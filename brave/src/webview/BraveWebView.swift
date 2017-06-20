/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit
import Shared
import JavaScriptCore
// FIXME: comparison operators with optionals were removed from the Swift Standard Libary.
// Consider refactoring the code to use the non-optional operators.
fileprivate func < <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l < r
  case (nil, _?):
    return true
  default:
    return false
  }
}

// FIXME: comparison operators with optionals were removed from the Swift Standard Libary.
// Consider refactoring the code to use the non-optional operators.
fileprivate func > <T : Comparable>(lhs: T?, rhs: T?) -> Bool {
  switch (lhs, rhs) {
  case let (l?, r?):
    return l > r
  default:
    return rhs < lhs
  }
}


let kNotificationPageUnload = "kNotificationPageUnload"
let kNotificationAllWebViewsDeallocated = "kNotificationAllWebViewsDeallocated"

func convertNavActionToWKType(_ type:UIWebViewNavigationType) -> WKNavigationType {
    return WKNavigationType(rawValue: type.rawValue)!
}

class ContainerWebView : WKWebView {
    weak var legacyWebView: BraveWebView?
}

var globalContainerWebView = ContainerWebView()

protocol WebPageStateDelegate : class {
    func webView(_ webView: UIWebView, progressChanged: Float)
    func webView(_ webView: UIWebView, isLoading: Bool)
    func webView(_ webView: UIWebView, urlChanged: String)
    func webView(_ webView: UIWebView, canGoBack: Bool)
    func webView(_ webView: UIWebView, canGoForward: Bool)
}


@objc class HandleJsWindowOpen : NSObject {
    static func open(_ url: String) {
        postAsyncToMain(0) { // we now know JS callbacks can be off main
            guard let wv = BraveApp.getCurrentWebView() else { return }
            let current = wv.URL
            print("window.open")
            if BraveApp.getPrefs()?.boolForKey("blockPopups") ?? true {
                guard let lastTappedTime = wv.lastTappedTime else { return }
                if fabs(lastTappedTime.timeIntervalSinceNow) > 0.75 { // outside of the 3/4 sec time window and we ignore it
                    print(lastTappedTime.timeIntervalSinceNow)
                    return
                }
            }
            wv.lastTappedTime = nil
            if let _url = URL(string: url, relativeTo: current) {
                getApp().browserViewController.openURLInNewTab(_url)
            }
        }
    }
}

class BrowserTabToUAMapper {
    static fileprivate let idToBrowserTab = NSMapTable(keyOptions: NSPointerFunctions.Options(), valueOptions: .weakMemory)

    static func setId(_ uniqueId: Int, tab: Browser) {
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }
        idToBrowserTab.setObject(tab, forKey: uniqueId)
    }

    static func userAgentToBrowserTab(_ ua: String?) -> Browser? {
        // synchronize code from this point on.
        objc_sync_enter(self)
        defer { objc_sync_exit(self) }

        guard let ua = ua else { return nil }
        guard let loc = ua.range(of: "_id/") else {
            // the first created webview doesn't have this id set (see webviewBuiltinUserAgent to explain)
            return idToBrowserTab.object(forKey: 1) as? Browser
        }
        let keyString = ua.substring(with: loc.upperBound..<loc.index(loc.upperBound, offsetBy: 6))
        guard let key = Int(keyString) else { return nil }
        return idToBrowserTab.object(forKey: key) as? Browser
    }
}

struct BraveWebViewConstants {
    static let kNotificationWebViewLoadCompleteOrFailed = "kNotificationWebViewLoadCompleteOrFailed"
    static let kNotificationPageInteractive = "kNotificationPageInteractive"
    static let kContextMenuBlockNavigation = 8675309
}

class BraveWebView: UIWebView {
    class Weak_WebPageStateDelegate {     // We can't use a WeakList here because this is a protocol.
        weak var value : WebPageStateDelegate?
        init (value: WebPageStateDelegate) { self.value = value }
    }
    var delegatesForPageState = [Weak_WebPageStateDelegate]()

    let usingDesktopUserAgent: Bool
    let specialStopLoadUrl = "http://localhost.stop.load"
    weak var navigationDelegate: WKCompatNavigationDelegate?

