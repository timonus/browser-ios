/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit
import Storage
import Shared
import CoreData

import Crashlytics
import XCGLogger

private let log = Logger.browserLogger

protocol BrowserHelper {
    static func scriptMessageHandlerName() -> String?
    func userContentController(userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage)
}


protocol BrowserDelegate {
    func browser(browser: Browser, didAddSnackbar bar: SnackBar)
    func browser(browser: Browser, didRemoveSnackbar bar: SnackBar)
    func browser(browser: Browser, didSelectFindInPageForSelection selection: String)
    func browser(browser: Browser, didCreateWebView webView: BraveWebView)
    func browser(browser: Browser, willDeleteWebView webView: BraveWebView)
}

struct DangerousReturnWKNavigation {
    static let emptyNav = WKNavigation()
}

class UIImageWithNotify {
    struct WeakImageView {
        weak var view : UIImageView?
        init(_ i: UIImageView?) {
            self.view = i
        }
    }
    var image: UIImage? {
        didSet {
            // notify listeners, and remove dead ones
            listenerImages = listenerImages.filter {
                $0.view?.image = image
                return $0.view != nil
            }
        }
    }
    var listenerImages = [WeakImageView]()
}

class Browser: NSObject, BrowserWebViewDelegate {
    private var _isPrivate: Bool = false
    internal private(set) var isPrivate: Bool {
        get {
            return _isPrivate
        }
        set {
            if newValue {
                PrivateBrowsing.singleton.enter()
            }
            else {
                PrivateBrowsing.singleton.exit()
            }
            _isPrivate = newValue
        }
    }

    private var _webView: BraveWebView?
    var webView: BraveWebView? {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        return _webView
    }


    // Wrap to indicate this is thread-safe (is called from networking thread), and to ensure safety.
    class BraveShieldStateSafeAsync {
        private var braveShieldState = BraveShieldState()
        private weak var browserTab: Browser?
        init(browser: Browser) {
            browserTab = browser
        }

        func set(state: BraveShieldState?) {
            objc_sync_enter(self)
            defer { objc_sync_exit(self) }

            braveShieldState = state != nil ? BraveShieldState(orig: state!) : BraveShieldState()

            // safely copy the currently set state, and copy it to the webview on the main thread
            let stateCopy = braveShieldState
            postAsyncToMain() { [weak browserTab] in
                browserTab?.webView?.setShieldStateSafely(stateCopy)
            }

            postAsyncToMain(0.2) { // update the UI, wait a bit for loading to have started
                (getApp().browserViewController as! BraveBrowserViewController).updateBraveShieldButtonState(animated: false)
            }
        }

        func get() -> BraveShieldState {
            objc_sync_enter(self)
            defer { objc_sync_exit(self) }
            
            return BraveShieldState(orig: braveShieldState)
        }
    }
    

    // Thread safe access to this property
    lazy var braveShieldStateSafeAsync: BraveShieldStateSafeAsync = {
        return BraveShieldStateSafeAsync(browser: self)
    }()

    var browserDelegate: BrowserDelegate?
    var bars = [SnackBar]()
    var favicons = [String:Favicon]() // map baseDomain() to favicon
    var lastExecutedTime: Timestamp?
    // This is messy in relation to the SavedTab tuple and should probably be abstracted into a single use item
    var sessionData: SessionData?
    var lastRequest: NSURLRequest? = nil
    var restoring: Bool = false
    var pendingScreenshot = false
    
    var tabID: String?

    /// The last title shown by this tab. Used by the tab tray to show titles for zombie tabs.
    var lastTitle: String?

    /// Whether or not the desktop site was requested with the last request, reload or navigation. Note that this property needs to
    /// be managed by the web view's navigation delegate.
    var desktopSite: Bool = false

    private(set) var screenshot = UIImageWithNotify()
    var screenshotUUID: NSUUID?

    private var helperManager: HelperManager? = nil
    private var configuration: WKWebViewConfiguration? = nil

    /// Any time a browser tries to make requests to display a Javascript Alert and we are not the active
    /// browser instance, queue it for later until we become foregrounded.
    private var alertQueue = [JSAlertInfo]()

