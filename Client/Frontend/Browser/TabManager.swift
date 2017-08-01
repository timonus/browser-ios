/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit
import Storage
import Shared
import CoreData

private let log = Logger.browserLogger

protocol TabManagerDelegate: class {
    func tabManager(_ tabManager: TabManager, didSelectedTabChange selected: Browser?)
    func tabManager(_ tabManager: TabManager, didCreateWebView tab: Browser, url: URL?, at: Int?)
    func tabManager(_ tabManager: TabManager, didAddTab tab: Browser)
    func tabManager(_ tabManager: TabManager, didRemoveTab tab: Browser)
    func tabManagerDidRestoreTabs(_ tabManager: TabManager)
    func tabManagerDidAddTabs(_ tabManager: TabManager)
    func tabManagerDidEnterPrivateBrowsingMode(_ tabManager: TabManager) // has default impl
    func tabManagerDidExitPrivateBrowsingMode(_ tabManager: TabManager) // has default impl
}

extension TabManagerDelegate { // add default implementation for 'optional' funcs
    func tabManagerDidEnterPrivateBrowsingMode(_ tabManager: TabManager) {}
    func tabManagerDidExitPrivateBrowsingMode(_ tabManager: TabManager) {}
}

protocol TabManagerStateDelegate: class {
    func tabManagerWillStoreTabs(_ tabs: [Browser])
}

// We can't use a WeakList here because this is a protocol.
class WeakTabManagerDelegate {
    weak var value : TabManagerDelegate?

    init (value: TabManagerDelegate) {
        self.value = value
    }
}

// TabManager must extend NSObjectProtocol in order to implement WKNavigationDelegate
class TabManager : NSObject {
    var delegates = [WeakTabManagerDelegate]()
    weak var stateDelegate: TabManagerStateDelegate?

    func addDelegate(_ delegate: TabManagerDelegate) {
        debugNoteIfNotMainThread()
        delegates.append(WeakTabManagerDelegate(value: delegate))
    }

    func removeDelegate(_ delegate: TabManagerDelegate) {
        debugNoteIfNotMainThread()
        for i in 0 ..< delegates.count {
            let del = delegates[i]
            if delegate === del.value {
                delegates.remove(at: i)
                return
            }
        }
    }

    class TabsList {
        fileprivate(set) var tabs = [Browser]()
        func append(_ tab: Browser) { tabs.append(tab) }
        func insert(_ tab: Browser, at: Int) { tabs.insert(tab, at: at) }
        func move(_ tab: Browser, from: Int, to: Int) { tabs.insert(tabs.remove(at: from), at: to) }
        var internalTabList : [Browser] { return tabs }

        var nonprivateTabs: [Browser] {
            objc_sync_enter(self); defer { objc_sync_exit(self) }
            debugNoteIfNotMainThread()
            return tabs.filter { !$0.isPrivate }
        }

        var privateTabs: [Browser] {
            objc_sync_enter(self); defer { objc_sync_exit(self) }
            debugNoteIfNotMainThread()
            return tabs.filter { $0.isPrivate }
        }

        // What the users sees displayed based on current private browsing mode
        var displayedTabsForCurrentPrivateMode: [Browser] {
            return PrivateBrowsing.singleton.isOn ? privateTabs : nonprivateTabs
        }

        func removeTab(_ tab: Browser) {
            if let i = internalTabList.index(of: tab) {
                tabs.remove(at: i)
            }
        }
    }

    fileprivate(set) var tabs = TabsList()

    fileprivate let defaultNewTabRequest: URLRequest
    fileprivate let navDelegate: TabManagerNavDelegate
    fileprivate(set) var isRestoring = false

    // A WKWebViewConfiguration used for normal tabs
    lazy fileprivate var configuration: WKWebViewConfiguration = {
        let configuration = WKWebViewConfiguration()
        configuration.processPool = WKProcessPool()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = !(self.prefs.boolForKey("blockPopups") ?? true)
        return configuration
    }()

