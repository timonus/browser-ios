/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import CoreData
import SnapKit
import Shared

class MainSidePanelViewController : SidePanelBaseViewController {

    let bookmarksPanel = BookmarksPanel(folder: nil)
    fileprivate var bookmarksNavController:UINavigationController!
    
    let history = HistoryPanel()

    var bookmarksButton = UIButton()
    var historyButton = UIButton()

    var settingsButton = UIButton()

    let topButtonsView = UIView()
    let addBookmarkButton = UIButton()

    let divider = UIView()
    
    // Buttons swap out the full page, meaning only one can be active at a time
    var pageButtons: Dictionary<UIButton, UIViewController> {
        return [
            bookmarksButton: bookmarksNavController,
            historyButton: history,
        ]
    }

    override func setupUIElements() {
        super.setupUIElements()
        
        bookmarksNavController = UINavigationController(rootViewController: bookmarksPanel)
        bookmarksNavController.view.backgroundColor = UIColor.white
        containerView.addSubview(topButtonsView)

        topButtonsView.addSubview(bookmarksButton)
        topButtonsView.addSubview(historyButton)
        topButtonsView.addSubview(addBookmarkButton)
        topButtonsView.addSubview(settingsButton)
        topButtonsView.addSubview(divider)

        divider.backgroundColor = BraveUX.ColorForSidebarLineSeparators

        settingsButton.setImage(UIImage(named: "settings")?.withRenderingMode(.alwaysTemplate), for: .normal)
        settingsButton.addTarget(self, action: #selector(onClickSettingsButton), for: .touchUpInside)
        settingsButton.accessibilityLabel = Strings.Settings

        bookmarksButton.setImage(UIImage(named: "bookmarklist"), for: .normal)
        bookmarksButton.accessibilityLabel = Strings.Show_Bookmarks
        
        historyButton.setImage(UIImage(named: "history"), for: .normal)
        historyButton.accessibilityLabel = Strings.Show_History

        addBookmarkButton.addTarget(self, action: #selector(onClickBookmarksButton), for: .touchUpInside)
        addBookmarkButton.setImage(UIImage(named: "bookmark"), for: .normal)
        addBookmarkButton.setImage(UIImage(named: "bookmarkMarked"), for: .selected)
        addBookmarkButton.accessibilityLabel = Strings.Add_Bookmark
        
        pageButtons.keys.forEach { $0.addTarget(self, action: #selector(onClickPageButton), for: .touchUpInside) }
        
        settingsButton.tintColor = BraveUX.ActionButtonTintColor
        addBookmarkButton.tintColor = BraveUX.ActionButtonTintColor

        containerView.addSubview(history.view)
        containerView.addSubview(bookmarksNavController.view)
        
        // Setup the bookmarks button as default
        onClickPageButton(bookmarksButton)

        bookmarksNavController.view.isHidden = false

        containerView.bringSubview(toFront: topButtonsView)

       // NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(historyItemAdded), name: kNotificationSiteAddedToHistory, object: nil)
    }

    func willHide() {
        //check if we are editing bookmark, if so pop controller then continue
        if self.bookmarksNavController?.visibleViewController is BookmarkEditingViewController {
           self.bookmarksNavController?.popViewController(animated: false)
        }
        if self.bookmarksPanel.currentBookmarksPanel().tableView.isEditing {
            self.bookmarksPanel.currentBookmarksPanel().disableTableEditingMode()
        }
    }
    
    func onClickSettingsButton() {
        if getApp().profile == nil {
            return
        }

        let settingsTableViewController = BraveSettingsView(style: .grouped)
        settingsTableViewController.profile = getApp().profile

        let controller = SettingsNavigationController(rootViewController: settingsTableViewController)
        controller.modalPresentationStyle = UIModalPresentationStyle.formSheet
        present(controller, animated: true, completion: nil)
    }

    //For this function to be called there *must* be a selected tab and URL
    //since we disable the button when there's no URL
    //see MainSidePanelViewController#updateBookmarkStatus(isBookmarked,url)
    func onClickBookmarksButton() {
        guard let tab = browserViewController?.tabManager.selectedTab else { return }
        guard let url = tab.url else { return }

        // stop from spamming the button, and enabled is used elsewhere, so create a guard
        struct Guard { static var block = false }
        if Guard.block {
            return
        }
        postAsyncToMain(0.3) {
            Guard.block = false
        }
        Guard.block = true

        //switch to bookmarks 'tab' in case we're looking at history and tapped the add/remove bookmark button
        onClickPageButton(bookmarksButton)

        //TODO -- need to separate the knowledge of whether current site is bookmarked or not from this UI button
        //tracked in https://github.com/brave/browser-ios/issues/375
        if addBookmarkButton.isSelected {
            browserViewController?.removeBookmark(url)
        } else {
            let folder = self.bookmarksPanel.currentBookmarksPanel().currentFolder
            browserViewController?.addBookmark(url, title: tab.title, parentFolder: folder)
        }
    }

    override func setupConstraints() {
        super.setupConstraints()
        
        topButtonsView.snp.remakeConstraints {
            make in
            make.top.equalTo(containerView).offset(spaceForStatusBar())
            make.left.right.equalTo(containerView)
            make.height.equalTo(44.0)
        }

        func common(_ make: ConstraintMaker) {
            make.bottom.equalTo(self.topButtonsView)
            make.height.equalTo(UIConstants.ToolbarHeight)
            make.width.equalTo(60)
        }

        settingsButton.snp.remakeConstraints {
            make in
            common(make)
            make.centerX.equalTo(self.topButtonsView).multipliedBy(0.25)
        }

        divider.snp.remakeConstraints {
            make in
            make.bottom.equalTo(self.topButtonsView)
            make.width.equalTo(self.topButtonsView)
            make.height.equalTo(1.0)
        }

        historyButton.snp.remakeConstraints {
            make in
            make.bottom.equalTo(self.topButtonsView)
            make.height.equalTo(UIConstants.ToolbarHeight)
            make.centerX.equalTo(self.topButtonsView).multipliedBy(0.75)
        }

        bookmarksButton.snp.remakeConstraints {
            make in
            make.bottom.equalTo(self.topButtonsView)
            make.height.equalTo(UIConstants.ToolbarHeight)
            make.centerX.equalTo(self.topButtonsView).multipliedBy(1.25)
        }

        addBookmarkButton.snp.remakeConstraints {
            make in
            make.bottom.equalTo(self.topButtonsView)
            make.height.equalTo(UIConstants.ToolbarHeight)
            make.centerX.equalTo(self.topButtonsView).multipliedBy(1.75)
        }

        bookmarksNavController.view.snp.remakeConstraints { make in
            make.left.right.bottom.equalTo(containerView)
            make.top.equalTo(topButtonsView.snp.bottom)
        }

        history.view.snp.remakeConstraints { make in
            make.left.right.bottom.equalTo(containerView)
            make.top.equalTo(topButtonsView.snp.bottom)
        }
    }
    
    func onClickPageButton(_ sender: UIButton) {
        guard let newView = self.pageButtons[sender]?.view else { return }
        
        // Hide all old views
        self.pageButtons.forEach { (btn, controller) in
            btn.isSelected = false
            btn.tintColor = BraveUX.ActionButtonTintColor
            controller.view.isHidden = true
        }
        
        // Setup the new view
        newView.isHidden = false
        sender.isSelected = true
        sender.tintColor = BraveUX.ActionButtonSelectedTintColor
    }

    override func setHomePanelDelegate(_ delegate: HomePanelDelegate?) {
        bookmarksPanel.homePanelDelegate = delegate
        history.homePanelDelegate = delegate
        
        if (delegate != nil) {
            bookmarksPanel.reloadData()
            history.reloadData()
        }
    }

    
    func updateBookmarkStatus(_ isBookmarked: Bool, url: URL?) {
        //URL will be passed as nil by updateBookmarkStatus from BraveTopViewController
        if url == nil {
            //disable button for homescreen/empty url
            addBookmarkButton.isSelected = false
            addBookmarkButton.isEnabled = false
        }
        else {
            addBookmarkButton.isEnabled = true
            addBookmarkButton.isSelected = isBookmarked
        }
    }
}