    init(configuration: WKWebViewConfiguration, isPrivate: Bool) {
        self.configuration = configuration
        super.init()
        self.isPrivate = isPrivate
    }

#if BRAVE && IMAGE_SWIPE_ON
    let screenshotsForHistory = ScreenshotsForHistory()

    func screenshotForBackHistory() -> UIImage? {
        webView?.backForwardList.update()
        guard let prevLoc = webView?.backForwardList.backItem?.URL.absoluteString else { return nil }
        return screenshotsForHistory.get(prevLoc)
    }

    func screenshotForForwardHistory() -> UIImage? {
        webView?.backForwardList.update()
        guard let next = webView?.backForwardList.forwardItem?.URL.absoluteString else { return nil }
        return screenshotsForHistory.get(next)
    }
#endif

    class func toTab(browser: Browser) -> RemoteTab? {
        if let displayURL = browser.displayURL {
            let hl = browser.historyList;
            let history = Array(hl.filter(RemoteTab.shouldIncludeURL).reverse())
            return RemoteTab(clientGUID: nil,
                URL: displayURL,
                title: browser.displayTitle,
                history: history,
                lastUsed: NSDate.now(),
                icon: nil)
        } else if let sessionData = browser.sessionData  where !sessionData.urls.isEmpty {
            let history = Array(sessionData.urls.filter(RemoteTab.shouldIncludeURL).reverse())
            if let displayURL = history.first {
                return RemoteTab(clientGUID: nil,
                    URL: displayURL,
                    title: browser.displayTitle,
                    history: history,
                    lastUsed: sessionData.lastUsedTime,
                    icon: nil)
            }
        }

        return nil
    }

    weak var navigationDelegate: WKCompatNavigationDelegate? {
        didSet {
            if let webView = webView {
                webView.navigationDelegate = navigationDelegate
            }
        }
    }

    func createWebview(useDesktopUserAgent useDesktopUserAgent:Bool = false) {
        assert(NSThread.isMainThread())
        if !NSThread.isMainThread() {
            return
        }

        // self.webView setter/getter is thread-safe
        objc_sync_enter(self); defer { objc_sync_exit(self) }

        if webView == nil {
            let webView = createNewWebview(useDesktopUserAgent)
            helperManager = HelperManager(webView: webView)

            restore(webView, restorationData: self.sessionData?.savedTabData)

            _webView = webView
            notifyDelegateNewWebview()

            lastExecutedTime = NSDate.now()
        }
    }
    
    // Created for better debugging against cryptic crash report
    // Broke these into separate methods to increase data, can merge back to main method at some point
    private func createNewWebview(useDesktopUserAgent:Bool) -> BraveWebView {
        let webView = BraveWebView(frame: CGRectZero, useDesktopUserAgent: useDesktopUserAgent)
        configuration = nil
        
        BrowserTabToUAMapper.setId(webView.uniqueId, tab:self)
        
        webView.accessibilityLabel = Strings.Web_content
        
        // Turning off masking allows the web content to flow outside of the scrollView's frame
        // which allows the content appear beneath the toolbars in the BrowserViewController
        webView.scrollView.layer.masksToBounds = false
        webView.navigationDelegate = navigationDelegate
        return webView
    }
    
    private func notifyDelegateNewWebview() {
        guard let webview = self.webView else {
            Answers.logCustomEventWithName("WebView nil when attempting to notify delegate", customAttributes: nil)
            return
        }
        // Setup answers
        browserDelegate?.browser(self, didCreateWebView: webview)
    }
    // // // // // //

