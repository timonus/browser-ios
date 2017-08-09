/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import Shared
/**
 * Data for identifying and constructing a HomePanel.
 */
struct HomePanelDescriptor {
    let makeViewController: (_ profile: Profile) -> UIViewController
    let imageName: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
}

class HomePanels {
    let enabledPanels = [
        HomePanelDescriptor(
            makeViewController: { _ in
                TopSitesPanel()
            },
            imageName: "TopSites",
            accessibilityLabel: Strings.Top_sites,
            accessibilityIdentifier: "HomePanels.TopSites"),

        HomePanelDescriptor(
            makeViewController: { profile in
                let bookmarks = BookmarksPanel(folder: nil)

                let controller = UINavigationController(rootViewController: bookmarks)
                controller.setNavigationBarHidden(true, animated: false)
                // this re-enables the native swipe to pop gesture on UINavigationController for embedded, navigation bar-less UINavigationControllers
                // don't ask me why it works though, I've tried to find an answer but can't.
                // found here, along with many other places: 
                // http://luugiathuy.com/2013/11/ios7-interactivepopgesturerecognizer-for-uinavigationcontroller-with-hidden-navigation-bar/
                controller.interactivePopGestureRecognizer?.delegate = nil
                return controller
            },
            imageName: "Bookmarks",
            accessibilityLabel: Strings.Bookmarks,
            accessibilityIdentifier: "HomePanels.Bookmarks"),

        HomePanelDescriptor(
            makeViewController: { profile in
                let controller = HistoryPanel()
                return controller
            },
            imageName: "History",
            accessibilityLabel: Strings.History,
            accessibilityIdentifier: "HomePanels.History"),

        HomePanelDescriptor(
            makeViewController: { profile in
                let controller = ReadingListPanel()
                controller.profile = profile
                return controller
            },
            imageName: "ReadingList",
            accessibilityLabel: Strings.Reading_list,
            accessibilityIdentifier: "HomePanels.ReadingList"),
    ]
}
