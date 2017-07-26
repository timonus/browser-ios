/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared
import Storage

private let log = Logger.browserLogger

extension BrowserViewController: URLBarDelegate {
    fileprivate func showSearchController() {
        if searchController != nil {
            return
        }

        let isPrivate = tabManager.selectedTab?.isPrivate ?? false
        searchController = SearchViewController(isPrivate: isPrivate)
        searchController!.searchEngines = profile.searchEngines
        searchController!.searchDelegate = self
        //searchController!.profile = self.profile

        searchLoader.addListener(searchController!)

        addChildViewController(searchController!)
        view.addSubview(searchController!.view)
        searchController!.view.snp_makeConstraints { make in
            make.top.equalTo(self.header.snp_bottom)
            make.left.right.bottom.equalTo(self.view)
            return
        }

        homePanelController?.view?.isHidden = true

        searchController!.didMove(toParentViewController: self)
    }

    fileprivate func hideSearchController() {
        if let searchController = searchController {
            searchController.willMove(toParentViewController: nil)
            searchController.view.removeFromSuperview()
            searchController.removeFromParentViewController()
            self.searchController = nil
            homePanelController?.view?.isHidden = false
        }
    }
    
    func cancelSearch() {
        urlBar.leaveSearchMode()
        hideSearchController()
        updateInContentHomePanel(tabManager.selectedTab?.url)
    }

    func urlBarDidPressReload(_ urlBar: URLBarView) {
        tabManager.selectedTab?.reload()
    }

    func urlBarDidPressStop(_ urlBar: URLBarView) {
        tabManager.selectedTab?.stop()
    }

    func urlBarDidPressTabs(_ urlBar: URLBarView) {
        self.webViewContainerToolbar.isHidden = true
        updateFindInPageVisibility(false)

        let tabTrayController = TabTrayController(tabManager: tabManager, profile: profile, tabTrayDelegate: self)
        
        for t in tabManager.tabs.internalTabList {
            screenshotHelper.takeScreenshot(t)
        }

        tabTrayController.modalPresentationStyle = .overCurrentContext
        tabTrayController.modalTransitionStyle = .crossDissolve
        // Allowing the tab tray to handle its own animation
        self.navigationController?.present(tabTrayController, animated: false, completion: nil)
        
        self.tabTrayController = tabTrayController
    }

    func urlBarDidPressReaderMode(_ urlBar: URLBarView) {
        if let tab = tabManager.selectedTab {
            if let readerMode = tab.getHelper(ReaderMode.self) {
                switch readerMode.state {
                case .Available:
                    enableReaderMode()
                case .Active:
                    disableReaderMode()
                case .Unavailable:
                    break
                }
            }
        }
    }

    func urlBarDidLongPressReaderMode(_ urlBar: URLBarView) -> Bool {
        guard let tab = tabManager.selectedTab,
            let url = tab.displayURL,
            let result = profile.readingList?.createRecordWithURL(url.absoluteString ?? "", title: tab.title ?? "", addedBy: UIDevice.current.name)
            else {
                UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, Strings.Could_not_add_page_to_Reading_List)
                return false
        }

