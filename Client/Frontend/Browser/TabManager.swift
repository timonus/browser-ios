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
        func insert(_ tab: Browser, at: Int) {
            var at = at
            at = max(0, at)
            at = min(tabs.count, at)
            tabs.insert(tab, at: at)
        }
        
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
    
    var currentIndex: Int? {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        
        guard let selectedTab = self.selectedTab else {
            return nil
        }
        
        return tabs.internalTabList.index(of: selectedTab)
    }
    
    var currentDisplayedIndex: Int? {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        
        guard let selectedTab = self.selectedTab else {
            return nil
        }
        
        return tabs.displayedTabsForCurrentPrivateMode.index(of: selectedTab)
    }
    
    func move(tab: Browser, from: Int, to: Int) {
        self.tabs.move(tab, from: from, to: to)
        
        // Update tab order.
        debugPrint("updated tab index from \(from) to \(to)")
        
        saveTabOrder()
    }
    
    func saveTabOrder() {
        let context = DataController.shared.workerContext
        context.perform {
            for i in 0..<self.tabs.internalTabList.count {
                let tab = self.tabs.internalTabList[i]
                guard let managedObject = TabMO.getByID(tab.tabID, context: context) else { print("Error: Tab missing managed object"); continue }
                managedObject.order = Int16(i)
            }
            DataController.saveContext(context: context)
        }
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
    
    func indexOfWebView(_ webView: UIWebView) -> UInt? {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        
        var count = UInt(0)
        for tab in tabs.internalTabList {
            if tab.webView === webView {
                return count
            }
            count = count + 1
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
            
            // Data was never set on internal tab restore, so now it happens when tab is selected.
            restoreTab(t)
            
            for delegate in delegates where t.webView != nil {
                delegate.value?.tabManager(self, didCreateWebView: t, url: nil, at: nil)
            }
        }

        // This is pitiful. Should just be storing the active tab Id rather than using this `isSelected` concept
        TabMO.getAll().forEach { $0.isSelected = $0.syncUUID == tab?.tabID }
        // `getAll` currently uses main thread
        DataController.saveContext(context: DataController.shared.mainThreadContext)
        
        for delegate in delegates where tab != nil {
            delegate.value?.tabManager(self, didSelectedTabChange: tab)
        }

        limitInMemoryTabs()
    }
    
    func selectPreviousTab() {
        let tab = tabs.displayedTabsForCurrentPrivateMode[currentDisplayedIndex ?? 0]
        guard let currentIndex = tabs.displayedTabsForCurrentPrivateMode.index(where: {$0 === tab}) else { return }
        if currentIndex > 0 {
            selectTab(tabs.displayedTabsForCurrentPrivateMode[currentIndex-1])
        }
    }
    
    func selectNextTab() {
        let tab = tabs.displayedTabsForCurrentPrivateMode[currentDisplayedIndex ?? 0]
        guard let currentIndex = tabs.displayedTabsForCurrentPrivateMode.index(where: {$0 === tab}) else { return }
        if currentIndex < tabs.displayedTabsForCurrentPrivateMode.count-1 {
            selectTab(tabs.displayedTabsForCurrentPrivateMode[currentIndex+1])
        }
    }

    func expireSnackbars() {
        debugNoteIfNotMainThread()

        for tab in tabs.internalTabList {
            tab.expireSnackbars()
        }
    }

    func addTabForDesktopSite() -> Browser {
        let tab = Browser(configuration: self.configuration, isPrivate: PrivateBrowsing.singleton.isOn)
        tab.tabID = TabMO.freshTab().syncUUID
        configureTab(tab, request: nil, zombie: false, useDesktopUserAgent: true)
        selectTab(tab)
        return tab
    }

    @discardableResult func addTabAndSelect(_ request: URLRequest! = nil, configuration: WKWebViewConfiguration! = nil) -> Browser? {
        guard let tab = addTab(request, configuration: configuration) else { return nil }
        selectTab(tab)
        return tab
    }
    
    @discardableResult func addAdjacentTabAndSelect(_ request: URLRequest! = nil, configuration: WKWebViewConfiguration! = nil) -> Browser? {
        let nextIndex = getApp().tabManager.currentIndex?.advanced(by: 1)
        guard let tab = addTab(request, configuration: configuration, id: nil, index: nextIndex) else { return nil }
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
            tab = self.addTab(URLRequest(url: url), configuration: nil, zombie: zombie, id: TabMO.freshTab().syncUUID)
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
        isRestoring = true
        
        // Do not want to load any tabs if PM is enabled
        assert(!PrivateBrowsing.singleton.isOn, "Tab restoration should never happen in PM")
        
        // These tabs MUST be sorted by `order` currently, as they are created in a linear manor 0..<max
        // Future optimizations to launching can be made by predicting what tabs will most likely be used
        //  (e.g. the last active tab), and loading those first, and inserting restored tabs in a non-linear
        //  fashion. This currently has exponential launch delay consequences though. Most of the time impact
        //  has been related to layout constraints on the tab tray (re-arranging tabs as they are being created)
        //  Since `move` recalculates each pre-existing tab's position. Hence the forced order here.
        let savedTabs = TabMO.getAll()
        for savedTab in savedTabs {
            if savedTab.url == nil {
                DataController.remove(object: savedTab)
                continue
            }
            
            guard let tab = addTab(nil, configuration: nil, zombie: true, id: savedTab.syncUUID, createWebview: false) else { return }
            
            if savedTab.isSelected {
                tabToSelect = tab
            }
            tab.lastTitle = savedTab.title
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
            restoreTab(tab)
            
            postAsyncToMain {
                self.selectTab(tab)
                self.isRestoring = false
            }
        }
        else {
            isRestoring = false
        }
    }
    
    func restoreTab(_ tab: Browser) {
        // Tab was created with no active webview or session data. Restore tab data from CD and configure.
        guard let savedTab = TabMO.getByID(tab.tabID) else { return }
        
        if let history = savedTab.urlHistorySnapshot as? [String], let tabUUID = savedTab.syncUUID, let url = savedTab.url {
            let data = SavedTab(id: tabUUID, title: savedTab.title ?? "", url: url, isSelected: savedTab.isSelected, order: savedTab.order, screenshot: nil, history: history, historyIndex: savedTab.urlHistoryCurrentIndex)
            if let webView = tab.webView {
                tab.restore(webView, restorationData: data)
            }
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

    @discardableResult func addTab(_ request: URLRequest? = nil, configuration: WKWebViewConfiguration? = nil, zombie: Bool = false, id: String? = nil, index: Int? = nil, createWebview: Bool = true) -> Browser? {
        debugNoteIfNotMainThread()
        if (!Thread.isMainThread) { // No logical reason this should be off-main, don't add a tab.
            return nil
        }
        objc_sync_enter(self); defer { objc_sync_exit(self) }

        let isPrivate = PrivateBrowsing.singleton.isOn
        let tab = Browser(configuration: self.configuration, isPrivate: isPrivate)
        tab.tabID = id ?? TabMO.freshTab().syncUUID
        
        configureTab(tab, request: request, zombie: zombie, index: index, createWebview: createWebview)
        return tab
    }

    func configureTab(_ tab: Browser, request: URLRequest?, zombie: Bool = false, useDesktopUserAgent: Bool = false, index: Int? = nil, createWebview: Bool = true) {
        debugNoteIfNotMainThread()
        if (!Thread.isMainThread) { // No logical reason this should be off-main, don't add a tab.
            return
        }
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        
        limitInMemoryTabs()

        var lastIndex = index
        if let index = index {
            tabs.insert(tab, at: index)
        } else {
            tabs.append(tab)
            lastIndex = tabs.internalTabList.count - 1
        }

        for delegate in delegates {
            delegate.value?.tabManager(self, didAddTab: tab)
        }

        
        // On restore we are casually creating webviews only on active tab. 
        // All others will be created when tab is selected.
        // Since tab bar manager awaits protocol method to create UI we trick into creating.
        if !createWebview {
            let showingPolicy = TabsBarShowPolicy(rawValue: Int(BraveApp.getPrefs()?.intForKey(kPrefKeyTabsBarShowPolicy) ?? Int32(kPrefKeyTabsBarOnDefaultValue.rawValue))) ?? kPrefKeyTabsBarOnDefaultValue
            if showingPolicy != TabsBarShowPolicy.never {
                for delegate in delegates {
                    delegate.value?.tabManager(self, didCreateWebView: tab, url: request?.url, at: lastIndex)
                }
            }
            return
        }
        
        tab.createWebview(useDesktopUserAgent)

        for delegate in delegates {
            delegate.value?.tabManager(self, didCreateWebView: tab, url: request?.url, at: lastIndex)
        }

        tab.navigationDelegate = navDelegate
        _ = tab.loadRequest(request ?? defaultNewTabRequest)
 
        // Ignore on restore.
        if !zombie && !PrivateBrowsing.singleton.isOn {
            TabMO.preserveTab(tab: tab)
            saveTabOrder()
        }
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

        if let tab = TabMO.getByID(tab.tabID) {
            DataController.remove(object: tab)
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
            let tab = addTab(id: TabMO.freshTab().syncUUID)
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

    func removeAll(createTabIfNoneLeft: Bool = false) {
        objc_sync_enter(self); defer { objc_sync_exit(self) }
        let tabs = self.tabs

        for tab in tabs.internalTabList {
            self.removeTab(tab, flushToDisk: false, notify: true, createTabIfNoneLeft: createTabIfNoneLeft)
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
