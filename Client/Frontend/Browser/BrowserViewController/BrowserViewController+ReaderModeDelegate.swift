/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared
private let log = Logger.browserLogger

extension BrowserViewController: ReaderModeStyleViewControllerDelegate {
    func readerModeStyleViewController(_ readerModeStyleViewController: ReaderModeStyleViewController, didConfigureStyle style: ReaderModeStyle) {
        // Persist the new style to the profile
        let encodedStyle: [String:AnyObject] = style.encode()
        profile.prefs.setObject(encodedStyle, forKey: ReaderModeProfileKeyStyle)
        // Change the reader mode style on all tabs that have reader mode active
        for tabIndex in 0..<tabManager.tabCount {
            let tab = tabManager.tabs.internalTabList[tabIndex]
            if let readerMode = tab.getHelper(ReaderMode.self) {
                if readerMode.state == ReaderModeState.Active {
                    readerMode.style = style
                }
            }
        }
    }
}


extension BrowserViewController {
    func updateReaderModeBar() {
//        if let readerModeBar = readerModeBar {
//            if let tab = self.tabManager.selectedTab where tab.isPrivate {
//                readerModeBar.applyTheme(Theme.PrivateMode)
//            } else {
//                readerModeBar.applyTheme(Theme.NormalMode)
//            }
//        }
    }

    func showReaderModeBar(animated: Bool) {
        (urlBar as! BraveURLBarView).showReaderModeBar()
        updateReaderModeBar()
    }

    func hideReaderModeBar(animated: Bool) {
        (urlBar as! BraveURLBarView).hideReaderModeBar()
    }

    /// There are two ways we can enable reader mode. In the simplest case we open a URL to our internal reader mode
    /// and be done with it. In the more complicated case, reader mode was already open for this page and we simply
    /// navigated away from it. So we look to the left and right in the BackForwardList to see if a readerized version
    /// of the current page is there. And if so, we go there.

    func enableReaderMode() {
        guard let tab = tabManager.selectedTab, let webView = tab.webView else { return }

        let backList = webView.backForwardList.backList
        let forwardList = webView.backForwardList.forwardList

        guard let currentURL = webView.URL, let readerModeURL = ReaderModeUtils.encodeURL(currentURL) else { return }

        if backList.count > 1 && backList.last?.URL == readerModeURL {
            webView.goToBackForwardListItem(backList.last!)
        } else if forwardList.count > 0 && forwardList.first?.URL == readerModeURL {
            webView.goToBackForwardListItem(forwardList.first!)
        } else {
            // Store the readability result in the cache and load it. This will later move to the ReadabilityHelper.
            webView.evaluateJavaScript("\(ReaderModeNamespace).readerize()", completionHandler: { (object, error) -> Void in
                if let readabilityResult = ReadabilityResult(object: object) {
                    do {
                        try self.readerModeCache.put(currentURL, readabilityResult)
                    } catch _ {}

                    #if BRAVE
                        // this is not really correct, the original code is ignoring the navigation
                        webView.loadRequest(URLRequest(url: readerModeURL))
                    #else
                        if let nav = webView.loadRequest(URLRequest(url: readerModeURL)) {
                            self.ignoreNavigationInTab(tab, navigation: nav)
                        }
                    #endif
                }
            })
        }
    }

    /// Disabling reader mode can mean two things. In the simplest case we were opened from the reading list, which
    /// means that there is nothing in the BackForwardList except the internal url for the reader mode page. In that
    /// case we simply open a new page with the original url. In the more complicated page, the non-readerized version
    /// of the page is either to the left or right in the BackForwardList. If that is the case, we navigate there.

    func disableReaderMode() {
        if let tab = tabManager.selectedTab,
            let webView = tab.webView {
            let backList = webView.backForwardList.backList
            let forwardList = webView.backForwardList.forwardList

            if let currentURL = webView.URL {
                if let originalURL = ReaderModeUtils.decodeURL(currentURL) {
                    if backList.count > 1 && backList.last?.URL == originalURL {
                        webView.goToBackForwardListItem(backList.last!)
                    } else if forwardList.count > 0 && forwardList.first?.URL == originalURL {
                        webView.goToBackForwardListItem(forwardList.first!)
                    } else {
                        #if BRAVE
                            // this is not really correct, the original code is ignoring the navigation
                            webView.loadRequest(URLRequest(url: originalURL))
                        #else
                            if let nav = webView.loadRequest(URLRequest(url: originalURL)) {
                                self.ignoreNavigationInTab(tab, navigation: nav)
                            }
                        #endif
                    }
                }
            }
        }
    }

    func SELDynamicFontChanged(_ notification: Notification) {
        guard notification.name == NotificationDynamicFontChanged else { return }

        var readerModeStyle = DefaultReaderModeStyle
        if let dict = profile.prefs.dictionaryForKey(ReaderModeProfileKeyStyle) {
            if let style = ReaderModeStyle(dict: dict as [String : AnyObject]) {
                readerModeStyle = style
            }
        }
        readerModeStyle.fontSize = ReaderModeFontSize.defaultSize
        self.readerModeStyleViewController(ReaderModeStyleViewController(), didConfigureStyle: readerModeStyle)
    }
}

extension BrowserViewController: ReaderModeBarViewDelegate {
    func readerModeBar(_ readerModeBar: ReaderModeBarView, didSelectButton buttonType: ReaderModeBarButtonType) {
//        switch buttonType {
//        case .Settings:
        guard let readerMode = tabManager.selectedTab?.getHelper(ReaderMode.self), readerMode.state == ReaderModeState.Active else {
            return
        }
        var readerModeStyle = DefaultReaderModeStyle
        if let dict = profile.prefs.dictionaryForKey(ReaderModeProfileKeyStyle) {
            if let style = ReaderModeStyle(dict: dict as [String : AnyObject]) {
                readerModeStyle = style
            }
        }

        let readerModeStyleViewController = ReaderModeStyleViewController()
        readerModeStyleViewController.delegate = self
        readerModeStyleViewController.readerModeStyle = readerModeStyle
        readerModeStyleViewController.modalPresentationStyle = UIModalPresentationStyle.popover

        let setupPopover = { [unowned self] in
            if let popoverPresentationController = readerModeStyleViewController.popoverPresentationController {
                popoverPresentationController.backgroundColor = UIColor.white
                popoverPresentationController.delegate = self
                popoverPresentationController.sourceView = readerModeBar
                popoverPresentationController.sourceRect = CGRect(x: readerModeBar.frame.width/2, y: readerModeBar.frame.height, width: 1, height: 1)
                popoverPresentationController.permittedArrowDirections = UIPopoverArrowDirection.up
            }
        }

        setupPopover()

        if readerModeStyleViewController.popoverPresentationController != nil {
            displayedPopoverController = readerModeStyleViewController
            updateDisplayedPopoverProperties = setupPopover
        }

        self.present(readerModeStyleViewController, animated: true, completion: nil)
    }
}