    fileprivate let imageStore: DiskImageStore?

    fileprivate let prefs: Prefs

    init(defaultNewTabRequest: URLRequest, prefs: Prefs, imageStore: DiskImageStore?) {
        debugNoteIfNotMainThread()

        self.prefs = prefs
        self.defaultNewTabRequest = defaultNewTabRequest
        self.navDelegate = TabManagerNavDelegate()
        self.imageStore = imageStore
        super.init()

        addNavigationDelegate(self)

        NotificationCenter.default.addObserver(self, selector: #selector(TabManager.prefsDidChange), name: UserDefaults.didChangeNotification, object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func addNavigationDelegate(_ delegate: WKCompatNavigationDelegate) {
        debugNoteIfNotMainThread()

        self.navDelegate.insert(delegate)
    }

    var tabCount: Int {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        return tabs.internalTabList.count
    }

    fileprivate weak var _selectedTab: Browser?
    var selectedTab: Browser? {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        return _selectedTab
    }
    
    var currentIndex: Int {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        
        var order = 0
        for t in self.tabs.internalTabList {
            if t === self.selectedTab { break }
            order += 1
        }
        
        return order
    }
    
    func move(tab: Browser, from: Int, to: Int) {
        self.tabs.move(tab, from: from, to: to)
        
        // Update tab order.
        debugPrint("updated tab index from \(from) to \(to)")
        
        let context = DataController.shared.mainThreadContext
        for i in 0..<tabs.internalTabList.count {
            let tab = tabs.internalTabList[i]
            guard let tabID = tab.tabID else { print("Error: Tab missing ID"); continue }
            let tabMO = TabMO.getByID(tabID, context: context)
            tabMO?.order = Int16(i)
        }
        
        DataController.saveContext(context: context)
    }

    func tabForWebView(_ webView: UIWebView) -> Browser? {
        objc_sync_enter(self); defer { objc_sync_exit(self) }

        for tab in tabs.internalTabList {
            if tab.webView === webView {
                return tab
            }
        }

        return nil
    }

    func getTabFor(_ url: URL) -> Browser? {
        objc_sync_enter(self); defer { objc_sync_exit(self) }

        for tab in tabs.internalTabList {
            if (tab.webView?.URL == url) {
                return tab
            }
        }
        return nil
    }

    func selectTab(_ tab: Browser?) {
        debugNoteIfNotMainThread()
        if (!Thread.isMainThread) { // No logical reason this should be off-main, don't select.
            return
        }
        objc_sync_enter(self); defer { objc_sync_exit(self) }

        if let tab = tab, selectedTab === tab && tab.webView != nil {
            return
        }

        _selectedTab = tab

        if let t = self.selectedTab, t.webView == nil {
            t.createWebview()
            for delegate in delegates where t.webView != nil {
                delegate.value?.tabManager(self, didCreateWebView: t, url: nil, at: nil)
            }
        }

        // This is pitiful. Should just be storing the active tab Id rather than using this `isSelected` concept
        TabMO.getAll().forEach { $0.isSelected = $0.syncUUID == tab?.tabID }
        
        for delegate in delegates where tab != nil {
            delegate.value?.tabManager(self, didSelectedTabChange: tab)
        }

        limitInMemoryTabs()
    }

    func expireSnackbars() {
        debugNoteIfNotMainThread()

        for tab in tabs.internalTabList {
            tab.expireSnackbars()
        }
    }

    func addTabForDesktopSite() -> Browser {
        let tab = Browser(configuration: self.configuration, isPrivate: PrivateBrowsing.singleton.isOn)
        tab.tabID = TabMO.freshTab()
        configureTab(tab, request: nil, zombie: false, useDesktopUserAgent: true)
        selectTab(tab)
        return tab
    }

    func addTabAndSelect(_ request: URLRequest! = nil, configuration: WKWebViewConfiguration! = nil) -> Browser? {
        guard let tab = addTab(request, configuration: configuration, id: TabMO.freshTab()) else { return nil }
        selectTab(tab)
        return tab
    }

    func addTabsForURLs(_ urls: [URL], zombie: Bool) {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        debugNoteIfNotMainThread()

        if urls.isEmpty {
            return
        }

        var tab: Browser!
        for url in urls {
            tab = self.addTab(URLRequest(url: url), configuration: nil, zombie: zombie, id: TabMO.freshTab())
        }

        // Select the most recent.
        self.selectTab(tab)

        // Notify that we bulk-loaded so we can adjust counts.
        for delegate in delegates {
            delegate.value?.tabManagerDidAddTabs(self)
        }
    }
    
    // Basically a dispatch once, prevents mulitple calls
    lazy var restoreTabs: () = {
        postAsyncToMain {
            self.restoreTabsInternal()
        }
    }()
    
    fileprivate func restoreTabsInternal() {
        var tabToSelect: Browser?
        let savedTabs = TabMO.getAll()
        for savedTab in savedTabs {
            if savedTab.url == nil {
                if let id = savedTab.syncUUID {
                    TabMO.removeTab(id)
                }
                continue
            }
            
            guard let tab = addTab(nil, configuration: nil, zombie: true, id: savedTab.syncUUID) else { return }
            
            debugPrint(savedTab)
            
            tab.setScreenshot(savedTab.screenshotImage)
            if savedTab.isSelected {
                tabToSelect = tab
            }
            tab.lastTitle = savedTab.title
            if let w = tab.webView, let history = savedTab.urlHistorySnapshot as? [String], let tabID = savedTab.syncUUID, let url = savedTab.url {
                let data = SavedTab(id: tabID, title: savedTab.title ?? "", url: url, isSelected: savedTab.isSelected, order: savedTab.order, screenshot: nil, history: history, historyIndex: savedTab.urlHistoryCurrentIndex)
                tab.restore(w, restorationData: data)
            }
            else {
                debugPrint("failed to load tab \(savedTab.url)")
            }
        }
        if tabToSelect == nil {
            tabToSelect = tabs.displayedTabsForCurrentPrivateMode.first
        }
        
        // Only tell our delegates that we restored tabs if we actually restored a tab(s)
        // Base this off of the actual, physical tabs, not what was stored in CD, as we could have edited removed broken CD records
        if tabCount > 0 {
            delegates.forEach { $0.value?.tabManagerDidRestoreTabs(self) }
        } else {
            tabToSelect = addTab()
        }
        
        if let tab = tabToSelect {
            selectTab(tab)
        }
    }

    fileprivate func limitInMemoryTabs() {
        let maxInMemTabs = BraveUX.MaxTabsInMemory
        if tabs.internalTabList.count < maxInMemTabs {
            return
        }

        var webviews = 0
        for browser in tabs.internalTabList {
            if browser.webView != nil {
                webviews += 1
            }
        }
        if webviews < maxInMemTabs {
            return
        }

        print("webviews \(webviews)")

        var oldestTime: Timestamp = Date.now()
        var oldestBrowser: Browser? = nil
        for browser in tabs.internalTabList {
            if browser.webView == nil {
                continue
            }
            if let t = browser.lastExecutedTime, t < oldestTime {
                oldestTime = t
                oldestBrowser = browser
            }
        }
        if let browser = oldestBrowser {
            if selectedTab != browser {
                browser.deleteWebView(false)
            } else {
                print("limitInMemoryTabs: tab to delete is selected!")
            }
        }
    }

    func addTab(_ request: URLRequest? = nil, configuration: WKWebViewConfiguration? = nil, zombie: Bool = false, id: String? = nil, index: Int = -1) -> Browser? {
        debugNoteIfNotMainThread()
        if (!Thread.isMainThread) { // No logical reason this should be off-main, don't add a tab.
            return nil
        }
        objc_sync_enter(self); defer { objc_sync_exit(self) }

        let isPrivate = PrivateBrowsing.singleton.isOn
        let tab = Browser(configuration: self.configuration, isPrivate: isPrivate)
        if id == nil {
            tab.tabID = TabMO.freshTab()
        }
        else {
            tab.tabID = id
        }
        configureTab(tab, request: request, zombie: zombie, index: index)
        return tab
    }

    func configureTab(_ tab: Browser, request: URLRequest?, zombie: Bool = false, useDesktopUserAgent: Bool = false, index: Int = -1) {
        debugNoteIfNotMainThread()
        if (!Thread.isMainThread) { // No logical reason this should be off-main, don't add a tab.
            return
        }
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        
        limitInMemoryTabs()

        var lastIndex = index
        if index == -1 {
            tabs.append(tab)
            lastIndex = tabs.internalTabList.count - 1
        }
        else {
            tabs.insert(tab, at: index)
        }

        for delegate in delegates {
            delegate.value?.tabManager(self, didAddTab: tab)
        }

        tab.createWebview(useDesktopUserAgent)

        for delegate in delegates {
            delegate.value?.tabManager(self, didCreateWebView: tab, url: request?.url, at: lastIndex)
        }

        tab.navigationDelegate = navDelegate
        _ = tab.loadRequest(request ?? defaultNewTabRequest)
        
        TabMO.preserveTab(tab: tab)
    }

    // This method is duplicated to hide the flushToDisk option from consumers.
    func removeTab(_ tab: Browser, createTabIfNoneLeft: Bool) {
        self.removeTab(tab, flushToDisk: true, notify: true, createTabIfNoneLeft: createTabIfNoneLeft)
        hideNetworkActivitySpinner()
    }

    /// - Parameter notify: if set to true, will call the delegate after the tab
    ///   is removed.
    fileprivate func removeTab(_ tab: Browser, flushToDisk: Bool, notify: Bool, createTabIfNoneLeft: Bool) {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        debugNoteIfNotMainThread()
        if !Thread.isMainThread {
            return
        }

        if let selected = selectedTab, selectedTab === tab {
            if let idx = tabs.displayedTabsForCurrentPrivateMode.index(of: selected) {
                if idx - 1 >= 0 {
                    selectTab(tabs.displayedTabsForCurrentPrivateMode[idx - 1])
                } else if tabs.displayedTabsForCurrentPrivateMode.last !== tab {
                    selectTab(tabs.displayedTabsForCurrentPrivateMode.last)
                }
            }
        }
        tabs.removeTab(tab)

        if let tabID = tab.tabID {
            TabMO.removeTab(tabID)
        }
        
        // There's still some time between this and the webView being destroyed.
        // We don't want to pick up any stray events.
        tab.webView?.navigationDelegate = nil
        if notify {
            for delegate in delegates {
                delegate.value?.tabManager(self, didRemoveTab: tab)
            }
        }

        // Make sure we never reach 0 normal tabs
        if tabs.displayedTabsForCurrentPrivateMode.count == 0 && createTabIfNoneLeft {
            let tab = addTab(id: TabMO.freshTab())
            selectTab(tab)
        }
        
        if createTabIfNoneLeft && selectedTab == nil {
            selectTab(tabs.displayedTabsForCurrentPrivateMode.first)
        }
    }

    /// Removes all private tabs from the manager.
    /// - Parameter notify: if set to true, the delegate is called when a tab is
    ///   removed.
    func removeAllPrivateTabsAndNotify(_ notify: Bool) {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        for tab in tabs.internalTabList {
            tab.deleteWebView(false)
        }
        _selectedTab = nil
        tabs.privateTabs.forEach{
            removeTab($0, flushToDisk: true, notify: notify, createTabIfNoneLeft: false)
        }
    }

    func removeAll() {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        let tabs = self.tabs

        for tab in tabs.internalTabList {
            self.removeTab(tab, flushToDisk: false, notify: true, createTabIfNoneLeft: false)
        }
    }

    func getTabForURL(_ url: URL) -> Browser? {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        debugNoteIfNotMainThread()

        return tabs.internalTabList.filter { $0.webView?.URL == url } .first
    }

    func prefsDidChange() {
#if !BRAVE
        DispatchQueue.main.async {
            let allowPopups = !(self.prefs.boolForKey("blockPopups") ?? true)
            // Each tab may have its own configuration, so we should tell each of them in turn.
            for tab in self.tabs {
                tab.webView?.configuration.preferences.javaScriptCanOpenWindowsAutomatically = allowPopups
            }
            // The default tab configurations also need to change.
            self.configuration.preferences.javaScriptCanOpenWindowsAutomatically = allowPopups
            self.privateConfiguration.preferences.javaScriptCanOpenWindowsAutomatically = allowPopups
        }
#endif
    }

    func resetProcessPool() {
        debugNoteIfNotMainThread()

        configuration.processPool = WKProcessPool()
    }
}

extension TabManager {

