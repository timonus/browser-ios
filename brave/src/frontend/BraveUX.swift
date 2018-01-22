/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

struct BraveUX {
    static let IsRelease = Bundle.main.bundleIdentifier == "com.brave.ios.browser"
    
    static let BraveCommunityURL = URL(string: "https://community.brave.com/")!
    static let BravePrivacyURL = URL(string: "https://brave.com/privacy/")!
    static let PrefKeyOptInDialogWasSeen = "OptInDialogWasSeen"
    static let PrefKeyUserAllowsTelemetry = "userallowstelemetry"
    
    static let MaxTabsInMemory = 9
    
    static var PanelShadowWidth = 11
    
    static let ReaderModeBarHeight = 28
    
    static let BraveOrange = UIColor(rgb: 0xFF3F3F)
    
    static let Blue = UIColor(rgb: 0x00BCD6)
    static let Purple = UIColor(rgb: 0x7D7BDC)
    static let Green = UIColor(rgb: 0x02B999)
    static let Red = UIColor(rgb: 0xE2052A)
    
    static let White = UIColor.white
    static let Black = UIColor.black
    
    static let GreyA = UIColor(rgb: 0xF7F8F9)
    static let GreyB = UIColor(rgb: 0xE7EBEE)
    static let GreyC = UIColor(rgb: 0xDBDFE3)
    static let GreyD = UIColor(rgb: 0xCDD1D5)
    static let GreyE = UIColor(rgb: 0xA7ACB2)
    static let GreyF = UIColor(rgb: 0x999EA2)
    static let GreyG = UIColor(rgb: 0x818589)
    static let GreyH = UIColor(rgb: 0x606467)
    static let GreyI = UIColor(rgb: 0x484B4E)
    static let GreyJ = UIColor(rgb: 0x222326)
    
    static let BraveButtonMessageInUrlBarColor = BraveOrange
    static let BraveButtonMessageInUrlBarShowTime = 0.5
    static let BraveButtonMessageInUrlBarFadeTime = 0.7
    
    static let lockIconColor = GreyJ
    
    static let TabsBarPlusButtonWidth = (UIDevice.current.userInterfaceIdiom == .pad) ? 40 : 0
    
    static let SwitchTintColor = GreyC
    
    static let ToolbarsBackgroundSolidColor = White
    static let DarkToolbarsBackgroundSolidColor = GreyJ
    static let DarkToolbarsBackgroundColor = GreyJ
    
    static let TopSitesStatTitleColor = GreyF
    
    // I am considering using DeviceInfo.isBlurSupported() to set this, and reduce heavy animations
    static var IsHighLoadAnimationAllowed = true
    
    static var WidthOfSlideOut: Int {
        let screenWidth = UIScreen.main.bounds.width
        
        // Panel width is 80% of screen width on all iPhones in portrait and on iPhone4s horizontal.
        // 480 is magic number for iP4S screen height.
        if screenWidth <= 480 {
            return Int(UIScreen.main.bounds.width * 0.8)
        } else {
            return 350
        }
    }
    
    static let PullToReloadDistance = 100
    
    static let PanelClosingThresholdWhenDragging = 0.3 // a percent range 1.0 to 0
    
    static let BrowserViewAlphaWhenShowingTabTray = 0.3
    
    static let PrefKeyIsToolbarHidingEnabled = "PrefKeyIsToolbarHidingEnabled"
    
    static let BackgroundColorForBookmarksHistoryAndTopSites = UIColor.white
    
    static let BackgroundColorForTopSitesPrivate = GreyJ
    
    static let BackgroundColorForSideToolbars = GreyA
    
    static let ColorForSidebarLineSeparators = GreyB
    
    static let PopupDialogColorLight = UIColor.white
    
    // debug settings
    //  static var IsToolbarHidingOff = false
    //  static var IsOverrideScrollingSpeedAndMakeSlower = false // overrides IsHighLoadAnimationAllowed effect
    
    // set to true to show borders around views
    static let DebugShowBorders = false
    
    static let BackForwardDisabledButtonAlpha = CGFloat(0.3)
    static let BackForwardEnabledButtonAlpha = CGFloat(1.0)
    
    static let TopLevelBackgroundColor = UIColor.white
    
    // LocationBar Coloring
    static let LocationBarTextColor = GreyJ
    
    // Setting this to clearColor() and setting LocationContainerBackgroundColor to a definitive color
    //  with transparency (e.g. allwhile 0.3 alpha) is how to make a non-opaque URL bar (e.g. for blurring).
    // Not currently needed since top bar is entirely opaque
    static let LocationBarBackgroundColor = GreyB
    static let LocationContainerBackgroundColor = LocationBarBackgroundColor
    
    // Editing colors same as standard coloring
    static let LocationBarEditModeTextColor = LocationBarTextColor
    static let LocationBarEditModeBackgroundColor = LocationBarBackgroundColor
    
    // LocationBar Private Coloring
    // TODO: Add text coloring
    // See comment for LocationBarBackgroundColor is semi-transparent location bar is desired
    static let LocationBarBackgroundColor_PrivateMode = Black
    static let LocationContainerBackgroundColor_PrivateMode = LocationBarBackgroundColor_PrivateMode
    
    static let LocationBarEditModeBackgroundColor_Private = Black
    static let LocationBarEditModeTextColor_Private = GreyA
    
    // Interesting: compontents of the url can be colored differently: http://www.foo.com
    // Base: http://www and Host: foo.com
    static let LocationBarTextColor_URLBaseComponent = GreyG
    static let LocationBarTextColor_URLHostComponent = LocationBarTextColor
    
    static let TextFieldCornerRadius: CGFloat = 8.0
    static let TextFieldBorderColor_HasFocus = GreyJ
    static let TextFieldBorderColor_NoFocus = GreyJ
    
    static let CancelTextColor = LocationBarTextColor
    // The toolbar button color (for the Normal state). Using default highlight color ATM
    static let ActionButtonTintColor = GreyI
    static let ActionButtonPrivateTintColor = GreyG
    
    // The toolbar button color when (for the Selected state).
    static let ActionButtonSelectedTintColor = Blue
    
    static let AutocompleteTextFieldHighlightColor = Blue
    
    // Yes it could be detected, just make life easier and set this number for now
    static let BottomToolbarNumberButtonsToRightOfBackForward = 3
    static let BackForwardButtonLeftOffset = CGFloat(10)
    
    static let ProgressBarColor = GreyC
    static let ProgressBarDarkColor = GreyI
    
    static let TabTrayCellCornerRadius = CGFloat(6.0)
    static let TabTrayCellBackgroundColor = UIColor.white
    
    /** Determines how fast the swipe needs to be to trigger navigation action(go back/go forward).
     To determine its value, see `UIPanGestureRecognizer.velocity()` */
    static let fastSwipeVelocity: CGFloat = 300
}

