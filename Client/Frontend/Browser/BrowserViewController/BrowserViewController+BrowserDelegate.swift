/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared
private let log = Logger.browserLogger

private let KVOLoading = "loading"
private let KVOEstimatedProgress = "estimatedProgress"
private let KVOURL = "URL"
private let KVOCanGoBack = "canGoBack"
private let KVOCanGoForward = "canGoForward"
private let KVOContentSize = "contentSize"

protocol BrowserTabStateDelegate: class {
    func browserUrlChanged(_ browser: Browser)
    func browserProgressChanged(_ browser: Browser)
}

extension BrowserViewController: WebPageStateDelegate {
    func webView(_ webView: UIWebView, canGoBack: Bool) {
        guard let tab = tabManager.tabForWebView(webView) else { return }
        if tab === tabManager.selectedTab {
            navigationToolbar.updateBackStatus(canGoBack)
        }
    }
    
    func webView(_ webView: UIWebView, canGoForward: Bool) {
        guard let tab = tabManager.tabForWebView(webView) else { return }
        if tab === tabManager.selectedTab {
            navigationToolbar.updateForwardStatus(canGoForward)
        }
    }

    func webView(_ webView: UIWebView, urlChanged: String) {
        guard let tab = tabManager.tabForWebView(webView) else { return }

        if let selected = tabManager.selectedTab {
            if selected.webView?.URL == nil {
                log.debug("URL is nil!")
            }

            if selected === tab && !tab.restoring {
                updateUIForReaderHomeStateForTab(tab)
            }
        }
    }

    func webView(_ webView: UIWebView, progressChanged: Float) {
        guard let tab = tabManager.tabForWebView(webView) else { return }
        if tab === tabManager.selectedTab {
            urlBar.updateProgressBar(progressChanged)
        }
    }

    func webView(_ webView: UIWebView, isLoading: Bool) {
        guard let tab = tabManager.tabForWebView(webView) else { return }

        if tab === tabManager.selectedTab {
            toolbar?.updateReloadStatus(isLoading)
            urlBar.updateReloadStatus(isLoading)
        }

    }
}

extension BrowserViewController: BrowserDelegate {
    func browser(_ browser: Browser, didCreateWebView webView: BraveWebView) {
        if webView.removeBvcObserversOnDeinit != nil {
            return
        }

        webView.scrollView.addObserver(self.scrollController, forKeyPath: KVOContentSize, options: .new, context: nil)
        webView.removeBvcObserversOnDeinit = {
            [weak sc = self.scrollController] (wv) in
            wv.scrollView.removeObserver(sc!, forKeyPath: KVOContentSize)
        }

        webView.delegatesForPageState.append(BraveWebView.Weak_WebPageStateDelegate(value: self))

        #if !BRAVE
            webView.UIDelegate = self /// these are for javascript alert panels
        #endif

        let readerMode = ReaderMode(browser: browser)
        readerMode.delegate = self
        browser.addHelper(readerMode)

        let favicons = FaviconManager(browser: browser, profile: profile)
        browser.addHelper(favicons)

        let logins = LoginsHelper(browser: browser, profile: profile)
        browser.addHelper(logins)

        #if !BRAVE
            let contextMenuHelper = ContextMenuHelper(browser: browser)
            contextMenuHelper.delegate = self
            browser.addHelper(contextMenuHelper, name: ContextMenuHelper.name())
        #endif

        let errorHelper = ErrorPageHelper()
        browser.addHelper(errorHelper)

        let windowCloseHelper = WindowCloseHelper(browser: browser)
        windowCloseHelper.delegate = self
        browser.addHelper(windowCloseHelper)

        let sessionRestoreHelper = SessionRestoreHelper(browser: browser)
        sessionRestoreHelper.delegate = self
        browser.addHelper(sessionRestoreHelper)

        let findInPageHelper = FindInPageHelper(browser: browser)
        findInPageHelper.delegate = self
        browser.addHelper(findInPageHelper)

        let printHelper = PrintHelper(browser: browser)
        browser.addHelper(printHelper)

        let openURL = {(url: URL) -> Void in
            self.switchToTabForURLOrOpen(url)
        }
        // TODO: Add spotlightHelper and test cases
        //let spotlightHelper = SpotlightHelper(browser: browser, openURL: openURL)
        //browser.addHelper(spotlightHelper)

        #if BRAVE
            let pageUnload = BravePageUnloadHelper(browser: browser)
            browser.addHelper(pageUnload)
            
            if BraveApp.getPrefs()?.boolForKey(kPrefKeyFingerprintProtection) ?? false {
                let fp = FingerprintingProtection(browser: browser)
                browser.addHelper(fp)
            }
        #endif
    }

