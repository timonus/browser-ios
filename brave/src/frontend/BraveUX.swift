/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

struct BraveUX {
    static let IsRelease = Bundle.main.bundleIdentifier == "com.brave.ios.browser"

    static let BraveCommunityURL = URL(string: "https://community.brave.com/")!
    static let BravePrivacyURL = URL(string: "https://www.brave.com/privacy_ios")!
    static let PrefKeyOptInDialogWasSeen = "OptInDialogWasSeen"
    static let PrefKeyUserAllowsTelemetry = "userallowstelemetry"

    static let MaxTabsInMemory = 9

    static var PanelShadowWidth = 11

    static let ReaderModeBarHeight = 28

    static let BraveOrange = UIColor(colorLiteralRed: 1.0, green: 70/255.0, blue: 0, alpha: 1.0)
    static let BraveButtonMessageInUrlBarColor = BraveOrange
    static let BraveButtonMessageInUrlBarShowTime = 0.5
    static let BraveButtonMessageInUrlBarFadeTime = 0.7
    
    static let lockIconColor = UIColor.black

    static let TabsBarPlusButtonWidth = (UIDevice.current.userInterfaceIdiom == .pad) ? 40 : 0
    
    static let SwitchTintColor = UIColor(white: 0.8, alpha: 1.0)
    
    static let ToolbarsBackgroundSolidColor = UIColor(red: 234/255.0, green: 234/255.0, blue: 234/255.0, alpha: 1.0)
    static let DarkToolbarsBackgroundSolidColor = UIColor(red: 63/255.0, green: 63/255.0, blue: 63/255.0, alpha: 1.0)
    static let DarkToolbarsBackgroundColor = UIColor(red: 57/255.0, green: 57/255.0, blue: 57/255.0, alpha: 0.8)
    
    static let TopSitesStatTitleColor = UIColor(white: 0.6, alpha: 1.0)

    // I am considering using DeviceInfo.isBlurSupported() to set this, and reduce heavy animations
    static var IsHighLoadAnimationAllowed = true

    static let WidthOfSlideOut = 270

    static let PullToReloadDistance = 100

    static let PanelClosingThresholdWhenDragging = 0.3 // a percent range 1.0 to 0

    static let BrowserViewAlphaWhenShowingTabTray = 0.3

    static let PrefKeyIsToolbarHidingEnabled = "PrefKeyIsToolbarHidingEnabled"

    static let BackgroundColorForBookmarksHistoryAndTopSites = UIColor(white: 1.0, alpha: 1.0)
    
    static let BackgroundColorForTopSitesPrivate = UIColor(white: 42 / 255.0, alpha: 1.0)
    
    static let BackgroundColorForSideToolbars = UIColor(white: 242/255.0, alpha: 1.0)
    
    static let ColorForSidebarLineSeparators = UIColor(white: 0.0, alpha: 0.15)

    static let DefaultBlue = UIColor(red: 92/255.0, green: 185/255.0, blue: 247/255.0, alpha: 1.0)
    
    static let PopupDialogColorLight = UIColor(white: 242/255.0, alpha: 1.0)
    
    // debug settings
    //  static var IsToolbarHidingOff = false
    //  static var IsOverrideScrollingSpeedAndMakeSlower = false // overrides IsHighLoadAnimationAllowed effect

    // set to true to show borders around views
    static let DebugShowBorders = false

    static let BackForwardDisabledButtonAlpha = CGFloat(0.3)
    static let BackForwardEnabledButtonAlpha = CGFloat(1.0)
    
    static let TopLevelBackgroundColor = UIColor.white

    // LocationBar Coloring
    static let LocationBarTextColor = UIColor.black
    
    // Setting this to clearColor() and setting LocationContainerBackgroundColor to a definitive color
    //  with transparency (e.g. allwhile 0.3 alpha) is how to make a non-opaque URL bar (e.g. for blurring).
    // Not currently needed since top bar is entirely opaque
    static let LocationBarBackgroundColor = UIColor.white
    static let LocationContainerBackgroundColor = LocationBarBackgroundColor
    
    // Editing colors same as standard coloring
    static let LocationBarEditModeTextColor = LocationBarTextColor
    static let LocationBarEditModeBackgroundColor = LocationBarBackgroundColor
    
    // LocationBar Private Coloring
    // TODO: Add text coloring
    // See comment for LocationBarBackgroundColor is semi-transparent location bar is desired
    static let LocationBarBackgroundColor_PrivateMode = UIColor.black
    static let LocationContainerBackgroundColor_PrivateMode = LocationBarBackgroundColor_PrivateMode

    static let LocationBarEditModeBackgroundColor_Private = UIColor(white: 0/255.0, alpha: 1.0)
    static let LocationBarEditModeTextColor_Private = UIColor(white: 242/255.0, alpha: 1)

    // Interesting: compontents of the url can be colored differently: http://www.foo.com
    // Base: http://www and Host: foo.com
    static let LocationBarTextColor_URLBaseComponent = LocationBarTextColor
    static let LocationBarTextColor_URLHostComponent = LocationBarTextColor

    static let TextFieldCornerRadius: CGFloat = 8.0
    static let TextFieldBorderColor_HasFocus = UIColor.gray
    static let TextFieldBorderColor_NoFocus = UIColor.black

    static let CancelTextColor = LocationBarTextColor
    // The toolbar button color (for the Normal state). Using default highlight color ATM
    static let ActionButtonTintColor = UIColor.black
    static let ActionButtonPrivateTintColor = UIColor.white
    
    // The toolbar button color when (for the Selected state).
    static let ActionButtonSelectedTintColor = BraveUX.DefaultBlue

    static let AutocompleteTextFieldHighlightColor = BraveUX.DefaultBlue

    // Yes it could be detected, just make life easier and set this number for now
    static let BottomToolbarNumberButtonsToRightOfBackForward = 3
    static let BackForwardButtonLeftOffset = CGFloat(10)

    static let ProgressBarColor = UIColor(white: 217/255.0, alpha: 1.0)
    static let ProgressBarDarkColor = UIColor(white: 1.0, alpha: 0.2)
    
    static let TabTrayCellCornerRadius = CGFloat(6.0)
    static let TabTrayCellBackgroundColor = UIColor.white
}