    // Only call from PB class
    func enterPrivateBrowsingMode(_: PrivateBrowsing) {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        tabs.internalTabList.forEach{ $0.deleteWebView(false) }
        delegates.forEach {
            $0.value?.tabManagerDidEnterPrivateBrowsingMode(self)
        }
    }

    func exitPrivateBrowsingMode(_: PrivateBrowsing) {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        delegates.forEach {
            $0.value?.tabManagerDidExitPrivateBrowsingMode(self)
        }

        if getApp().tabManager.tabs.internalTabList.count < 1 {
            _ = getApp().tabManager.addTab()
        }
        getApp().tabManager.selectTab(getApp().tabManager.tabs.displayedTabsForCurrentPrivateMode.first)
        getApp().browserViewController.urlBar.updateTabsBarShowing()
    }
}

extension TabManager : WKCompatNavigationDelegate {

    func webViewDecidePolicyForNavigationAction(_ webView: UIWebView, url: URL?, shouldLoad: inout Bool) {}

    func webViewDidStartProvisionalNavigation(_: UIWebView, url: URL?) {
        UIApplication.shared.isNetworkActivityIndicatorVisible = true

#if BRAVE
        var hider: ((Void) -> Void)!
        hider = {
            postAsyncToMain(1) {
                self.hideNetworkActivitySpinner()
                if UIApplication.shared.isNetworkActivityIndicatorVisible {
                    hider()
                }
            }
        }
        hider()
#endif
    }