    func restore(webView: BraveWebView, restorationData: SavedTab?) {
        // Pulls restored session data from a previous SavedTab to load into the Browser. If it's nil, a session restore
        // has already been triggered via custom URL, so we use the last request to trigger it again; otherwise,
        // we extract the information needed to restore the tabs and create a NSURLRequest with the custom session restore URL
        // to trigger the session restore via custom handlers
        if let sessionData = restorationData {
            #if !BRAVE // no idea why restoring is needed, but it causes the displayed url not to update, which is bad
                restoring = true
            #endif
            lastTitle = sessionData.title
            if let title = lastTitle {
                webView.title = title
            }
            var updatedURLs = [String]()
            var prev = ""
            for urlString in sessionData.history {
                guard let url = NSURL(string: urlString) else { continue }
                let updatedURL = WebServer.sharedInstance.updateLocalURL(url)!.absoluteString
                guard let curr = updatedURL?.regexReplacePattern("https?:..", with: "") else { continue }
                if curr.characters.count > 1 && curr == prev {
                    updatedURLs.removeLast()
                }
                prev = curr
                updatedURLs.append(updatedURL!)
            }
            let currentPage = sessionData.historyIndex
            self.sessionData = nil
            var jsonDict = [String: AnyObject]()
            jsonDict["history"] = updatedURLs
            jsonDict["currentPage"] = Int(currentPage)
            let escapedJSON = JSON.stringify(jsonDict, pretty: false).stringByAddingPercentEncodingWithAllowedCharacters(NSCharacterSet.URLQueryAllowedCharacterSet())!
            let restoreURL = NSURL(string: "\(WebServer.sharedInstance.base)/about/sessionrestore?history=\(escapedJSON)")
            lastRequest = NSURLRequest(URL: restoreURL!)
            webView.loadRequest(lastRequest!)
        } else if let request = lastRequest {
            webView.loadRequest(request)
        } else {
            log.error("creating webview with no lastRequest and no session data: \(self.url)")
        }

    }

    func deleteWebView(isTabDeleted isTabDeleted: Bool) {
        assert(NSThread.isMainThread()) // to find and remove these cases in debug
        guard let wv = webView else { return }


        // self.webView setter/getter is thread-safe
        objc_sync_enter(self); defer { objc_sync_exit(self) }

            if !isTabDeleted {
                self.lastTitle = self.title
                let currentItem: LegacyBackForwardListItem! = wv.backForwardList.currentItem
                // Freshly created web views won't have any history entries at all.
                // If we have no history, abort.
                if currentItem != nil {
                    let backList = wv.backForwardList.backList ?? []
                    let forwardList = wv.backForwardList.forwardList ?? []
                    let urls = (backList + [currentItem] + forwardList).map { $0.URL }
                    let currentPage = -forwardList.count
                    
                    self.sessionData = SessionData(currentPage: currentPage, currentTitle: self.title, currentFavicon: self.displayFavicon, urls: urls, lastUsedTime: self.lastExecutedTime ?? NSDate.now())
                }
            }
            self.browserDelegate?.browser(self, willDeleteWebView: wv)
            _webView = nil

    }

    deinit {
        deleteWebView(isTabDeleted: true)
    }

    var loading: Bool {
        return webView?.loading ?? false
    }

    var estimatedProgress: Double {
        return webView?.estimatedProgress ?? 0
    }

    var backList: [LegacyBackForwardListItem]? {
        return webView?.backForwardList.backList
    }

    var forwardList: [LegacyBackForwardListItem]? {
        return webView?.backForwardList.forwardList
    }

    var historyList: [NSURL] {
        func listToUrl(item: LegacyBackForwardListItem) -> NSURL { return item.URL }
        var tabs = self.backList?.map(listToUrl) ?? [NSURL]()
        tabs.append(self.url!)
        return tabs
    }

    var title: String? {
        return webView?.title
    }

    var displayTitle: String {
        if let title = webView?.title where !title.isEmpty {
            return title
        }

        guard let lastTitle = lastTitle where !lastTitle.isEmpty else {
            return displayURL?.absoluteString ??  ""
        }

        return lastTitle
    }

    var currentInitialURL: NSURL? {
        get {
            let initalURL = self.webView?.backForwardList.currentItem?.initialURL
            return initalURL
        }
    }

    var displayFavicon: Favicon? {
        assert(NSThread.isMainThread())
        var width = 0
        var largest: Favicon?
        for icon in favicons {
            if icon.0 != webView?.URL?.normalizedHost() {
                continue
            }
            if icon.1.width > width {
                width = icon.1.width!
                largest = icon.1
            }
        }
        return largest ?? self.sessionData?.currentFavicon
    }
    