    lazy var configuration: BraveWebViewConfiguration = { return BraveWebViewConfiguration(webView: self) }()
    lazy var backForwardList: WebViewBackForwardList = { return WebViewBackForwardList(webView: self) } ()
    var progress: WebViewProgress?
    var certificateInvalidConnection:NSURLConnection?

    var uniqueId = -1
    var knownFrameContexts = Set<NSObject>()
    fileprivate static var containerWebViewForCallbacks = { return ContainerWebView() }()
    // From http://stackoverflow.com/questions/14268230/has-anybody-found-a-way-to-load-https-pages-with-an-invalid-server-certificate-u
    var loadingUnvalidatedHTTPSPage: Bool = false



    var blankTargetLinkDetectionOn = true
    var lastTappedTime: Date?
    var removeBvcObserversOnDeinit: ((UIWebView) -> Void)?
    var removeProgressObserversOnDeinit: ((UIWebView) -> Void)?

    var safeBrowsingBlockTriggered:Bool = false
    
    var estimatedProgress: Double = 0
    var title: String = "" {
        didSet {
            if let item = backForwardList.currentItem {
                item.title = title
            }
        }
    }

    fileprivate var _url: (url: Foundation.URL?, prevUrl: Foundation.URL?) = (nil, nil)

    fileprivate var lastBroadcastedKvoUrl: String = ""
    // return true if set, false if unchanged
    func setUrl( _ newUrl: Foundation.URL?) -> Bool {
        guard var newUrl = newUrl, let urlString = newUrl.absoluteString, !urlString.isEmpty else { return false }

        if urlString.endsWith("?") {
            if let noEndingQ = URL?.absoluteString.components(separatedBy: "?")[0] {
                newUrl = Foundation.URL(string: noEndingQ) ?? newUrl
            }
        }

        if urlString == _url.url?.absoluteString {
            return false
        }

        _url.prevUrl = _url.url
        _url.url = newUrl

        if urlString != lastBroadcastedKvoUrl {
            delegatesForPageState.forEach { $0.value?.webView(self, urlChanged: urlString) }
            lastBroadcastedKvoUrl = urlString
        }

        return true
    }

    var previousUrl: Foundation.URL? { get { return _url.prevUrl } }

    var URL: Foundation.URL? {
        get {
            return _url.url
        }
    }

    func updateLocationFromHtml() -> Bool {
        guard let js = stringByEvaluatingJavaScript(from: "document.location.href"), let location = Foundation.URL(string: js) else { return false }
        
        // Must be in same domain space to allow document location changes
        if location.baseDomain != self.URL?.baseDomain || !location.schemeIsValid {
            return false
        }
        
        print(location.domainURL)
        if AboutUtils.isAboutHomeURL(location) {
            return false
        }
        return setUrl(location)
    }

    fileprivate static var webviewBuiltinUserAgent = UserAgent.defaultUserAgent()

    // Needed to identify webview in url protocol
    func generateUniqueUserAgent() {
        struct StaticCounter {
            static var counter = 0
        }

        StaticCounter.counter += 1
        let userAgentBase = usingDesktopUserAgent ? kDesktopUserAgent : BraveWebView.webviewBuiltinUserAgent
        let userAgent = userAgentBase + String(format:" _id/%06d", StaticCounter.counter)
        let defaults = UserDefaults(suiteName: AppInfo.sharedContainerIdentifier)!
        defaults.register(defaults: ["UserAgent": userAgent ])
        self.uniqueId = StaticCounter.counter
    }

    fileprivate var braveShieldState = BraveShieldState()
    fileprivate func internalSetBraveShieldStateForDomain(_ domain: String) {
        braveShieldState = BraveShieldState.perNormalizedDomain[domain] ?? BraveShieldState()

        // we need to propagate this change to the thread-safe wrapper
        let stateCopy = braveShieldState
        let browserTab = getApp().tabManager.tabForWebView(self)
        postAsyncToMain() {
            browserTab?.braveShieldStateSafeAsync.set(stateCopy)
        }
    }

    func setShieldStateSafely(_ state: BraveShieldState) {
        assert(Thread.isMainThread)
        if (!Thread.isMainThread) { return }
        braveShieldState = state
    }