    func webViewDidFinishNavigation(_ webView: UIWebView, url: URL?) {
        hideNetworkActivitySpinner()

        // only store changes if this is not an error page
        // as we current handle tab restore as error page redirects then this ensures that we don't
        // call storeChanges unnecessarily on startup
        if let tab = tabForWebView(webView), let url = tabForWebView(webView)?.url {
            if !ErrorPageHelper.isErrorPageURL(url) {
                postAsyncToMain(0.25) {
                    TabMO.preserveTab(tab: tab)
                }
            }
        }
    }

    func webViewDidFailNavigation(_: UIWebView, withError _: NSError) {
        hideNetworkActivitySpinner()
    }

    func hideNetworkActivitySpinner() {
        for tab in tabs.internalTabList {
            if let tabWebView = tab.webView {
                // If we find one tab loading, we don't hide the spinner
                if tabWebView.isLoading {
                    return
                }
            }
        }
        UIApplication.shared.isNetworkActivityIndicatorVisible = false
    }

    /// Called when the WKWebView's content process has gone away. If this happens for the currently selected tab
    /// then we immediately reload it.

//    func webViewWebContentProcessDidTerminate(webView: WKWebView) {
//        if let browser = selectedTab where browser.webView == webView {
//            webView.reload()
//        }
//    }
}

protocol WKCompatNavigationDelegate : class {
    func webViewDidFailNavigation(_ webView: UIWebView, withError error: NSError)
    func webViewDidFinishNavigation(_ webView: UIWebView, url: URL?)
    func webViewDidStartProvisionalNavigation(_ webView: UIWebView, url: URL?)
    func webViewDecidePolicyForNavigationAction(_ webView: UIWebView, url: URL?, shouldLoad: inout Bool)
}

// WKNavigationDelegates must implement NSObjectProtocol
class TabManagerNavDelegate : WKCompatNavigationDelegate {
    class Weak_WKCompatNavigationDelegate {     // We can't use a WeakList here because this is a protocol.
        weak var value : WKCompatNavigationDelegate?
        init (value: WKCompatNavigationDelegate) { self.value = value }
    }
    fileprivate var navDelegates = [Weak_WKCompatNavigationDelegate]()

