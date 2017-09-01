/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared
private let log = Logger.browserLogger

extension BrowserViewController: TabManagerDelegate {
    func tabManager(_ tabManager: TabManager, didSelectedTabChange selected: Browser?) {
        if (urlBar.inSearchMode) {
            urlBar.leaveSearchMode()
        }

        // Remove the old accessibilityLabel. Since this webview shouldn't be visible, it doesn't need it
        // and having multiple views with the same label confuses tests.

        if let prevWebView = webViewContainer.subviews.filter({ $0 as? UIWebView != nil }).first {
            if prevWebView == selected?.webView {
                assert(false)
                NSLog("Error: Selected webview should not be in view heirarchy already")
                return
            }

            removeOpenInView()
            prevWebView.endEditing(true)
            prevWebView.accessibilityLabel = nil
            prevWebView.accessibilityElementsHidden = true
            prevWebView.accessibilityIdentifier = nil
            // due to screwy handling within iOS, the scrollToTop handling does not work if there are
            // more than one scroll view in the view hierarchy
            // we therefore have to hide all the scrollViews that we are no actually interesting in interacting with
            // to ensure that scrollsToTop actually works
            ///wv.scrollView.hidden = true
            prevWebView.removeFromSuperview()
        }

        if let tab = selected, let webView = tab.webView {
            // if we have previously hidden this scrollview in order to make scrollsToTop work then
            // we should ensure that it is not hidden now that it is our foreground scrollView
            //            if webView.scrollView.hidden {
            //                webView.scrollView.hidden = false
            //            }

            updateURLBarDisplayURL(tab: tab)

            if tab.isPrivate {
                readerModeCache = MemoryReaderModeCache.sharedInstance
                applyTheme(Theme.PrivateMode)
            } else {
                readerModeCache = DiskReaderModeCache.sharedInstance
                applyTheme(Theme.NormalMode)
            }
            ReaderModeHandlers.readerModeCache = readerModeCache

            scrollController.browser = selected

            webView.accessibilityLabel = Strings.Web_content
            webView.accessibilityIdentifier = "contentView"
            webView.accessibilityElementsHidden = false

            #if BRAVE
                selectedTabChanged(tab)
            #endif
            addOpenInViewIfNeccessary(webView.URL)

            if let url = webView.URL {
                // Don't bother fetching bookmark state for about/sessionrestore and about/home.
                if AboutUtils.isAboutURL(url) {
                    // Indeed, because we don't show the toolbar at all, don't even blank the star.
                } else {
                    let isBookmarked = Bookmark.contains(url: url, context: DataController.shared.mainThreadContext)
                    self.urlBar.updateBookmarkStatus(isBookmarked)
                }
            } else {
                // The web view can go gray if it was zombified due to memory pressure.
                // When this happens, the URL is nil, so try restoring the page upon selection.
                weak var weakSelf = self
                tab.screenshot(callback: { (image) in
                    weakSelf?.webViewPreviewImage.image = image
                    //weakSelf?.webViewPreviewImage.alpha = 0.9
                    weakSelf?.webViewPreviewImage.isHidden = false
                })
                
                tab.reload()
            }
        }

        updateTabCountUsingTabManager(tabManager)

        removeAllBars()
        if let bars = selected?.bars {
            for bar in bars {
                showBar(bar, animated: true)
            }
        }

        updateFindInPageVisibility(false)

        navigationToolbar.updateReloadStatus(selected?.loading ?? false)
        navigationToolbar.updateBackStatus(selected?.canGoBack ?? false)
        navigationToolbar.updateForwardStatus(selected?.canGoForward ?? false)

        if let readerMode = selected?.getHelper(ReaderMode.self) {
            urlBar.updateReaderModeState(readerMode.state)
            if readerMode.state == .Active {
                showReaderModeBar(animated: false)
            } else {
                hideReaderModeBar(animated: false)
            }
        } else {
            urlBar.updateReaderModeState(ReaderModeState.Unavailable)
        }

        updateInContentHomePanel(selected?.url)
    }

    func tabManager(_ tabManager: TabManager, didCreateWebView tab: Browser, url: URL?, at: Int?) {}

    func tabManager(_ tabManager: TabManager, didAddTab tab: Browser) {
        // If we are restoring tabs then we update the count once at the end
        if !tabManager.isRestoring {
            updateTabCountUsingTabManager(tabManager)
        }
        tab.browserDelegate = self
    }

    func tabManager(_ tabManager: TabManager, didRemoveTab tab: Browser) {
        updateTabCountUsingTabManager(tabManager)
        // browserDelegate is a weak ref (and the tab's webView may not be destroyed yet)
        // so we don't expcitly unset it.
    }

    func tabManagerDidAddTabs(_ tabManager: TabManager) {
        updateTabCountUsingTabManager(tabManager)
    }

    func tabManagerDidRestoreTabs(_ tabManager: TabManager) {
        updateTabCountUsingTabManager(tabManager)
    }

    func updateTabCountUsingTabManager(_ tabManager: TabManager, animated: Bool = true) {
        let count = tabManager.tabs.displayedTabsForCurrentPrivateMode.count
        urlBar.updateTabCount(max(count, 1), animated: animated)
    }
}