    var triggeredLocationCheckTimer = Timer()
    // On page load, the contentSize of the webview is updated (**). If the webview has not been notified of a page change (i.e. shouldStartLoadWithRequest was never called) then 'loading' will be false, and we should check the page location using JS.
    // (** Not always updated, particularly on back/forward. For instance load duckduckgo.com, then google.com, and go back. No content size change detected.)
    func contentSizeChangeDetected() {
        if triggeredLocationCheckTimer.isValid {
            return
        }

        // Add a time delay so that multiple calls are aggregated
        triggeredLocationCheckTimer = Timer.scheduledTimer(timeInterval: 0.15, target: self, selector: #selector(timeoutCheckLocation), userInfo: nil, repeats: false)
    }

    // Pushstate navigation may require this case (see brianbondy.com), as well as sites for which simple pushstate detection doesn't work:
    // youtube and yahoo news are examples of this (http://stackoverflow.com/questions/24297929/javascript-to-listen-for-url-changes-in-youtube-html5-player)
    @objc func timeoutCheckLocation() {
        assert(Thread.isMainThread)

        if URL?.isSpecialInternalUrl() ?? true {
            return
        }

        if !updateLocationFromHtml() {
            return
        }

        // print("Page change detected by content size change triggered timer: \(URL?.absoluteString ?? "")")

        NotificationCenter.default.post(name: Notification.Name(rawValue: kNotificationPageUnload), object: self)
        shieldStatUpdate(.reset)
        progress?.reset()

        if (!isLoading ||
            stringByEvaluatingJavaScript(from: "document.readyState.toLowerCase()") == "complete")
        {
            progress?.completeProgress()
        } else {
            progress?.setProgress(0.3)
            delegatesForPageState.forEach { $0.value?.webView(self, progressChanged: 0.3) }
        }
    }

    func updateTitleFromHtml() {
        if URL?.isSpecialInternalUrl() ?? false {
            title = ""
            return
        }
        if let t = stringByEvaluatingJavaScript(from: "document.title"), !t.isEmpty {
            title = t
        } else {
            title = URL?.baseDomain ?? ""
        }
    }

    required init(frame: CGRect, useDesktopUserAgent: Bool) {
        self.usingDesktopUserAgent = useDesktopUserAgent
        super.init(frame: frame)
        commonInit()
    }

    static var allocCounter = 0

    fileprivate func commonInit() {
        BraveWebView.allocCounter += 1
        print("webview init  \(BraveWebView.allocCounter)")
        generateUniqueUserAgent()

        progress = WebViewProgress(parent: self)

        mediaPlaybackRequiresUserAction = true
        delegate = self
        scalesPageToFit = true
        scrollView.showsHorizontalScrollIndicator = false
        allowsInlineMediaPlayback = true
        isOpaque = false
        backgroundColor = UIColor.white

        let rate = UIScrollViewDecelerationRateFast + (UIScrollViewDecelerationRateNormal - UIScrollViewDecelerationRateFast) * 0.5;
            scrollView.setValue(NSValue(cgSize: CGSize(width: rate, height: rate)), forKey: "_decelerationFactor")

        NotificationCenter.default.addObserver(self, selector: #selector(firstLayoutPerformed), name: NSNotification.Name(rawValue: swizzledFirstLayoutNotification), object: nil)
    }

    func firstLayoutPerformed() {
        updateLocationFromHtml()
    }

    var jsBlockedStatLastUrl: String? = nil
    func checkScriptBlockedAndBroadcastStats() {
        let state = braveShieldState
        if state.isOnScriptBlocking() ?? BraveApp.getPrefs()?.boolForKey(kPrefKeyNoScriptOn) ?? false {
            let jsBlocked = Int(stringByEvaluatingJavaScript(from: "document.getElementsByTagName('script').length") ?? "0") ?? 0

            if request?.url?.absoluteString == jsBlockedStatLastUrl && jsBlocked == 0 {
                return
            }
            jsBlockedStatLastUrl = request?.url?.absoluteString

            shieldStatUpdate(.jsSetValue, increment: jsBlocked)
        } else {
            shieldStatUpdate(.broadcastOnly)
        }
    }

    func internalProgressNotification(_ notification: Notification) {
        if let prog = notification.userInfo?["WebProgressEstimatedProgressKey"] as? Double {
            progress?.setProgress(prog)
            if prog > 0.99 {
                loadingCompleted()
            }
        }
    }

    override var isLoading: Bool {
        get {
            return estimatedProgress > 0 && estimatedProgress < 0.99
        }
    }

    required init?(coder aDecoder: NSCoder) {
        self.usingDesktopUserAgent = false
        super.init(coder: aDecoder)
        commonInit()
    }

    deinit {
        BraveWebView.allocCounter -= 1
        if (BraveWebView.allocCounter == 0) {
            NotificationCenter.default.post(name: Notification.Name(rawValue: kNotificationAllWebViewsDeallocated), object: nil)
            print("NO LIVE WEB VIEWS")
        }

        NotificationCenter.default.removeObserver(self)

        _ = Try(withTry: {
            self.removeBvcObserversOnDeinit?(self)
        }) { (exception) -> Void in
            print("Failed remove: \(exception)")
        }

        _ = Try(withTry: {
            self.removeProgressObserversOnDeinit?(self)
        }) { (exception) -> Void in
            print("Failed remove: \(exception)")
        }

        print("webview deinit \(title) ")
    }

    var blankTargetUrl: String?

    let internalProgressStartedNotification = "WebProgressStartedNotification"
    let internalProgressChangedNotification = "WebProgressEstimateChangedNotification"
    let internalProgressFinishedNotification = "WebProgressFinishedNotification" // Not usable

    let swizzledFirstLayoutNotification = "WebViewFirstLayout" // not broadcast on history push nav

    override func loadRequest(_ request: URLRequest) {
        clearLoadCompletedHtmlProperty()

        guard let internalWebView = value(forKeyPath: "documentView.webView") else { return }
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: internalProgressChangedNotification), object: internalWebView)
        NotificationCenter.default.addObserver(self, selector: #selector(BraveWebView.internalProgressNotification(_:)), name: NSNotification.Name(rawValue: internalProgressChangedNotification), object: internalWebView)

        if let url = request.url {
            internalSetBraveShieldStateForDomain(url.normalizedHost!)
        }
        super.loadRequest(request)
    }

    enum LoadCompleteHtmlPropertyOption {
        case setCompleted, checkIsCompleted, clear, debug
    }

    // Not pretty, but we set some items on the page to know when the load completion arrived
    // You would think the DOM gets refreshed on page change, but not with modern js lib navigation
    // Domain changes will reset the DOM, which is easily to detect, but path changes require a few properties to reliably detect
    func loadCompleteHtmlProperty(option: LoadCompleteHtmlPropertyOption) -> Bool {
        let sentinels = ["_brave_cached_title": "document.title", "_brave_cached_location" : "location.href"]

        if option == .debug {
            let js = sentinels.values.joined(separator: ",")
            print(stringByEvaluatingJavaScript(from: "JSON.stringify({ \(js) })"))
            return false
        }

        let oper = (option != .checkIsCompleted) ? " = " : " === "
        let joiner = (option != .checkIsCompleted) ? "; " : " && "

        var js = sentinels.map{ $0 + oper + (option == .clear ? "''" :$1) }.joined(separator: joiner)
        if option == .checkIsCompleted {
            js = "('_brave_cached_title' in window) && \(js) "
        }
        return stringByEvaluatingJavaScript(from: js) == "true"
    }

    fileprivate func isLoadCompletedHtmlPropertySet() -> Bool {
        return loadCompleteHtmlProperty(option: .checkIsCompleted)
    }

    fileprivate func setLoadCompletedHtmlProperty() {
        loadCompleteHtmlProperty(option: .setCompleted)
    }

    fileprivate func clearLoadCompletedHtmlProperty() {
        loadCompleteHtmlProperty(option: .clear)
    }

    func loadingCompleted() {
        if isLoadCompletedHtmlPropertySet() {
            return
        }
        setLoadCompletedHtmlProperty()

        print("loadingCompleted() ••••")
        progress?.setProgress(1.0)
        broadcastToPageStateDelegates()

        navigationDelegate?.webViewDidFinishNavigation(self, url: URL)

        if safeBrowsingBlockTriggered {
            return
        }

        // Wait a tiny bit in hopes the page contents are updated. Load completed doesn't mean the UIWebView has done any rendering (or even has the JS engine for the page ready, see the delay() below)
        postAsyncToMain(0.1) {
            [weak self] in
            guard let me = self, let tab = getApp().tabManager.tabForWebView(me) else {
                    return
            }

            me.updateLocationFromHtml()
            me.updateTitleFromHtml()
            tab.lastExecutedTime = Date.now()
            getApp().browserViewController.updateProfileForLocationChange(tab)

            me.configuration.userContentController.injectJsIntoPage()
            NotificationCenter.default.post(name: Notification.Name(rawValue: BraveWebViewConstants.kNotificationWebViewLoadCompleteOrFailed), object: me)
            LegacyUserContentController.injectJsIntoAllFrames(me, script: "document.body.style.webkitTouchCallout='none'")

            me.stringByEvaluatingJavaScript(from: "console.log('get favicons'); __firefox__.favicons.getFavicons()")

            postAsyncToMain(0.3) { // the longer we wait, the more reliable the result (even though this script does polling for a result)
                [weak self] in
                let readerjs = ReaderModeNamespace + ".checkReadability()"
                self?.stringByEvaluatingJavaScript(from: readerjs)
            }

            me.checkScriptBlockedAndBroadcastStats()

            getApp().tabManager.expireSnackbars()
            getApp().browserViewController.screenshotHelper.takeDelayedScreenshot(tab)
            getApp().browserViewController.addOpenInViewIfNeccessary(tab.url)
        }
    }

    // URL changes are NOT broadcast here. Have to be selective with those until the receiver code is improved to be more careful about updating
    func broadcastToPageStateDelegates() {
        delegatesForPageState.forEach {
            $0.value?.webView(self, isLoading: isLoading)
            $0.value?.webView(self, canGoBack: canGoBack)
            $0.value?.webView(self, canGoForward: canGoForward)
            $0.value?.webView(self, progressChanged: isLoading ? Float(estimatedProgress) : 1.0)
        }
    }

    func canNavigateBackward() -> Bool {
        return self.canGoBack
    }

    func canNavigateForward() -> Bool {
        return self.canGoForward
    }

    func reloadFromOrigin() {
        self.reload()
    }

    override func reload() {
        clearLoadCompletedHtmlProperty()
        shieldStatUpdate(.reset)
        progress?.setProgress(0.3)
        URLCache.shared.removeAllCachedResponses()
        URLCache.shared.diskCapacity = 0
        URLCache.shared.memoryCapacity = 0

        if let url = URL {
            internalSetBraveShieldStateForDomain(url.normalizedHost!)
            (getApp().browserViewController as! BraveBrowserViewController).updateBraveShieldButtonState(false)
        }
        super.reload()
        
        BraveApp.setupCacheDefaults()
    }

    override func stopLoading() {
        super.stopLoading()
        self.progress?.reset()
    }

    fileprivate func convertStringToDictionary(_ text: String?) -> [String:AnyObject]? {
        if let data = text?.data(using: String.Encoding.utf8), text?.characters.count > 0 {
            do {
                let json = try JSONSerialization.jsonObject(with: data, options: .mutableContainers) as? [String:AnyObject]
                return json
            } catch {
                print("Something went wrong")
            }
        }
        return nil
    }

    func evaluateJavaScript(_ javaScriptString: String, completionHandler: ((AnyObject?, NSError?) -> Void)?) {
        postAsyncToMain(0) { // evaluateJavaScript is for compat with WKWebView/Firefox, I didn't vet all the uses, guard by posting to main
            let wrapped = "var result = \(javaScriptString); JSON.stringify(result)"
            let string = self.stringByEvaluatingJavaScript(from: wrapped)
            let dict = self.convertStringToDictionary(string)
            completionHandler?(dict as AnyObject, NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotOpenFile, userInfo: nil))
        }
    }