    func insert(_ delegate: WKCompatNavigationDelegate) {
        navDelegates.append(Weak_WKCompatNavigationDelegate(value: delegate))
    }

//    func webView(webView: WKWebView, didCommitNavigation navigation: WKNavigation!) {
//        for delegate in delegates {
//            delegate.webView?(webView, didCommitNavigation: navigation)
//        }
//    }

    func webViewDidFailNavigation(_ webView: UIWebView, withError error: NSError) {
        for delegate in navDelegates {
            delegate.value?.webViewDidFailNavigation(webView, withError: error)
        }
    }

//    func webView(webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
//        withError error: NSError) {
//            for delegate in delegates {
//                delegate.webView?(webView, didFailProvisionalNavigation: navigation, withError: error)
//            }
//    }

    func webViewDidFinishNavigation(_ webView: UIWebView, url: URL?) {
        for delegate in navDelegates {
            delegate.value?.webViewDidFinishNavigation(webView, url: url)
        }
    }

//    func webView(webView: WKWebView, didReceiveAuthenticationChallenge challenge: NSURLAuthenticationChallenge,
//        completionHandler: (NSURLSessionAuthChallengeDisposition,
//        NSURLCredential?) -> Void) {
//            let authenticatingDelegates = delegates.filter {
//                $0.respondsToSelector(#selector(WKNavigationDelegate.webView(_:didReceiveAuthenticationChallenge:completionHandler:)))
//            }
//
//            guard let firstAuthenticatingDelegate = authenticatingDelegates.first else {
//                return completionHandler(NSURLSessionAuthChallengeDisposition.PerformDefaultHandling, nil)
//            }
//
//            firstAuthenticatingDelegate.webView?(webView, didReceiveAuthenticationChallenge: challenge) { (disposition, credential) in
//                completionHandler(disposition, credential)
//            }
//    }

//    func webView(webView: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
//        for delegate in delegates {
//            delegate.webView?(webView, didReceiveServerRedirectForProvisionalNavigation: navigation)
//        }
//    }

    func webViewDidStartProvisionalNavigation(_ webView: UIWebView, url: URL?) {
        for delegate in navDelegates {
            delegate.value?.webViewDidStartProvisionalNavigation(webView, url: url)
        }
    }

    func webViewDecidePolicyForNavigationAction(_ webView: UIWebView, url: URL?, shouldLoad: inout Bool) {
        for delegate in navDelegates {
            delegate.value?.webViewDecidePolicyForNavigationAction(webView, url: url, shouldLoad: &shouldLoad)
        }

    }

//    func webView(webView: WKWebView, decidePolicyForNavigationResponse navigationResponse: WKNavigationResponse,
//        decisionHandler: (WKNavigationResponsePolicy) -> Void) {
//            var res = WKNavigationResponsePolicy.Allow
//            for delegate in delegates {
//                delegate.webView?(webView, decidePolicyForNavigationResponse: navigationResponse, decisionHandler: { policy in
//                    if policy == .Cancel {
//                        res = policy
//                    }
//                })
//            }
//
//            decisionHandler(res)
//    }
}
