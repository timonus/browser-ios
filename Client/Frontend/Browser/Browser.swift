/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit
import Storage
import Shared
import CoreData
import SwiftyJSON

import Crashlytics
import XCGLogger

private let log = Logger.browserLogger

protocol BrowserHelper {
    static func scriptMessageHandlerName() -> String?
    func userContentController(_ userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage)
}

protocol BrowserDelegate {
    func browser(_ browser: Browser, didAddSnackbar bar: SnackBar)
    func browser(_ browser: Browser, didRemoveSnackbar bar: SnackBar)
    func browser(_ browser: Browser, didSelectFindInPageForSelection selection: String)
    func browser(_ browser: Browser, didCreateWebView webView: BraveWebView)
    func browser(_ browser: Browser, willDeleteWebView webView: BraveWebView)
}

struct DangerousReturnWKNavigation {
    static let emptyNav = WKNavigation()
}

class Browser: NSObject, BrowserWebViewDelegate {
    fileprivate var _isPrivate: Bool = false
    internal fileprivate(set) var isPrivate: Bool {
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

    fileprivate var _webView: BraveWebView?
    var webView: BraveWebView? {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        return _webView
    }


    // Wrap to indicate this is thread-safe (is called from networking thread), and to ensure safety.
    class BraveShieldStateSafeAsync {
        fileprivate var braveShieldState = BraveShieldState()
        fileprivate weak var browserTab: Browser?
        init(browser: Browser) {
            browserTab = browser
        }

        func set(_ state: BraveShieldState?) {
            objc_sync_enter(self)
            defer { objc_sync_exit(self) }

            braveShieldState = state != nil ? BraveShieldState(orig: state!) : BraveShieldState()

            // safely copy the currently set state, and copy it to the webview on the main thread
            let stateCopy = braveShieldState
            postAsyncToMain() { [weak browserTab] in
                browserTab?.webView?.setShieldStateSafely(stateCopy)
            }

            postAsyncToMain(0.2) { // update the UI, wait a bit for loading to have started
                (getApp().browserViewController as! BraveBrowserViewController).updateBraveShieldButtonState(false)
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
    var lastRequest: URLRequest? = nil
    var restoring: Bool = false
    var pendingScreenshot = false
    
    var tabID: String?

    /// The last title shown by this tab. Used by the tab tray to show titles for zombie tabs.
    var lastTitle: String?

    /// Whether or not the desktop site was requested with the last request, reload or navigation. Note that this property needs to
    /// be managed by the web view's navigation delegate.
    var desktopSite: Bool = false

    fileprivate var screenshotCallback: ((_ image: UIImage?)->Void)?
    fileprivate var _screenshot: UIImage?
    var screenshotUUID: UUID?

    fileprivate var helperManager: HelperManager? = nil
    fileprivate var configuration: WKWebViewConfiguration? = nil

    /// Any time a browser tries to make requests to display a Javascript Alert and we are not the active
    /// browser instance, queue it for later until we become foregrounded.
    fileprivate var alertQueue = [JSAlertInfo]()

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
    
    func screenshot(callback: ((_ image: UIImage?)->Void)?) {
        screenshotCallback = callback
        
        guard let callback = callback else { return }
        if let id = tabID, let tab = TabMO.getByID(id), let url = tab.imageUrl {
            weak var weakSelf = self
            ImageCache.shared.image(url, callback: { (image) in
                weakSelf?._screenshot = image
                postAsyncToMain {
                    callback(image)
                }
            })
        }
    }

    class func toTab(_ browser: Browser) -> RemoteTab? {
        if let displayURL = browser.displayURL {
            let hl = browser.historyList;
            let history = Array(hl.filter(RemoteTab.shouldIncludeURL).reversed())
            return RemoteTab(clientGUID: nil,
                URL: displayURL,
                title: browser.displayTitle,
                history: history,
                lastUsed: Date.now(),
                icon: nil)
        } else if let sessionData = browser.sessionData, !sessionData.urls.isEmpty {
            let history = Array(sessionData.urls.filter(RemoteTab.shouldIncludeURL).reversed())
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

    func createWebview(_ useDesktopUserAgent:Bool = false) {
        assert(Thread.isMainThread)
        if !Thread.isMainThread {
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

            lastExecutedTime = Date.now()
        }
    }
    
    // Created for better debugging against cryptic crash report
    // Broke these into separate methods to increase data, can merge back to main method at some point
    fileprivate func createNewWebview(_ useDesktopUserAgent:Bool) -> BraveWebView {
        let webView = BraveWebView(frame: CGRect.zero, useDesktopUserAgent: useDesktopUserAgent)
        configuration = nil
        
        BrowserTabToUAMapper.setId(webView.uniqueId, tab:self)
        
        webView.accessibilityLabel = Strings.Web_content
        
        // Turning off masking allows the web content to flow outside of the scrollView's frame
        // which allows the content appear beneath the toolbars in the BrowserViewController
        webView.scrollView.layer.masksToBounds = false
        webView.navigationDelegate = navigationDelegate
        return webView
    }
    
    fileprivate func notifyDelegateNewWebview() {
        guard let webview = self.webView else {
            Answers.logCustomEvent(withName: "WebView nil when attempting to notify delegate", customAttributes: nil)
            return
        }
        // Setup answers
        browserDelegate?.browser(self, didCreateWebView: webview)
    }
    // // // // // //

    func restore(_ webView: BraveWebView, restorationData: SavedTab?) {
        // Pulls restored session data from a previous SavedTab to load into the Browser. If it's nil, a session restore
        // has already been triggered via custom URL, so we use the last request to trigger it again; otherwise,
        // we extract the information needed to restore the tabs and create a NSURLRequest with the custom session restore URL
        // to trigger the session restore via custom handlers
        if let sessionData = restorationData {
            lastTitle = sessionData.title
            if let title = lastTitle {
                webView.title = title
            }
            var updatedURLs = [String]()
            var prev = ""
            for urlString in sessionData.history {
                guard let url = URL(string: urlString) else { continue }
                let updatedURL = WebServer.sharedInstance.updateLocalURL(url)!.absoluteString
                let curr = updatedURL.regexReplacePattern("https?:..", with: "")
                if curr.characters.count > 1 && curr == prev {
                    updatedURLs.removeLast()
                }
                prev = curr
                updatedURLs.append(updatedURL)
            }
            let currentPage = sessionData.historyIndex
            self.sessionData = nil
            var jsonDict = [String: AnyObject]()
            jsonDict["history"] = updatedURLs as AnyObject
            jsonDict["currentPage"] = Int(currentPage) as AnyObject
            
            guard let escapedJSON = JSON(jsonDict).rawString()?.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) else {
                return
            }
            
            guard let restoreURL = URL(string: "\(WebServer.sharedInstance.base)/about/sessionrestore?history=\(escapedJSON)") else {
                return
            }
            
            lastRequest = URLRequest(url: restoreURL)
            webView.loadRequest(lastRequest!)
        } else if let request = lastRequest {
            webView.loadRequest(request)
        } else {
            log.error("creating webview with no lastRequest and no session data: \(self.url)")
        }

    }

    func deleteWebView(_ isTabDeleted: Bool) {
        assert(Thread.isMainThread) // to find and remove these cases in debug
        guard let wv = webView else { return }


        // self.webView setter/getter is thread-safe
        objc_sync_enter(self); defer { objc_sync_exit(self) }

            if !isTabDeleted {
                self.lastTitle = self.title
                let currentItem: LegacyBackForwardListItem! = wv.backForwardList.currentItem
                // Freshly created web views won't have any history entries at all.
                // If we have no history, abort.
                if currentItem != nil {
                    let backList = wv.backForwardList.backList 
                    let forwardList = wv.backForwardList.forwardList 
                    let urls = (backList + [currentItem] + forwardList).map { $0.URL }
                    let currentPage = -forwardList.count
                    
                    self.sessionData = SessionData(currentPage: currentPage, currentTitle: self.title, currentFavicon: self.displayFavicon, urls: urls, lastUsedTime: self.lastExecutedTime ?? Date.now())
                }
            }
            self.browserDelegate?.browser(self, willDeleteWebView: wv)
            _webView = nil

    }

    deinit {
        deleteWebView(true)
    }

    var loading: Bool {
        return webView?.isLoading ?? false
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

    var historyList: [URL] {
        func listToUrl(_ item: LegacyBackForwardListItem) -> URL { return item.URL as URL }
        var tabs = self.backList?.map(listToUrl) ?? [URL]()
        tabs.append(self.url!)
        return tabs
    }

    var title: String? {
        return webView?.title
    }

    var displayTitle: String {
        if let title = webView?.title, !title.isEmpty {
            return title
        }

        guard let lastTitle = lastTitle, !lastTitle.isEmpty else {
            return displayURL?.absoluteString ??  ""
        }

        return lastTitle
    }

    var currentInitialURL: URL? {
        get {
            let initalURL = self.webView?.backForwardList.currentItem?.initialURL
            return initalURL
        }
    }

    var displayFavicon: Favicon? {
        assert(Thread.isMainThread)
        var width = 0
        var largest: Favicon?
        for icon in favicons {
            if icon.0 != webView?.URL?.normalizedHost {
                continue
            }
            if icon.1.width! > width {
                width = icon.1.width!
                largest = icon.1
            }
        }
        return largest ?? self.sessionData?.currentFavicon
    }
    
    var url: URL? {
        get {
            guard let resolvedURL = webView?.URL ?? lastRequest?.url else {
                guard let sessionData = sessionData else { return nil }
                return sessionData.urls.last
            }
            return resolvedURL
        }
    }

    var displayURL: URL? {
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

            if var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false), (urlComponents.user != nil) || (urlComponents.password != nil) {
                urlComponents.user = nil
                urlComponents.password = nil
                return urlComponents.url
            }

            if !AboutUtils.isAboutURL(url) && !url.absoluteString.contains(WebServer.sharedInstance.base) {
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
        guard let back = backUrl, back.contains("localhost") && back.contains("errors/error.html") else { return }

        if let url = url, ReaderModeUtils.isReaderModeURL(url) {
            postAsyncToMain(0.4) { [weak self] in
                let isReaderDoc = self?.webView?.stringByEvaluatingJavaScript(from: "document.getElementById('reader-header') != null && document.getElementById('reader-content') != null") == "true"
                if (!isReaderDoc) {
                    return
                }
                guard let loc = self?.webView?.stringByEvaluatingJavaScript(from: "location"),
                    let url = URL(string:loc) else { return }

                if !ReaderModeUtils.isReaderModeURL(url) {
                    self?.reload()
                }
            }
        }
    }

    func goForward() {
        webView?.goForward()
    }

    func goToBackForwardListItem(_ item: LegacyBackForwardListItem) {
        webView?.goToBackForwardListItem(item)
    }

    @discardableResult func loadRequest(_ request: URLRequest) -> WKNavigation? {
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

    func addHelper(_ helper: BrowserHelper) {
        helperManager!.addHelper(helper)
    }

    func getHelper<T>(_ classType: T.Type) -> T? {
        return helperManager?.getHelper(classType)
    }

    func removeHelper<T>(_ classType: T.Type) {
        helperManager?.removeHelper(classType)
    }

    func hideContent(_ animated: Bool = false) {
        webView?.isUserInteractionEnabled = false
        if animated {
            UIView.animate(withDuration: 0.25, animations: { () -> Void in
                self.webView?.alpha = 0.0
            })
        } else {
            webView?.alpha = 0.0
        }
    }

    func showContent(_ animated: Bool = false) {
        webView?.isUserInteractionEnabled = true
        if animated {
            UIView.animate(withDuration: 0.25, animations: { () -> Void in
                self.webView?.alpha = 1.0
            })
        } else {
            webView?.alpha = 1.0
        }
    }

    func addSnackbar(_ bar: SnackBar) {
        bars.append(bar)
        browserDelegate?.browser(self, didAddSnackbar: bar)
    }

    func removeSnackbar(_ bar: SnackBar) {
        if let index = bars.index(of: bar) {
            bars.remove(at: index)
            browserDelegate?.browser(self, didRemoveSnackbar: bar)
        }
    }

    func removeAllSnackbars() {
        // Enumerate backwards here because we'll remove items from the list as we go.
        for i in (0..<bars.count).reversed() {
            let bar = bars[i]
            removeSnackbar(bar)
        }
    }

    func expireSnackbars() {
        // Enumerate backwards here because we may remove items from the list as we go.
        for i in (0..<bars.count).reversed() {
            let bar = bars[i]
            if !bar.shouldPersist(self) {
                removeSnackbar(bar)
            }
        }
    }


    func setScreenshot(_ screenshot: UIImage?, revUUID: Bool = true) {
#if IMAGE_SWIPE_ON
        if let loc = webView?.URL?.absoluteString, let screenshot = screenshot {
            screenshotsForHistory.addForLocation(loc, image: screenshot)
        }
#endif
        guard let screenshot = screenshot else { return }

        _screenshot = screenshot
        self.screenshotCallback?(screenshot)
        
        if revUUID {
            screenshotUUID = UUID()
        }
        
        if let tab = TabMO.getByID(tabID), let url = tab.imageUrl {
            ImageCache.shared.cache(screenshot, url: url, callback: {
                debugPrint("Cached screenshot.")
            })
        }
    }

    func queueJavascriptAlertPrompt(_ alert: JSAlertInfo) {
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

    fileprivate func browserWebView(_ browserWebView: BrowserWebView, didSelectFindInPageForSelection selection: String) {
        browserDelegate?.browser(self, didSelectFindInPageForSelection: selection)
    }
}

private class HelperManager: NSObject, WKScriptMessageHandler {
    fileprivate var helpers = [String: BrowserHelper]()
    fileprivate weak var webView: BraveWebView?

    init(webView: BraveWebView) {
        self.webView = webView
    }

    @objc func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        for helper in helpers.values {
            if let scriptMessageHandlerName = type(of: helper).scriptMessageHandlerName() {
                if scriptMessageHandlerName == message.name {
                    helper.userContentController(userContentController, didReceiveScriptMessage: message)
                    return
                }
            }
        }
    }

    func addHelper(_ helper: BrowserHelper) {
        if let _ = helpers["\(type(of: helper))"] {
            assertionFailure("Duplicate helper added: \(type(of: helper))")
        }

        helpers["\(type(of: helper))"] = helper

        // If this helper handles script messages, then get the handler name and register it. The Browser
        // receives all messages and then dispatches them to the right BrowserHelper.
        if let scriptMessageHandlerName = type(of: helper).scriptMessageHandlerName() {
            webView?.configuration.userContentController.addScriptMessageHandler(self, name: scriptMessageHandlerName)
        }
    }

    func getHelper<T>(_ classType: T.Type) -> T? {
        return helpers["\(classType)"] as? T
    }

    func removeHelper<T>(_ classType: T.Type) {
        if let t = T.self as? BrowserHelper.Type, let name = t.scriptMessageHandlerName() {
            webView?.configuration.userContentController.removeScriptMessageHandler(name)
        }
        helpers.removeValue(forKey: "\(classType)")
    }
}

private protocol BrowserWebViewDelegate: class {
    func browserWebView(_ browserWebView: BrowserWebView, didSelectFindInPageForSelection selection: String)
}

private class BrowserWebView: WKWebView, MenuHelperInterface {
    fileprivate weak var delegate: BrowserWebViewDelegate?

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return action == MenuHelper.SelectorFindInPage
    }

    @objc func menuHelperFindInPage(_ sender: Notification) {
        evaluateJavaScript("getSelection().toString()") { result, _ in
            let selection = result as? String ?? ""
            self.delegate?.browserWebView(self, didSelectFindInPageForSelection: selection)
        }
    }

    fileprivate override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // The find-in-page selection menu only appears if the webview is the first responder.
        becomeFirstResponder()

        return super.hitTest(point, with: event)
    }
}