    func goToBackForwardListItem(_ item: LegacyBackForwardListItem) {
        if let index = backForwardList.backList.index(of: item) {
            let backCount = backForwardList.backList.count - index
            for _ in 0..<backCount {
                goBack()
            }
        } else if let index = backForwardList.forwardList.index(of: item) {
            for _ in 0..<(index + 1) {
                goForward()
            }
        }
    }

    override func goBack() {
        clearLoadCompletedHtmlProperty()

        // stop scrolling so the web view will respond faster
        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        NotificationCenter.default.post(name: Notification.Name(rawValue: kNotificationPageUnload), object: self)
        super.goBack()
    }

    override func goForward() {
        clearLoadCompletedHtmlProperty()

        scrollView.setContentOffset(scrollView.contentOffset, animated: false)
        NotificationCenter.default.post(name: Notification.Name(rawValue: kNotificationPageUnload), object: self)
        super.goForward()
    }

    class func isTopFrameRequest(_ request:URLRequest) -> Bool {
        guard let url = request.url, let mainDoc = request.mainDocumentURL else { return false }
        return url.host == mainDoc.host && url.path == mainDoc.path
    }

    // Long press context menu text selection overriding
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        return super.canPerformAction(action, withSender: sender)
    }

    func injectCSS(_ css: String) {
        var js = "var script = document.createElement('style');"
        js += "script.type = 'text/css';"
        js += "script.innerHTML = '\(css)';"
        js += "document.head.appendChild(script);"
        LegacyUserContentController.injectJsIntoAllFrames(self, script: js)
    }

    enum ShieldStatUpdate {
        case reset
        case broadcastOnly
        case httpseIncrement
        case abIncrement
        case tpIncrement
        case jsSetValue
        case fpIncrement
    }

    var shieldStats = ShieldBlockedStats()

    // Some sites will re-try loads (us.yahoo.com). Trivially block this case by keeping small list of recently blocked
    struct RecentlyBlocked {
        var urls = [String](repeating: "", count: 5)
        var insertAtIndex = 0
    }
    var recentlyBlocked = RecentlyBlocked()

    func shieldStatUpdate(_ stat: ShieldStatUpdate, increment: Int = 1, affectedUrl: String = "") {
        if !affectedUrl.isEmpty {
            if recentlyBlocked.urls.contains(affectedUrl) {
                return
            }
            recentlyBlocked.urls[recentlyBlocked.insertAtIndex] = affectedUrl
            recentlyBlocked.insertAtIndex = (recentlyBlocked.insertAtIndex + 1) % recentlyBlocked.urls.count
        }

        switch stat {
        case .broadcastOnly:
            break
        case .reset:
            shieldStats = ShieldBlockedStats()
            recentlyBlocked = RecentlyBlocked()
        case .httpseIncrement:
            shieldStats.httpse += increment
            BraveGlobalShieldStats.singleton.httpse += increment
        case .abIncrement:
            shieldStats.abAndTp += increment
            BraveGlobalShieldStats.singleton.adblock += increment
        case .tpIncrement:
            shieldStats.abAndTp += increment
            BraveGlobalShieldStats.singleton.trackingProtection += increment
        case .jsSetValue:
            shieldStats.js = increment
        case .fpIncrement:
            shieldStats.fp += increment
            BraveGlobalShieldStats.singleton.fpProtection += increment
        }

        postAsyncToMain(0.2) { [weak self] in
            if let me = self, BraveApp.getCurrentWebView() === me {
                getApp().braveTopViewController.rightSidePanel.setShieldBlockedStats(me.shieldStats)
            }
        }
    }
}

