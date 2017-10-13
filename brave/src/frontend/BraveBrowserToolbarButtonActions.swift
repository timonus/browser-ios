/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit

/// A protocol listing methods for toolbars to implement that will
/// attach handlers to various button actions.
protocol BraveBrowserToolbarButtonActions {
    /// Response to button tap where user requests new tab.
    func respondToNewTab(action: UIAlertAction)
    
    /// Responds to button tap where user requests a new private tab.
    func respondToNewPrivateTab(action: UIAlertAction)
}

// MARK: - Default Implementations
extension BraveBrowserToolbarButtonActions {
    func respondToNewTab(action: UIAlertAction) {
        getApp().tabManager.addTabAndSelect()
    }
    
    func respondToNewPrivateTab(action: UIAlertAction) {
        getApp().browserViewController.switchBrowsingMode(toPrivate: true)
    }
}
