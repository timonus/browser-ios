/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared

public struct UIConstants {
    static let DefaultHomePage = URL(string: "\(WebServer.sharedInstance.base)/about/home/#panel=0")!

    static let AppBackgroundColor = UIColor.white
    static let PrivateModePurple = UIColor(red: 207 / 255, green: 104 / 255, blue: 255 / 255, alpha: 1)
    static let PrivateModeLocationBackgroundColor = UIColor(red: 31 / 255, green: 31 / 255, blue: 31 / 255, alpha: 1)
    static let PrivateModeLocationBorderColor = UIColor(red: 255, green: 255, blue: 255, alpha: 0.15)
    static let PrivateModeActionButtonTintColor = UIColor(red: 255, green: 255, blue: 255, alpha: 1.0)
    static let PrivateModeTextHighlightColor = UIColor(white: 0.5, alpha: 1)
    static let PrivateModeReaderModeBackgroundColor = UIColor(red: 89 / 255, green: 89 / 255, blue: 89 / 255, alpha: 1)

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
    static let HighlightColor = UIColor(red: 205/255, green: 223/255, blue: 243/255, alpha: 0.9)
    static let HighlightText = UIColor(red: 42/255, green: 121/255, blue: 213/255, alpha: 1.0)

    static let PanelBackgroundColor = UIColor.white
    static let SeparatorColor = UIColor(rgb: 0xcccccc)
    static let HighlightBlue = BraveUX.DefaultBlue
    static let DestructiveRed = UIColor(red: 255/255, green: 64/255, blue: 0/255, alpha: 1.0)
    static let BorderColor = UIColor.black.withAlphaComponent(0.3)
    static let BorderColorDark = UIColor.black.withAlphaComponent(0.9)
    static let BackgroundColor = UIColor(red: 0.21, green: 0.23, blue: 0.25, alpha: 1)

    // settings
    static let TableViewHeaderBackgroundColor = UIColor(red: 248/255, green: 248/255, blue: 248/255, alpha: 1.0)
    static let TableViewHeaderTextColor = UIColor(red: 109/255, green: 109/255, blue: 109/255, alpha: 1.0)
    static let TableViewRowTextColor = UIColor(red: 53.55/255, green: 53.55/255, blue: 53.55/255, alpha: 1.0)
    static let TableViewDisabledRowTextColor = UIColor.lightGray
    static let TableViewSeparatorColor = UIColor(red: 200/255, green: 200/255, blue: 200/255, alpha: 1.0)
    static let TableViewHeaderFooterHeight = CGFloat(44)

    // Brave Orange
    static let ControlTintColor = BraveUX.BraveOrange

    // Passcode dot gray
    static let PasscodeDotColor = UIColor(rgb: 0x4A4A4A)

    /// JPEG compression quality for persisted screenshots. Must be between 0-1.
    static let ScreenshotQuality: Float = 0.3
}
