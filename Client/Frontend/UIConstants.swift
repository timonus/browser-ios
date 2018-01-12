/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared

public struct UIConstants {
    static let DefaultHomePage = URL(string: "\(WebServer.sharedInstance.base)/about/home/#panel=0")!

    static let AppBackgroundColor = UIColor.white
    static let PrivateModePurple = BraveUX.Purple
    static let PrivateModeActionButtonTintColor = BraveUX.ActionButtonPrivateTintColor
    static let PrivateModeTextHighlightColor = BraveUX.GreyC
    static let PrivateModeReaderModeBackgroundColor = BraveUX.GreyJ

    static let ToolbarHeight: CGFloat = 44
    static let BottomToolbarHeight: CGFloat = {
        if BraveApp.isIPhoneX() {
            return 44 + 34 // 34 is the bottom inset on the iPhone X
        }
        return 44
    }()
    static let DefaultRowHeight: CGFloat = 58
    static let DefaultPadding: CGFloat = 12
    static let SnackbarButtonHeight: CGFloat = 48

    // Static fonts
    static let DefaultChromeSize: CGFloat = 16
    static let DefaultChromeSmallSize: CGFloat = 11
    static let PasscodeEntryFontSize: CGFloat = 36
    static let DefaultChromeFont: UIFont = UIFont.systemFont(ofSize: DefaultChromeSize, weight: UIFontWeightRegular)
    static let DefaultChromeBoldFont = UIFont.boldSystemFont(ofSize: DefaultChromeSize)
    static let DefaultChromeSmallFontBold = UIFont.boldSystemFont(ofSize: DefaultChromeSmallSize)
    static let PasscodeEntryFont = UIFont.systemFont(ofSize: PasscodeEntryFontSize, weight: UIFontWeightBold)

    // These highlight colors are currently only used on Snackbar buttons when they're pressed
    static let HighlightColor = BraveUX.Blue
    static let HighlightText = BraveUX.Blue

    static let PanelBackgroundColor = UIColor.white
    static let SeparatorColor = BraveUX.GreyC
    static let HighlightBlue = BraveUX.Blue
    static let DestructiveRed = BraveUX.Red
    static let BorderColor = BraveUX.GreyE
    static let BorderColorDark = BraveUX.GreyI
    static let BackgroundColor = BraveUX.BraveOrange

    // settings
    static let TableViewHeaderBackgroundColor = BraveUX.GreyA
    static let TableViewHeaderTextColor = BraveUX.GreyH
    static let TableViewRowTextColor = BraveUX.GreyJ
    static let TableViewDisabledRowTextColor = BraveUX.GreyE
    static let TableViewSeparatorColor = BraveUX.GreyC
    static let TableViewHeaderFooterHeight = CGFloat(44)

    // Brave Orange
    static let ControlTintColor = BraveUX.BraveOrange

    // Passcode dot gray
    static let PasscodeDotColor = BraveUX.GreyG

    /// JPEG compression quality for persisted screenshots. Must be between 0-1.
    static let ScreenshotQuality: Float = 0.3
}