    var url: NSURL? {
        get {
            guard let resolvedURL = webView?.URL ?? lastRequest?.URL else {
                guard let sessionData = sessionData else { return nil }
                return sessionData.urls.last
            }
            return resolvedURL
        }
    }

    var displayURL: NSURL? {
        if let url = url {
            if ReaderModeUtils.isReaderModeURL(url) {
                return ReaderModeUtils.decodeURL(url)
            }

            if ErrorPageHelper.isErrorPageURL(url) {
                let decodedURL = ErrorPageHelper.originalURLFromQuery(url)
                if !AboutUtils.isAboutURL(decodedURL) {
                    return decodedURL
                } else {
                    return nil
                }
            }

            if let urlComponents = NSURLComponents(URL: url, resolvingAgainstBaseURL: false) where (urlComponents.user != nil) || (urlComponents.password != nil) {
                urlComponents.user = nil
                urlComponents.password = nil
                return urlComponents.URL
            }

            if let path = url.absoluteString where !AboutUtils.isAboutURL(url) && !path.contains(WebServer.sharedInstance.base) {
                return url
            }
        }
        return nil
    }

    var canGoBack: Bool {
        return webView?.canGoBack ?? false
    }

    var canGoForward: Bool {
        return webView?.canGoForward ?? false
    }

    func goBack() {
        let backUrl = webView?.backForwardList.backItem?.URL.absoluteString
        webView?.goBack()

        // UIWebView has a restoration bug, if the current page after restore is reader, and back is pressed, the page location
        // changes but the page doesn't reload with the new location
        guard let back = backUrl where back.contains("localhost") && back.contains("errors/error.html") else { return }

        if let url = url where ReaderModeUtils.isReaderModeURL(url) {
            postAsyncToMain(0.4) { [weak self] in
                let isReaderDoc = self?.webView?.stringByEvaluatingJavaScriptFromString("document.getElementById('reader-header') != null && document.getElementById('reader-content') != null") == "true"
                if (!isReaderDoc) {
                    return
                }
                guard let loc = self?.webView?.stringByEvaluatingJavaScriptFromString("location"),
                    url = NSURL(string:loc) else { return }

                if !ReaderModeUtils.isReaderModeURL(url) {
                    self?.reload()
                }
            }
        }
    }

    func goForward() {
        webView?.goForward()
    }

    func goToBackForwardListItem(item: LegacyBackForwardListItem) {
        webView?.goToBackForwardListItem(item)
    }

    func loadRequest(request: NSURLRequest) -> WKNavigation? {
        if let webView = webView {
            lastRequest = request
            webView.loadRequest(request)
            return DangerousReturnWKNavigation.emptyNav
        }
        return nil
    }

    func stop() {
        webView?.stopLoading()
    }

    func reload() {
        webView?.reloadFromOrigin()
    }

    func addHelper(helper: BrowserHelper) {
        helperManager!.addHelper(helper)
    }

    func getHelper<T>(classType: T.Type) -> T? {
        return helperManager?.getHelper(classType)
    }

    func removeHelper<T>(classType: T.Type) {
        helperManager?.removeHelper(classType)
    }

    func hideContent(animated: Bool = false) {
        webView?.userInteractionEnabled = false
        if animated {
            UIView.animateWithDuration(0.25, animations: { () -> Void in
                self.webView?.alpha = 0.0
            })
        } else {
            webView?.alpha = 0.0
        }
    }

    func showContent(animated: Bool = false) {
        webView?.userInteractionEnabled = true
        if animated {
            UIView.animateWithDuration(0.25, animations: { () -> Void in
                self.webView?.alpha = 1.0
            })
        } else {
            webView?.alpha = 1.0
        }
    }

    func addSnackbar(bar: SnackBar) {
        bars.append(bar)
        browserDelegate?.browser(self, didAddSnackbar: bar)
    }

    func removeSnackbar(bar: SnackBar) {
        if let index = bars.indexOf(bar) {
            bars.removeAtIndex(index)
            browserDelegate?.browser(self, didRemoveSnackbar: bar)
        }
    }