    func browser(_ browser: Browser, willDeleteWebView webView: BraveWebView) {
        browser.cancelQueuedAlerts()

        #if !BRAVE // todo create a fake proxy for this. it is unused completely ATM
            webView.UIDelegate = nil
        #endif
        webView.scrollView.delegate = nil
        webView.removeFromSuperview()
    }

    fileprivate func findSnackbar(_ barToFind: SnackBar) -> Int? {
        let bars = snackBars.subviews
        for (index, bar) in bars.enumerated() {
            if bar === barToFind {
                return index
            }
        }
        return nil
    }

    func updateSnackBarConstraints() {
        snackBars.snp.remakeConstraints { make in
            make.bottom.equalTo(findInPageContainer.snp.top)

            let bars = self.snackBars.subviews
            if bars.count > 0 {
                let view = bars[bars.count-1]
                make.top.equalTo(view.snp.top)
            } else {
                make.height.equalTo(0)
            }

            if traitCollection.horizontalSizeClass != .regular {
                make.leading.trailing.equalTo(self.footer)
                self.snackBars.layer.borderWidth = 0
            } else {
                make.centerX.equalTo(self.footer)
                make.width.equalTo(SnackBarUX.MaxWidth)
                self.snackBars.layer.borderColor = UIConstants.BorderColor.cgColor
                self.snackBars.layer.borderWidth = 1
            }
        }
    }

    // This removes the bar from its superview and updates constraints appropriately
    fileprivate func finishRemovingBar(_ bar: SnackBar) {
        // If there was a bar above this one, we need to remake its constraints.
        if let index = findSnackbar(bar) {
            // If the bar being removed isn't on the top of the list
            let bars = snackBars.subviews
            if index < bars.count-1 {
                // Move the bar above this one
                let nextbar = bars[index+1] as! SnackBar
                nextbar.snp.updateConstraints { make in
                    // If this wasn't the bottom bar, attach to the bar below it
                    if index > 0 {
                        let bar = bars[index-1] as! SnackBar
                        nextbar.bottom = make.bottom.equalTo(bar.snp.top).constraint
                    } else {
                        // Otherwise, we attach it to the bottom of the snackbars
                        nextbar.bottom = make.bottom.equalTo(self.snackBars.snp.bottom).constraint
                    }
                }
            }
        }

        // Really remove the bar
        bar.removeFromSuperview()
    }

    fileprivate func finishAddingBar(_ bar: SnackBar) {
        snackBars.addSubview(bar)
        bar.snp.remakeConstraints { make in
            // If there are already bars showing, add this on top of them
            let bars = self.snackBars.subviews

            // Add the bar on top of the stack
            // We're the new top bar in the stack, so make sure we ignore ourself
            if bars.count > 1 {
                let view = bars[bars.count - 2]
                bar.bottom = make.bottom.equalTo(view.snp.top).offset(0).constraint
            } else {
                bar.bottom = make.bottom.equalTo(self.snackBars.snp.bottom).offset(0).constraint
            }
            make.leading.trailing.equalTo(self.snackBars)
        }
    }

    func showBar(_ bar: SnackBar, animated: Bool) {
        finishAddingBar(bar)
        updateSnackBarConstraints()

        bar.hide()
        view.layoutIfNeeded()
        UIView.animate(withDuration: animated ? 0.25 : 0, animations: { () -> Void in
            bar.show()
            self.view.layoutIfNeeded()
        })
    }

    func removeBar(_ bar: SnackBar, animated: Bool) {
        if let _ = findSnackbar(bar) {
            UIView.animate(withDuration: animated ? 0.25 : 0, animations: { () -> Void in
                bar.hide()
                self.view.layoutIfNeeded()
            }, completion: { success in
                // Really remove the bar
                self.finishRemovingBar(bar)
                self.updateSnackBarConstraints()
            }) 
        }
    }

    func removeAllBars() {
        let bars = snackBars.subviews
        for bar in bars {
            if let bar = bar as? SnackBar {
                bar.removeFromSuperview()
            }
        }
        self.updateSnackBarConstraints()
    }

    func browser(_ browser: Browser, didAddSnackbar bar: SnackBar) {
        if tabManager.selectedTab !== browser {
            return
        }
        showBar(bar, animated: true)
    }

    func browser(_ browser: Browser, didRemoveSnackbar bar: SnackBar) {
        removeBar(bar, animated: true)
    }
    
    func browser(_ browser: Browser, didSelectFindInPageForSelection selection: String) {
        updateFindInPageVisibility(true)
        findInPageBar?.text = selection
    }
}