extension BraveWebView: UIWebViewDelegate {

    class LegacyNavigationAction : WKNavigationAction {
        var writableRequest: URLRequest
        var writableType: WKNavigationType

        init(type: WKNavigationType, request: URLRequest) {
            writableType = type
            writableRequest = request
            super.init()
        }

        override var request: URLRequest { get { return writableRequest} }
        override var navigationType: WKNavigationType { get { return writableType } }
        override var sourceFrame: WKFrameInfo {
            get { return WKFrameInfo() }
        }
    }

    func webView(_ webView: UIWebView,shouldStartLoadWith request: URLRequest, navigationType: UIWebViewNavigationType ) -> Bool {
        guard let url = request.url else { return false }

        webView.backgroundColor = UIColor.white

        if let contextMenu = window?.rootViewController?.presentedViewController, contextMenu.view.tag == BraveWebViewConstants.kContextMenuBlockNavigation {
            // When showing a context menu, the webview will often still navigate (ex. news.google.com)
            // We need to block navigation using this tag.
            return false
        }

        if let tab = getApp().tabManager.tabForWebView(self) {
            let state = braveShieldState
            var fpShieldOn = !state.isAllOff() && (state.isOnFingerprintProtection() ?? BraveApp.getPrefs()?.boolForKey(kPrefKeyFingerprintProtection) ?? false)

            // Override for automated testing
            if URLProtocol.testShieldState?.isOnFingerprintProtection() ?? false {
                fpShieldOn = true
            }

            if fpShieldOn {
                if tab.getHelper(FingerprintingProtection.self) == nil {
                    let fp = FingerprintingProtection(browser: tab)
                    tab.addHelper(fp)
                }
            } else {
                tab.removeHelper(FingerprintingProtection.self)
            }
        }

        if url.absoluteString == blankTargetUrl {
            blankTargetUrl = nil
            print(url)
            getApp().browserViewController.openURLInNewTab(url)
            return false
        }
        blankTargetUrl = nil

        if url.scheme == "mailto" {
            UIApplication.shared.openURL(url)
            return false
        }

        if AboutUtils.isAboutHomeURL(url) {
            setUrl(url)
            progress?.setProgress(1.0)
            return true
        }

        if url.absoluteString.contains(specialStopLoadUrl) ?? false {
            progress?.completeProgress()
            return false
        }

        if loadingUnvalidatedHTTPSPage {
            certificateInvalidConnection = NSURLConnection(request: request, delegate: self)
            certificateInvalidConnection?.start()
            return false
        }

        if let progressCheck = progress?.shouldStartLoadWithRequest(request, navigationType: navigationType), !progressCheck {
            return false
        }

        if let nd = navigationDelegate {
            var shouldLoad = true
            nd.webViewDecidePolicyForNavigationAction(self, url: url, shouldLoad: &shouldLoad)
            if !shouldLoad {
                return false
            }
        }

        if url.scheme?.startsWith("itms") ?? false || url.host == "itunes.apple.com" {
            progress?.completeProgress()
            return false
        }

        let locationChanged = BraveWebView.isTopFrameRequest(request) && url.absoluteString != URL?.absoluteString
        if locationChanged {
            blankTargetLinkDetectionOn = true
            // TODO Maybe separate page unload from link clicked.
            NotificationCenter.default.post(name: Notification.Name(rawValue: kNotificationPageUnload), object: self)
            setUrl(url)
            //print("Page changed by shouldStartLoad: \(URL?.absoluteString ?? "")")

            if let url = request.url {
                internalSetBraveShieldStateForDomain(url.normalizedHost!)
            }

            shieldStatUpdate(.reset)
        }

        broadcastToPageStateDelegates()

        return true
    }