    func removeAllSnackbars() {
        // Enumerate backwards here because we'll remove items from the list as we go.
        for i in (0..<bars.count).reverse() {
            let bar = bars[i]
            removeSnackbar(bar)
        }
    }

    func expireSnackbars() {
        // Enumerate backwards here because we may remove items from the list as we go.
        for i in (0..<bars.count).reverse() {
            let bar = bars[i]
            if !bar.shouldPersist(self) {
                removeSnackbar(bar)
            }
        }
    }


    func setScreenshot(screenshot: UIImage?, revUUID: Bool = true) {
#if IMAGE_SWIPE_ON
        if let loc = webView?.URL?.absoluteString, screenshot = screenshot {
            screenshotsForHistory.addForLocation(loc, image: screenshot)
        }
#endif
        guard let screenshot = screenshot else { return }

        self.screenshot.image = screenshot
        if revUUID {
            self.screenshotUUID = NSUUID()
        }
    }

//    func toggleDesktopSite() {
//        desktopSite = !desktopSite
//        reload()
//    }

    func queueJavascriptAlertPrompt(alert: JSAlertInfo) {
        alertQueue.append(alert)
    }

    func dequeueJavascriptAlertPrompt() -> JSAlertInfo? {
        guard !alertQueue.isEmpty else {
            return nil
        }
        return alertQueue.removeFirst()
    }

    func cancelQueuedAlerts() {
        alertQueue.forEach { alert in
            alert.cancel()
        }
    }

    private func browserWebView(browserWebView: BrowserWebView, didSelectFindInPageForSelection selection: String) {
        browserDelegate?.browser(self, didSelectFindInPageForSelection: selection)
    }
}

private class HelperManager: NSObject, WKScriptMessageHandler {
    private var helpers = [String: BrowserHelper]()
    private weak var webView: BraveWebView?

    init(webView: BraveWebView) {
        self.webView = webView
    }

    @objc func userContentController(userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        for helper in helpers.values {
            if let scriptMessageHandlerName = helper.dynamicType.scriptMessageHandlerName() {
                if scriptMessageHandlerName == message.name {
                    helper.userContentController(userContentController, didReceiveScriptMessage: message)
                    return
                }
            }
        }
    }

    func addHelper(helper: BrowserHelper) {
        if let _ = helpers["\(helper.dynamicType)"] {
            assertionFailure("Duplicate helper added: \(helper.dynamicType)")
        }

        helpers["\(helper.dynamicType)"] = helper

        // If this helper handles script messages, then get the handler name and register it. The Browser
        // receives all messages and then dispatches them to the right BrowserHelper.
        if let scriptMessageHandlerName = helper.dynamicType.scriptMessageHandlerName() {
            webView?.configuration.userContentController.addScriptMessageHandler(self, name: scriptMessageHandlerName)
        }
    }

    func getHelper<T>(classType: T.Type) -> T? {
        return helpers["\(classType)"] as? T
    }

    func removeHelper<T>(classType: T.Type) {
        if let t = T.self as? BrowserHelper.Type, name = t.scriptMessageHandlerName() {
            webView?.configuration.userContentController.removeScriptMessageHandler(name: name)
        }
        helpers.removeValueForKey("\(classType)")
    }
}

private protocol BrowserWebViewDelegate: class {
    func browserWebView(browserWebView: BrowserWebView, didSelectFindInPageForSelection selection: String)
}

private class BrowserWebView: WKWebView, MenuHelperInterface {
    private weak var delegate: BrowserWebViewDelegate?

    override func canPerformAction(action: Selector, withSender sender: AnyObject?) -> Bool {
        return action == MenuHelper.SelectorFindInPage
    }

    @objc func menuHelperFindInPage(sender: NSNotification) {
        evaluateJavaScript("getSelection().toString()") { result, _ in
            let selection = result as? String ?? ""
            self.delegate?.browserWebView(self, didSelectFindInPageForSelection: selection)
        }
    }

    private override func hitTest(point: CGPoint, withEvent event: UIEvent?) -> UIView? {
        // The find-in-page selection menu only appears if the webview is the first responder.
        becomeFirstResponder()

        return super.hitTest(point, withEvent: event)
    }
}