        switch result {
        case .success:
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, Strings.Added_page_to_reading_list)
        // TODO: https://bugzilla.mozilla.org/show_bug.cgi?id=1158503 provide some form of 'this has been added' visual feedback?
        case .failure(let error):
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, Strings.Could_not_add_page_to_Reading_List)
            log.error("readingList.createRecordWithURL(url: \"\(url.absoluteString)\", ...) failed with error: \(error)")
        }
        return true
    }

    func locationActionsForURLBar(_ urlBar: URLBarView) -> [AccessibleAction] {
        if UIPasteboard.general.string != nil {
            return [pasteGoAction, pasteAction, copyAddressAction]
        } else {
            return [copyAddressAction]
        }
    }

    func urlBarDisplayTextForURL(_ url: URL?) -> String? {
        // use the initial value for the URL so we can do proper pattern matching with search URLs
        var searchURL = self.tabManager.selectedTab?.currentInitialURL
        if searchURL == nil || ErrorPageHelper.isErrorPageURL(searchURL!) {
            searchURL = url
        }
        return profile.searchEngines.queryForSearchURL(searchURL) ?? url?.absoluteString
    }

    func urlBarDidLongPressLocation(_ urlBar: URLBarView) {
        let longPressAlertController = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)

        for action in locationActionsForURLBar(urlBar) {
            longPressAlertController.addAction(action.alertAction(style: .default))
        }

        let cancelAction = UIAlertAction(title: Strings.Cancel, style: .cancel, handler: { (alert: UIAlertAction) -> Void in
        })
        longPressAlertController.addAction(cancelAction)

        let setupPopover = { [unowned self] in
            if let popoverPresentationController = longPressAlertController.popoverPresentationController {
                popoverPresentationController.sourceView = urlBar
                popoverPresentationController.sourceRect = urlBar.frame
                popoverPresentationController.permittedArrowDirections = .any
                popoverPresentationController.delegate = self
            }
        }

        setupPopover()

        if longPressAlertController.popoverPresentationController != nil {
            displayedPopoverController = longPressAlertController
            updateDisplayedPopoverProperties = setupPopover
        }

        self.present(longPressAlertController, animated: true, completion: nil)
    }

    func urlBarDidPressScrollToTop(_ urlBar: URLBarView) {
        if let selectedTab = tabManager.selectedTab {
            // Only scroll to top if we are not showing the home view controller
            if homePanelController == nil {
                selectedTab.webView?.scrollView.setContentOffset(CGPoint.zero, animated: true)
            }
        }
    }

    func urlBarLocationAccessibilityActions(_ urlBar: URLBarView) -> [UIAccessibilityCustomAction]? {
        return locationActionsForURLBar(urlBar).map { $0.accessibilityCustomAction }
    }

    func urlBar(_ urlBar: URLBarView, didEnterText text: String) {
        searchLoader.query = text

        if text.isEmpty {
            hideSearchController()
        } else {
            showSearchController()
            searchController!.searchQuery = text
        }
    }

    func urlBar(_ urlBar: URLBarView, didSubmitText text: String) {
        // If we can't make a valid URL, do a search query.
        // If we still don't have a valid URL, something is broken. Give up.
        guard let url = URIFixup.getURL(text) ??
            profile.searchEngines.defaultEngine.searchURLForQuery(text) else {
                log.error("Error handling URL entry: \"\(text)\".")
                return
        }

        finishEditingAndSubmit(url)
    }

    func urlBarDidEnterSearchMode(_ urlBar: URLBarView) {
        showHomePanelController(false)
    }

    func urlBarDidLeaveSearchMode(_ urlBar: URLBarView) {
        hideSearchController()
        updateInContentHomePanel(tabManager.selectedTab?.url)
    }
}

extension BrowserViewController: BrowserToolbarDelegate {
    func browserToolbarDidPressBack(_ browserToolbar: BrowserToolbarProtocol, button: UIButton) {
        tabManager.selectedTab?.goBack()
    }

    func browserLocationViewDidPressReload(_ browserToolbar: BrowserToolbarProtocol, button: UIButton) {
        tabManager.selectedTab?.reload()
    }

    func browserLocationViewDidPressStop(_ browserToolbar: BrowserToolbarProtocol, button: UIButton) {
        tabManager.selectedTab?.stop()
    }

    func browserToolbarDidPressForward(_ browserToolbar: BrowserToolbarProtocol, button: UIButton) {
        tabManager.selectedTab?.goForward()
    }

    func browserToolbarDidPressBookmark(_ browserToolbar: BrowserToolbarProtocol, button: UIButton) {
        guard let tab = tabManager.selectedTab,
            let url = tab.url else {
                log.error("Bookmark error: No tab is selected, or no URL in tab.")
                return
        }

       Bookmark.contains(url: url, completionOnMain: { isBookmarked in
            if isBookmarked {
                self.removeBookmark(url)
            } else {
                self.addBookmark(url, title: tab.title)
            }
        })
    }

    func browserToolbarDidPressShare(_ browserToolbar: BrowserToolbarProtocol, button: UIButton) {
        telemetry("Share Button Pressed", props: ["bottomToolbar": "\(browserToolbar as? BraveBrowserBottomToolbar != nil)"])
        if let tab = tabManager.selectedTab, let url = tab.displayURL {
            let sourceView = self.navigationToolbar.shareButton
            presentActivityViewController(url, tab: tab, sourceView: sourceView.superview, sourceRect: sourceView.frame, arrowDirection: .up)
        }
    }
    
    func browserToolbarDidPressPwdMgr(browserToolbar: BrowserToolbarProtocol, button: UIButton) {
        if let loginsHelper = tabManager.selectedTab?.getHelper(LoginsHelper.self) {
            loginsHelper.onExecuteTapped(button)
        }
    }
}