    func webViewDidStartLoad(_ webView: UIWebView) {
        backForwardList.update()
        
        if let nd = navigationDelegate {
            // this triggers the network activity spinner
            globalContainerWebView.legacyWebView = self
            nd.webViewDidStartProvisionalNavigation(self, url: URL)
        }
        progress?.webViewDidStartLoad()

        delegatesForPageState.forEach { $0.value?.webView(self, isLoading: true) }

        #if !TEST
            HideEmptyImages.runJsInWebView(self)
        #endif

        configuration.userContentController.injectFingerprintProtection()
    }

    func webViewDidFinishLoad(_ webView: UIWebView) {
        assert(Thread.isMainThread)
#if DEBUGJS
        let context = valueForKeyPath("documentView.webView.mainFrame.javaScriptContext") as! JSContext
        let logFunction : @convention(block) (String) -> Void = { (msg: String) in
            NSLog("Console: %@", msg)
        }
        context.objectForKeyedSubscript("console").setObject(unsafeBitCast(logFunction, AnyObject.self), forKeyedSubscript: "log")
#endif
        // browserleaks canvas requires injection at this point
        configuration.userContentController.injectFingerprintProtection()

        let readyState = stringByEvaluatingJavaScript(from: "document.readyState.toLowerCase()")
        updateTitleFromHtml()

        if let isSafeBrowsingBlock = stringByEvaluatingJavaScript(from: "document['BraveSafeBrowsingPageResult']") {
            safeBrowsingBlockTriggered = (isSafeBrowsingBlock as NSString).boolValue
        }

        progress?.webViewDidFinishLoad(readyState)

        backForwardList.update()
        broadcastToPageStateDelegates()
    }

