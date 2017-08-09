//
//  QuickActions.swift
//  Client
//
//  Created by Emily Toop on 11/20/15.
//  Copyright © 2015 Mozilla. All rights reserved.
//

import Foundation
import Storage

import Shared
import XCGLogger

enum ShortcutType: String {
    case NewTab
    case NewPrivateTab
    //case OpenLastBookmark
    @available(*, deprecated: 2.1) case OpenLastTab

    init?(fullType: String) {
        guard let last = fullType.components(separatedBy: ".").last else { return nil }

        self.init(rawValue: last)
    }

    var type: String {
        return Bundle.main.bundleIdentifier! + ".\(self.rawValue)"
    }
}

protocol QuickActionHandlerDelegate {
    func handleShortCutItemType(_ type: ShortcutType, userData: [String: NSSecureCoding]?)
}

class QuickActions: NSObject {

    fileprivate let log = Logger.browserLogger

    static let QuickActionsVersion = "1.0"
    static let QuickActionsVersionKey = "dynamicQuickActionsVersion"

    static let TabURLKey = "url"
    static let TabTitleKey = "title"

    static var sharedInstance = QuickActions()

    var launchedShortcutItem: UIApplicationShortcutItem?

    // MARK: Administering Quick Actions
    func addDynamicApplicationShortcutItemOfType(_ type: ShortcutType, fromShareItem shareItem: ShareItem, toApplication application: UIApplication) {
            var userData = [QuickActions.TabURLKey: shareItem.url]
            if let title = shareItem.title {
                userData[QuickActions.TabTitleKey] = title
            }
            QuickActions.sharedInstance.addDynamicApplicationShortcutItemOfType(type, withUserData: userData, toApplication: application)
    }

    func addDynamicApplicationShortcutItemOfType(_ type: ShortcutType, withUserData userData: [AnyHashable: Any] = [AnyHashable: Any](), toApplication application: UIApplication) -> Bool {
        // add the quick actions version so that it is always in the user info
        var userData: [AnyHashable: Any] = userData
        userData[QuickActions.QuickActionsVersionKey] = QuickActions.QuickActionsVersion
       // let dynamicShortcutItems = application.shortcutItems ?? [UIApplicationShortcutItem]()

            log.warning("Cannot add static shortcut item of type \(type)")
            return false

    }

    func removeDynamicApplicationShortcutItemOfType(_ type: ShortcutType, fromApplication application: UIApplication) {
        guard var dynamicShortcutItems = application.shortcutItems,
            let index = (dynamicShortcutItems.index{ $0.type == type.type }) else { return }

        dynamicShortcutItems.remove(at: index)
        application.shortcutItems = dynamicShortcutItems
    }


    // MARK: Handling Quick Actions
    func handleShortCutItem(_ shortcutItem: UIApplicationShortcutItem, withBrowserViewController bvc: BrowserViewController ) -> Bool {

        // Verify that the provided `shortcutItem`'s `type` is one handled by the application.
        guard let shortCutType = ShortcutType(fullType: shortcutItem.type) else { return false }

        DispatchQueue.main.async {
            self.handleShortCutItemOfType(shortCutType, userData: shortcutItem.userInfo, browserViewController: bvc)
        }

        return true
    }

    fileprivate func handleShortCutItemOfType(_ type: ShortcutType, userData: [String : NSSecureCoding]?, browserViewController: BrowserViewController) {
        switch(type) {
        case .NewTab:
            handleOpenNewTab(withBrowserViewController: browserViewController, isPrivate: false)
        case .NewPrivateTab:
            handleOpenNewTab(withBrowserViewController: browserViewController, isPrivate: true)
        // even though we're removing OpenLastTab, it's possible that someone will use an existing last tab quick action to open the app
        // the first time after upgrading, so we should still handle it
        case .OpenLastTab:
            if let urlToOpen = (userData?[QuickActions.TabURLKey] as? String)?.asURL {
                handleOpenURL(withBrowserViewController: browserViewController, urlToOpen: urlToOpen)
            }
        }
    }

    fileprivate func handleOpenNewTab(withBrowserViewController bvc: BrowserViewController, isPrivate: Bool) {
        bvc.openBlankNewTabAndFocus(isPrivate: isPrivate)
    }

    fileprivate func handleOpenURL(withBrowserViewController bvc: BrowserViewController, urlToOpen: URL) {
        // open bookmark in a non-private browsing tab
        //bvc.switchToPrivacyMode(isPrivate: false)

        // find out if bookmarked URL is currently open
        // if so, open to that tab,
        // otherwise, create a new tab with the bookmarked URL
        bvc.switchToTabForURLOrOpen(urlToOpen)
    }
}