    func webView(_ webView: UIWebView, didFailLoadWithError error: Error) {
        //print("didFailLoadWithError: \(error)")
        guard let errorUrl = error.userInfo[NSURLErrorFailingURLErrorKey] as? Foundation.URL else { return }
        if errorUrl.isSpecialInternalUrl() {
            return
        }

        if (error.domain == NSURLErrorDomain) &&
               (error.code == NSURLErrorServerCertificateHasBadDate      ||
                error.code == NSURLErrorServerCertificateUntrusted         ||
                error.code == NSURLErrorServerCertificateHasUnknownRoot    ||
                error.code == NSURLErrorServerCertificateNotYetValid)
        {
            if errorUrl.absoluteString?.regexReplacePattern("^.+://", with: "") != URL?.absoluteString?.regexReplacePattern("^.+://", with: "") {
                print("only show cert error for top-level page")
                return
            }

            let alertUrl = errorUrl.absoluteString ?? "this site"
            let alert = UIAlertController(title: "Certificate Error", message: "The identity of \(alertUrl) can't be verified", preferredStyle: UIAlertControllerStyle.alert)
            alert.addAction(UIAlertAction(title: "Cancel", style: UIAlertActionStyle.default) {
                handler in
                self.stopLoading()
                webView.loadRequest(URLRequest(url: Foundation.URL(string: self.specialStopLoadUrl)!))

                // The current displayed url is wrong, so easiest hack is:
                if (self.canGoBack) { // I don't think the !canGoBack case needs handling
                    self.goBack()
                    self.goForward()
                }
                })
            alert.addAction(UIAlertAction(title: "Continue", style: UIAlertActionStyle.default) {
                handler in
                self.loadingUnvalidatedHTTPSPage = true;
                self.loadRequest(URLRequest(url: errorUrl))
                })

            window?.rootViewController?.present(alert, animated: true, completion: nil)
            return
        }

        NotificationCenter.default
            .post(name: Notification.Name(rawValue: BraveWebViewConstants.kNotificationWebViewLoadCompleteOrFailed), object: self)

        // The error may not be the main document that failed to load. Check if the failing URL matches the URL being loaded

        if let errorUrl = error.userInfo[NSURLErrorFailingURLErrorKey] as? Foundation.URL {
            var handled = false
            if error.code == -1009 /*kCFURLErrorNotConnectedToInternet*/ {
                let cache = URLCache.shared.cachedResponse(for: URLRequest(url: errorUrl))
                if let html = cache?.data.utf8EncodedString, html.characters.count > 100 {
                    loadHTMLString(html, baseURL: errorUrl)
                    handled = true
                }
            }

            let kPluginIsHandlingLoad = 204 // mp3 for instance, returns an error to webview that a plugin is taking over, which is correct
            if !handled && URL?.absoluteString == errorUrl.absoluteString && error.code != kPluginIsHandlingLoad {
                if let nd = navigationDelegate {
                    globalContainerWebView.legacyWebView = self
                    nd.webViewDidFailNavigation(self, withError: error as NSError ?? NSError.init(domain: "", code: 0, userInfo: nil))
                }
            }
        }

        progress?.didFailLoadWithError()
        broadcastToPageStateDelegates()
    }
}

extension BraveWebView : NSURLConnectionDelegate, NSURLConnectionDataDelegate {
    func connection(_ connection: NSURLConnection, willSendRequestFor challenge: URLAuthenticationChallenge) {
        guard let trust = challenge.protectionSpace.serverTrust else { return }
        let cred = URLCredential(trust: trust)
        challenge.sender?.use(cred, for: challenge)
        challenge.sender?.continueWithoutCredential(for: challenge)
        loadingUnvalidatedHTTPSPage = false
    }

    func connection(_ connection: NSURLConnection, didReceive response: URLResponse) {
        guard let url = URL else { return }
        loadingUnvalidatedHTTPSPage = false
        loadRequest(URLRequest(url: url))
        certificateInvalidConnection?.cancel()
    }    
}
