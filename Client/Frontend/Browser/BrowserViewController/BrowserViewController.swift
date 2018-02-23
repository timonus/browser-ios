/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import WebKit
import Shared
import CoreData
import SnapKit
import XCGLogger

import ReadingList
import MobileCoreServices

private let log = Logger.browserLogger


struct BrowserViewControllerUX {
    static let BackgroundColor = UIConstants.AppBackgroundColor
    static let ShowHeaderTapAreaHeight: CGFloat = 32
    static let BookmarkStarAnimationDuration: Double = 0.5
    static let BookmarkStarAnimationOffset: CGFloat = 80
}

class BrowserViewController: UIViewController {

    // Reader mode bar is currently (temporarily) glued onto the urlbar bottom, and is outside of the frame of the urlbar.
    // Need this to detect touches as a result
    class ViewToCaptureReaderModeTap : UIView {
        weak var urlBarView:BraveURLBarView?
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            if let toolbar = urlBarView?.readerModeToolbar {
                let pointForTargetView = toolbar.convert(point, from: self)
                let isHidden = toolbar.isHidden || toolbar.convert(CGPoint(x:0,y:0), to: nil).y < UIConstants.ToolbarHeight
                if !isHidden && toolbar.bounds.contains(pointForTargetView) {
                    return toolbar.settingsButton
                }
            }
            return super.hitTest(point, with: event)
        }
    }

    var homePanelController: HomePanelViewController?
    var webViewContainer: UIView!
    var urlBar: URLBarView!
    var readerModeCache: ReaderModeCache
    var statusBarOverlay: UIView!
    fileprivate(set) var toolbar: BraveBrowserBottomToolbar?
    var searchController: SearchViewController?
    var screenshotHelper: ScreenshotHelper!
    var homePanelIsInline = true
    var searchLoader: SearchLoader!
    let snackBars = UIView()
    let webViewContainerToolbar = UIView()
    var findInPageBar: FindInPageBar?
    let findInPageContainer = UIView()

    // popover rotation handling
    var displayedPopoverController: UIViewController?
    var updateDisplayedPopoverProperties: (() -> ())?

    var openInHelper: OpenInHelper?

    // location label actions
    var pasteGoAction: AccessibleAction!
    var pasteAction: AccessibleAction!
    var copyAddressAction: AccessibleAction!

    weak var tabTrayController: TabTrayController?

    let profile: Profile
    let tabManager: TabManager

    // These views wrap the urlbar and toolbar to provide background effects on them
    var header: BlurWrapper!
    var footer: UIView!
    var footerBackdrop: UIView!
    var footerBackground: UIView?
    var topTouchArea: UIButton!

    // Backdrop used for displaying greyed background for private tabs
    var webViewContainerBackdrop: UIView!

    var scrollController = BraveScrollController()

    fileprivate var keyboardState: KeyboardState?
    
    fileprivate var currentThemeName: String?

    let WhiteListedUrls = ["\\/\\/itunes\\.apple\\.com\\/"]

    // Tracking navigation items to record history types.
    // TODO: weak references?
    var ignoredNavigation = Set<WKNavigation>()

    var navigationToolbar: BrowserToolbarProtocol {
        return toolbar ?? urlBar
    }

    static var instanceAsserter = 0 // Brave: it is easy to get confused as to which fx classes are effectively singletons
    
    /// Flag to check if keyboard was triggered by find in page action.
    fileprivate var showKeyboardFromFindInPage = false

    init(profile: Profile, tabManager: TabManager) {
        self.profile = profile
        self.tabManager = tabManager
        self.readerModeCache = DiskReaderModeCache.sharedInstance
        super.init(nibName: nil, bundle: nil)
        didInit()

        BrowserViewController.instanceAsserter += 1
        assert(BrowserViewController.instanceAsserter == 1)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func selectedTabChanged(_ selected: Browser) {}

    override var supportedInterfaceOrientations : UIInterfaceOrientationMask {
        if UIDevice.current.userInterfaceIdiom == .phone {
            return UIInterfaceOrientationMask.allButUpsideDown
        } else {
            return UIInterfaceOrientationMask.all
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        displayedPopoverController?.dismiss(animated: true, completion: nil)

        guard let displayedPopoverController = self.displayedPopoverController else {
            return
        }

        coordinator.animate(alongsideTransition: nil) { context in
            self.updateDisplayedPopoverProperties?()
            self.present(displayedPopoverController, animated: true, completion: nil)
        }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        log.debug("BVC received memory warning")
    }

    fileprivate func didInit() {
        screenshotHelper = ScreenshotHelper(controller: self)
        tabManager.addDelegate(self)
        tabManager.addNavigationDelegate(self)
        
        NotificationCenter.default.addObserver(self, selector: #selector(leftSwipeToolbar), name: LeftSwipeToolbarNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(rightSwipeToolbar), name: RightSwipeToolbarNotification, object: nil)
    }

    func shouldShowFooterForTraitCollection(_ previousTraitCollection: UITraitCollection) -> Bool {
        return previousTraitCollection.verticalSizeClass != .compact &&
               previousTraitCollection.horizontalSizeClass != .regular
    }
    
    var swipeScheduled = false
    func leftSwipeToolbar() {
        if !swipeScheduled {
            swipeScheduled = true
            postAsyncToMain(0.1) {
                if let browser = getApp().tabManager.selectedTab {
                    self.screenshotHelper.takeScreenshot(browser)
                }
                self.swipeScheduled = false
                getApp().tabManager.selectNextTab()
            }
        }
    }
    
    func rightSwipeToolbar() {
        if !swipeScheduled {
            swipeScheduled = true
            postAsyncToMain(0.1) {
                if let browser = getApp().tabManager.selectedTab {
                    self.screenshotHelper.takeScreenshot(browser)
                }
                self.swipeScheduled = false
                getApp().tabManager.selectPreviousTab()
            }
        }
    }

    func toggleSnackBarVisibility(_ show: Bool) {
        if show {
            UIView.animate(withDuration: 0.1, animations: { self.snackBars.isHidden = false })
        } else {
            snackBars.isHidden = true
        }
    }

    func updateToolbarStateForTraitCollection(_ newCollection: UITraitCollection) {
        let bottomToolbarIsHidden = shouldShowFooterForTraitCollection(newCollection)

        urlBar.hideBottomToolbar(!bottomToolbarIsHidden)
        
        // TODO: (IMO) should be refactored to not destroy and recreate the toolbar all the time
        // This would prevent theme knowledge from being retained as well
        toolbar?.removeFromSuperview()
        toolbar?.browserToolbarDelegate = nil
        footerBackground?.removeFromSuperview()
        footerBackground = nil
        toolbar = nil

        if bottomToolbarIsHidden {
            toolbar = BraveBrowserBottomToolbar()
            toolbar?.browserToolbarDelegate = self
            toolbar?.drawTopBorder = false
            
            footerBackground = UIView()
            footerBackground?.translatesAutoresizingMaskIntoConstraints = false
            footerBackground?.addSubview(toolbar!)
            footer.addSubview(footerBackground!)
            
            footer.layer.shadowOffset = CGSize(width: 0, height: -0.5)
            footer.layer.shadowRadius = 0
            footer.layer.shadowOpacity = 1.0
            footer.layer.masksToBounds = false
            
            // Since this is freshly created, theme needs to be applied
            if let currentThemeName = self.currentThemeName {
                self.applyTheme(currentThemeName)
            }
        }

        view.setNeedsUpdateConstraints()
        if let home = homePanelController {
            home.view.setNeedsUpdateConstraints()
        }

        if let tab = tabManager.selectedTab,
               let webView = tab.webView {
            updateURLBarDisplayURL(tab: tab)
            navigationToolbar.updateBackStatus(webView.canGoBack)
            navigationToolbar.updateForwardStatus(webView.canGoForward)
            navigationToolbar.updateReloadStatus(tab.loading)
        }
    }

    override func willTransition(to newCollection: UITraitCollection, with coordinator: UIViewControllerTransitionCoordinator) {
        super.willTransition(to: newCollection, with: coordinator)

        // During split screen launching on iPad, this callback gets fired before viewDidLoad gets a chance to
        // set things up. Make sure to only update the toolbar state if the view is ready for it.
        if isViewLoaded {
            updateToolbarStateForTraitCollection(newCollection)
        }

        displayedPopoverController?.dismiss(animated: true, completion: nil)

        // WKWebView looks like it has a bug where it doesn't invalidate it's visible area when the user
        // performs a device rotation. Since scrolling calls
        // _updateVisibleContentRects (https://github.com/WebKit/webkit/blob/master/Source/WebKit2/UIProcess/API/Cocoa/WKWebView.mm#L1430)
        // this method nudges the web view's scroll view by a single pixel to force it to invalidate.
        if let scrollView = self.tabManager.selectedTab?.webView?.scrollView {
            let contentOffset = scrollView.contentOffset
            coordinator.animate(alongsideTransition: { context in
                scrollView.setContentOffset(CGPoint(x: contentOffset.x, y: contentOffset.y + 1), animated: true)
                self.scrollController.showToolbars(animated: false)
            }, completion: { context in
                scrollView.setContentOffset(CGPoint(x: contentOffset.x, y: contentOffset.y), animated: false)
            })
        }
    }

    func SELappDidEnterBackgroundNotification() {
        displayedPopoverController?.dismiss(animated: false, completion: nil)
    }

    func SELtappedTopArea() {
        scrollController.showToolbars(animated: true)
    }

    func SELappWillResignActiveNotification() {
        // If we are displying a private tab, hide any elements in the browser that we wouldn't want shown
        // when the app is in the home switcher
        guard let privateTab = tabManager.selectedTab, privateTab.isPrivate else {
            return
        }

        webViewContainerBackdrop.alpha = 1
        webViewContainer.alpha = 0
        urlBar.locationView.alpha = 0
    }

    func SELappDidBecomeActiveNotification() {
        // Re-show any components that might have been hidden because they were being displayed
        // as part of a private mode tab
        UIView.animate(withDuration: 0.2, delay: 0, options: UIViewAnimationOptions(), animations: {
            self.webViewContainer.alpha = 1
            self.urlBar.locationView.alpha = 1
            self.view.backgroundColor = UIColor.clear
        }, completion: { _ in
            self.webViewContainerBackdrop.alpha = 0
        })
        
        // Re-show toolbar which might have been hidden during scrolling (prior to app moving into the background)
        scrollController.showToolbars(animated: false)
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIApplicationWillResignActive, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
    }

    override func loadView() {
        let v = ViewToCaptureReaderModeTap(frame: UIScreen.main.bounds)
        view = v
    }

    override func viewDidLoad() {
        log.debug("BVC viewDidLoad…")
        super.viewDidLoad()
        log.debug("BVC super viewDidLoad called.")

        NotificationCenter.default.addObserver(self, selector: #selector(BrowserViewController.SELappWillResignActiveNotification), name: NSNotification.Name.UIApplicationWillResignActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(BrowserViewController.SELappDidBecomeActiveNotification), name: NSNotification.Name.UIApplicationDidBecomeActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(BrowserViewController.SELappDidEnterBackgroundNotification), name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)
        KeyboardHelper.defaultHelper.addDelegate(self)

        log.debug("BVC adding footer and header…")
        footerBackdrop = UIView()
        footerBackdrop.backgroundColor = BrowserViewControllerUX.BackgroundColor
        view.addSubview(footerBackdrop)

        log.debug("BVC setting up webViewContainer…")
        webViewContainerBackdrop = UIView()
        webViewContainerBackdrop.backgroundColor = BrowserViewControllerUX.BackgroundColor
        webViewContainerBackdrop.alpha = 0
        view.addSubview(webViewContainerBackdrop)

        webViewContainer = UIView()
        webViewContainer.addSubview(webViewContainerToolbar)
        view.addSubview(webViewContainer)

        log.debug("BVC setting up status bar…")
        statusBarOverlay = UIView()
        statusBarOverlay.backgroundColor = BraveUX.ToolbarsBackgroundSolidColor
        view.addSubview(statusBarOverlay)

        log.debug("BVC setting up top touch area…")
        topTouchArea = UIButton()
        topTouchArea.isAccessibilityElement = false
        topTouchArea.addTarget(self, action: #selector(BrowserViewController.SELtappedTopArea), for: UIControlEvents.touchUpInside)
        view.addSubview(topTouchArea)

        // Setup the URL bar, wrapped in a view to get transparency effect
#if BRAVE
        // Brave: need to inject in the middle of this function, override won't work
        urlBar = BraveURLBarView()
        urlBar.translatesAutoresizingMaskIntoConstraints = false
        urlBar.delegate = self
        urlBar.browserToolbarDelegate = self
        header = BlurWrapper(view: urlBar)
        view.addSubview(header)
    
        header.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        header.layer.shadowRadius = 0
        header.layer.shadowOpacity = 1.0
        header.layer.masksToBounds = false

        (view as! ViewToCaptureReaderModeTap).urlBarView = (urlBar as! BraveURLBarView)
 #endif

        // UIAccessibilityCustomAction subclass holding an AccessibleAction instance does not work, thus unable to generate AccessibleActions and UIAccessibilityCustomActions "on-demand" and need to make them "persistent" e.g. by being stored in BVC
        pasteGoAction = AccessibleAction(name: Strings.Paste_and_Go, handler: { () -> Bool in
            if let pasteboardContents = UIPasteboard.general.string {
                self.urlBar(self.urlBar, didSubmitText: pasteboardContents)
                return true
            }
            return false
        })
        pasteAction = AccessibleAction(name: Strings.Paste, handler: { () -> Bool in
            if let pasteboardContents = UIPasteboard.general.string {
                // Enter overlay mode and fire the text entered callback to make the search controller appear.
                self.urlBar.enterSearchMode(pasteboardContents, pasted: true)
                self.urlBar(self.urlBar, didEnterText: pasteboardContents)
                return true
            }
            return false
        })
        copyAddressAction = AccessibleAction(name: Strings.Copy_Address, handler: { () -> Bool in
            if let url = self.urlBar.currentURL {
                UIPasteboard.general.url = url
            }
            return true
        })


        log.debug("BVC setting up search loader…")
        searchLoader = SearchLoader(profile: profile, urlBar: urlBar)

        footer = UIView()
        self.view.addSubview(footer)
        self.view.addSubview(snackBars)
        snackBars.backgroundColor = UIColor.clear
        self.view.addSubview(findInPageContainer)

        scrollController.urlBar = urlBar
        scrollController.header = header
        scrollController.footer = footer
        scrollController.snackBars = snackBars
        
        // No access to PrivateBrowsing.singleton.isOn yet but tried other arragements and those would require more refactoring.access
        // TODO: refactor when theme is called, take into account private/normal browsing modes.
        applyTheme(Theme.NormalMode)
    }

    var headerHeightConstraint: Constraint?
    var webViewContainerTopOffset: Constraint?
    var webViewHeightConstraint: Constraint?

    func setupConstraints() {
        
        statusBarOverlay.snp.makeConstraints { make in
            make.top.right.left.equalTo(statusBarOverlay.superview!)
            make.bottom.equalTo(topLayoutGuide.snp.bottom)
        }
        
        header.snp.makeConstraints { make in
            
            scrollController.headerTopConstraint = make.top.equalTo(self.topLayoutGuide.snp.bottom).constraint
            if let headerHeightConstraint = headerHeightConstraint {
                headerHeightConstraint.update(offset: BraveURLBarView.CurrentHeight)
            } else {
                headerHeightConstraint = make.height.equalTo(BraveURLBarView.CurrentHeight).constraint
            }

            if UIDevice.current.userInterfaceIdiom == .phone {
                // iPad layout is customized in BraveTopViewController for showing panels
                make.left.right.equalTo(header.superview!)
            }
        }
        
        // webViewContainer constraints set in Brave subclass.
        // TODO: This should be centralized

        webViewContainerBackdrop.snp.makeConstraints { make in
            make.edges.equalTo(webViewContainer)
        }

        webViewContainerToolbar.snp.makeConstraints { make in
            make.left.right.top.equalTo(webViewContainer)
            make.height.equalTo(0)
        }
    }

    override func viewDidLayoutSubviews() {
        log.debug("BVC viewDidLayoutSubviews…")
        super.viewDidLayoutSubviews()
        log.debug("BVC done.")

        // Updating footer contraints in viewSafeAreaInsetsDidChange, doesn't work when view is loaded so we do it here.
        if #available(iOS 11.0, *), DeviceDetector.iPhoneX {
            footerBackground?.snp.updateConstraints { make in
                make.bottom.equalTo(self.footer).inset(self.view.safeAreaInsets.bottom)
            }
        }
    }
    
    override func viewSafeAreaInsetsDidChange() {
        if #available(iOS 11.0, *), DeviceDetector.iPhoneX {
            let keyboardHeight = keyboardState?.intersectionHeightForView(self.view) ?? 0
            adjustFindInPageBar(safeArea: keyboardHeight == 0)
        }
    }

    func loadQueuedTabs() {
        log.debug("Loading queued tabs in the background.")

        // Chain off of a trivial deferred in order to run on the background queue.
        succeed().upon() { res in
            self.dequeueQueuedTabs()
        }
    }

    fileprivate func dequeueQueuedTabs() {
        // Brave doesn't have queued tabs
    }

    override func viewWillAppear(_ animated: Bool) {
        log.debug("BVC viewWillAppear.")
        super.viewWillAppear(animated)
        log.debug("BVC super.viewWillAppear done.")
        
#if !DISABLE_INTRO_SCREEN
        // On iPhone, if we are about to show the On-Boarding, blank out the browser so that it does
        // not flash before we present. This change of alpha also participates in the animation when
        // the intro view is dismissed.
        if UIDevice.current.userInterfaceIdiom == .phone {
            self.view.alpha = (profile.prefs.intForKey(IntroViewControllerSeenProfileKey) != nil) ? 1.0 : 0.0
        }
#endif
#if !BRAVE
        if activeCrashReporter?.previouslyCrashed ?? false {
            log.debug("Previously crashed.")

            // Reset previous crash state
            activeCrashReporter?.resetPreviousCrashState()

            let optedIntoCrashReporting = profile.prefs.boolForKey("crashreports.send.always")
            if optedIntoCrashReporting == nil {
                // Offer a chance to allow the user to opt into crash reporting
                showCrashOptInAlert()
            } else {
                showRestoreTabsAlert()
            }
        } else {
           tabManager.restoreTabs()
        }

        updateTabCountUsingTabManager(tabManager, animated: false)
#endif
    }

    fileprivate func shouldRestoreTabs() -> Bool {
        let tabsToRestore = TabMO.getAll()
        let onlyNoHistoryTabs = !tabsToRestore.every {
            if let history = $0.urlHistorySnapshot as? [String] {
                if history.count > 1 {
                    return false
                }
                if let first = history.first {
                    return first.contains(WebServer.sharedInstance.base)
                }
            }
            return true
        }
        return !onlyNoHistoryTabs && !DebugSettingsBundleOptions.skipSessionRestore
    }

    override func viewDidAppear(_ animated: Bool) {
        log.debug("BVC viewDidAppear.")

#if !DISABLE_INTRO_SCREEN
        presentIntroViewController()
#endif

        log.debug("BVC intro presented.")
        self.webViewContainerToolbar.isHidden = false

        log.debug("BVC calling super.viewDidAppear.")
        super.viewDidAppear(animated)
        log.debug("BVC done.")

        if shouldShowWhatsNewTab() {
            if let whatsNewURL = SupportUtils.URLForTopic("new-ios") {
                self.openURLInNewTab(whatsNewURL)
                profile.prefs.setString(AppInfo.appVersion, forKey: LatestAppVersionProfileKey)
            }
        }

        showQueuedAlertIfAvailable()
    }
    
    func presentBrowserLockCallout() {
        if profile.prefs.boolForKey(kPrefKeySetBrowserLock) == true || profile.prefs.boolForKey(kPrefKeyPopupForBrowserLock) == true {
            return
        }
        
        weak var weakSelf = self
        let popup = AlertPopupView(image: UIImage(named: "browser_lock_popup"), title: Strings.Browser_lock_callout_title, message: Strings.Browser_lock_callout_message)
        popup.addButton(title: Strings.Browser_lock_callout_not_now) { () -> PopupViewDismissType in
            weakSelf?.profile.prefs.setBool(true, forKey: kPrefKeyPopupForBrowserLock)
            return .flyDown
        }
        popup.addDefaultButton(title: Strings.Browser_lock_callout_enable) { () -> PopupViewDismissType in
            if getApp().profile == nil {
                return .flyUp
            }
            
            weakSelf?.profile.prefs.setBool(true, forKey: kPrefKeyPopupForBrowserLock)
            
            let settingsTableViewController = BraveSettingsView(style: .grouped)
            settingsTableViewController.profile = getApp().profile
            
            let controller = SettingsNavigationController(rootViewController: settingsTableViewController)
            controller.modalPresentationStyle = UIModalPresentationStyle.formSheet
            weakSelf?.present(controller, animated: true, completion: {
                let view = PinViewController()
                view.delegate = settingsTableViewController
                controller.pushViewController(view, animated: true)
            })
            
            return .flyUp
        }
        popup.showWithType(showType: .normal)
    }

    fileprivate func shouldShowWhatsNewTab() -> Bool {
        guard let latestMajorAppVersion = profile.prefs.stringForKey(LatestAppVersionProfileKey)?.components(separatedBy: ".").first else {
            return DeviceInfo.hasConnectivity()
        }

        return latestMajorAppVersion != AppInfo.majorAppVersion && DeviceInfo.hasConnectivity()
    }

    fileprivate func showQueuedAlertIfAvailable() {
        if var queuedAlertInfo = tabManager.selectedTab?.dequeueJavascriptAlertPrompt() {
            let alertController = queuedAlertInfo.alertController()
            alertController.delegate = self
            present(alertController, animated: true, completion: nil)
        }
    }

    func resetBrowserChrome() {
        // animate and reset transform for browser chrome
        urlBar.updateAlphaForSubviews(1)

        [header, footer, footerBackdrop].forEach { view in
                view?.transform = CGAffineTransform.identity
        }
    }

    override func updateViewConstraints() {
        super.updateViewConstraints()

        topTouchArea.snp.remakeConstraints { make in
            make.top.left.right.equalTo(self.view)
            make.height.equalTo(BrowserViewControllerUX.ShowHeaderTapAreaHeight)
        }
        
        footer.snp.remakeConstraints { make in
            scrollController.footerBottomConstraint = make.bottom.equalTo(self.view.snp.bottom).constraint
            make.top.equalTo(self.snackBars.snp.top)
            make.leading.trailing.equalTo(self.view)
        }

        footerBackdrop.snp.remakeConstraints { make in
            make.edges.equalTo(self.footer)
        }

        updateSnackBarConstraints()
        footerBackground?.snp.remakeConstraints { make in
            make.left.right.equalTo(self.footer)
            make.height.equalTo(UIConstants.ToolbarHeight) // Set this to toolbar height. Use BottomToolbarHeight for hiding footer
            make.bottom.equalTo(self.footer)
        }
        urlBar.setNeedsUpdateConstraints()
        
        webViewContainer.snp.remakeConstraints { make in
            if #available(iOS 11.0, *), DeviceDetector.iPhoneX {
                make.left.equalTo(self.view.safeAreaLayoutGuide.snp.left)
                make.right.equalTo(self.view.safeAreaLayoutGuide.snp.right)
            } else {
                make.left.right.equalTo(self.view)
            }
            make.top.equalTo(self.header.snp.bottom)
            
            let findInPageHeight = (findInPageBar == nil) ? 0 : UIConstants.ToolbarHeight
            if let toolbar = self.toolbar {
                make.bottom.equalTo(toolbar.snp.top).offset(-findInPageHeight)
            } else {
                make.bottom.equalTo(self.view).offset(-findInPageHeight)
            }
        }

        // Remake constraints even if we're already showing the home controller.
        // The home controller may change sizes if we tap the URL bar while on about:home.
        homePanelController?.view.snp.remakeConstraints { make in
            make.top.equalTo(self.header.snp.bottom)
            make.left.right.equalTo(self.view)
            if self.homePanelIsInline {
                make.bottom.equalTo(self.toolbar?.snp.top ?? self.view.snp.bottom)
            } else {
                make.bottom.equalTo(self.view.snp.bottom)
            }
        }

        findInPageContainer.snp.remakeConstraints { make in
            make.left.right.equalTo(self.view)

            if let keyboardHeight = keyboardState?.intersectionHeightForView(self.view), keyboardHeight > 0 {
                make.bottom.equalTo(self.view).offset(-keyboardHeight)
            } else if let toolbar = self.toolbar {
                make.bottom.equalTo(toolbar.snp.top)
            } else {
                make.bottom.equalTo(self.view)
            }
        }
    }

    func showHomePanelController(_ inline: Bool) {
        log.debug("BVC showHomePanelController.")
        homePanelIsInline = inline

        #if BRAVE
            // we always want to show the bottom toolbar, if this is false, the bottom toolbar is hidden
            homePanelIsInline = true
        #endif

        if homePanelController == nil {
            homePanelController = HomePanelViewController()
            homePanelController!.profile = profile
            homePanelController!.delegate = self
            homePanelController!.url = tabManager.selectedTab?.displayURL
            homePanelController!.view.alpha = 0

            addChildViewController(homePanelController!)
            view.addSubview(homePanelController!.view)
            homePanelController!.didMove(toParentViewController: self)
        }

        // We have to run this animation, even if the view is already showing because there may be a hide animation running
        // and we want to be sure to override its results.
        UIView.animate(withDuration: 0.2, animations: { () -> Void in
            self.homePanelController!.view.alpha = 1
        }, completion: { finished in
            if finished {
                self.webViewContainer.accessibilityElementsHidden = true
                UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil)
            }
        })
        view.setNeedsUpdateConstraints()
        log.debug("BVC done with showHomePanelController.")
    }

    func hideHomePanelController() {
        guard let homePanel = homePanelController else { return }
        homePanelController = nil

        // UIView animation conflict is causing completion block to run prematurely
        let duration = 0.3

        UIView.animate(withDuration: duration, delay: 0, options: .beginFromCurrentState, animations: { () -> Void in
            homePanel.view.alpha = 0
            }, completion: { (b) in })

        postAsyncToMain(duration) {
            homePanel.willMove(toParentViewController: nil)
            homePanel.view.removeFromSuperview()
            homePanel.removeFromParentViewController()
            self.webViewContainer.accessibilityElementsHidden = false
            UIAccessibilityPostNotification(UIAccessibilityScreenChangedNotification, nil)
        }
    }

    func updateInContentHomePanel(_ url: URL?) {
        if !urlBar.inSearchMode {
            if AboutUtils.isAboutHomeURL(url){
                urlBar.updateBookmarkStatus(false)
                showHomePanelController((tabManager.selectedTab?.canGoForward ?? false || tabManager.selectedTab?.canGoBack ?? false))
            } else {
                hideHomePanelController()
            }
        }
    }

    func finishEditingAndSubmit(_ url: URL) {
        guard let tab = tabManager.selectedTab else {
            return
        }

        // Ugly UI when submit completes, the view stack pops back to homepanel stats, which flash
        // then disappear as the webview is reshown. Hide the elements so the homepanel is just a white screen
        homePanelController?.view.subviews.forEach { $0.isHidden = true }
        tabManager.selectedTab?.webView?.backgroundColor = UIColor.white

        urlBar.currentURL = url
        urlBar.leaveSearchMode()

        _ = tab.loadRequest(URLRequest(url: url))
    }

    func addBookmark(_ url: URL?, title: String?, parentFolder: Bookmark? = nil) {
        // Custom title can only be applied during an edit
        _ = Bookmark.add(url: url, title: title, parentFolder: parentFolder)
        self.urlBar.updateBookmarkStatus(true)
    }

    func removeBookmark(_ url: URL) {
        if Bookmark.remove(forUrl: url, context: DataController.shared.mainThreadContext) {
            self.urlBar.updateBookmarkStatus(false)
        }
    }

    override func accessibilityPerformEscape() -> Bool {
        if urlBar.inSearchMode {
            urlBar.SELdidClickCancel()
            return true
        } else if let selectedTab = tabManager.selectedTab, selectedTab.canGoBack {
            selectedTab.goBack()
            return true
        }
        return false
    }

//    private func runScriptsOnWebView(webView: WKWebView) {
//        webView.evaluateJavaScript("__firefox__.favicons.getFavicons()", completionHandler:nil)
//    }

    func updateUIForReaderHomeStateForTab(_ tab: Browser) {
        updateURLBarDisplayURL(tab: tab)
        updateInContentHomePanel(tab.url)
        
        scrollController.showToolbars(animated: false)
    }

    fileprivate func isWhitelistedUrl(_ url: URL) -> Bool {
        for entry in WhiteListedUrls {
            if let _ = url.absoluteString.range(of: entry, options: .regularExpression) {
                return UIApplication.shared.canOpenURL(url)
            }
        }
        return false
    }

    /// Updates the URL bar text and button states.
    /// Call this whenever the page URL changes.
    func updateURLBarDisplayURL(tab _tab: Browser?) {
        guard let selected = tabManager.selectedTab else { return }
        let tab = _tab != nil ? _tab! : selected

        urlBar.currentURL = tab.displayURL

        let isPage = tab.displayURL?.isWebPage() ?? false
        navigationToolbar.updatePageStatus(isPage)

        guard let url = tab.url else {
            return
        }

        let isBookmarked = Bookmark.contains(url: url, context: DataController.shared.mainThreadContext)
        self.urlBar.updateBookmarkStatus(isBookmarked)
    }
    // Mark: Opening New Tabs

    func switchBrowsingMode(toPrivate isPrivate: Bool, request: URLRequest? = nil) {
        if PrivateBrowsing.singleton.isOn == isPrivate {
            // No change
            return
        }
        
        func update() {
            applyTheme(isPrivate ? Theme.PrivateMode : Theme.NormalMode)
            
            let tabTrayController = self.tabTrayController ?? TabTrayController(tabManager: tabManager, profile: profile, tabTrayDelegate: self)
            tabTrayController.changePrivacyMode(isPrivate)
            self.tabTrayController = tabTrayController
            
            // Should be fixed as part of larger privatemode refactor
            //  But currently when switching to PM tabCount == 1, but no tabs actually
            //  exist, so causes lot of issues, explicit check for isPM
            if tabManager.tabCount == 0 || request != nil || isPrivate {
                tabManager.addTabAndSelect(request)
            }
        }
        
        if isPrivate {
            PrivateBrowsing.singleton.enter()
            update()
        } else {
            PrivateBrowsing.singleton.exit().uponQueue(DispatchQueue.main) {
                let _ = self.tabManager.restoreTabs
                update()
            }
        }
        // exiting is async and non-trivial for Brave, not currently handled here
    }

    func switchToTabForURLOrOpen(_ url: URL, isPrivate: Bool = false) {
        let tab = tabManager.getTabForURL(url)
        popToBrowser(tab)
        if let tab = tab {
            tabManager.selectTab(tab)
        } else {
            openURLInNewTab(url)
        }
    }

    func openURLInNewTab(_ url: URL?) {
        if let selectedTab = tabManager.selectedTab {
            screenshotHelper.takeScreenshot(selectedTab)
        }

        var request: URLRequest? = nil
        if let url = url {
            request = URLRequest(url: url)
        }
        
        // Cannot leave PM via this, only enter
        if PrivateBrowsing.singleton.isOn {
            switchBrowsingMode(toPrivate: true)
        }
        
        tabManager.addAdjacentTabAndSelect(request)
    }

    func openBlankNewTabAndFocus(isPrivate: Bool = false) {
        popToBrowser()
        tabManager.selectTab(nil)
        openURLInNewTab(nil)
    }

    fileprivate func popToBrowser(_ forTab: Browser? = nil) {
        guard let currentViewController = navigationController?.topViewController else {
                return
        }
        if let presentedViewController = currentViewController.presentedViewController {
            presentedViewController.dismiss(animated: false, completion: nil)
        }
        // if a tab already exists and the top VC is not the BVC then pop the top VC, otherwise don't.
        if currentViewController != self,
            let _ = forTab {
            self.navigationController?.popViewController(animated: true)
        }
    }

    var helper:ShareExtensionHelper!
    
    func presentActivityViewController(_ url: URL, tab: Browser?, sourceView: UIView?, sourceRect: CGRect, arrowDirection: UIPopoverArrowDirection) {
        var activities = [UIActivity]()
        
        let findInPageActivity = FindInPageActivity() { [unowned self] in
            self.updateFindInPageVisibility(true)
        }
        activities.append(findInPageActivity)
        
        //if let tab = tab where (tab.getHelper(name: ReaderMode.name()) as? ReaderMode)?.state != .Active { // needed for reader mode?
        let requestDesktopSiteActivity = RequestDesktopSiteActivity() { [weak tab] in
            if let url = tab?.url {
                (getApp().browserViewController as! BraveBrowserViewController).newTabForDesktopSite(url)
            }
            //tab?.toggleDesktopSite()
        }
        activities.append(requestDesktopSiteActivity)

        helper = ShareExtensionHelper(url: url, tab: tab, activities: activities)
        let controller = helper.createActivityViewController() {
            [weak self] completed in
            self?.handleActivityViewDismiss(with: completed, using: tab)
        }

        presentActivityViewController(controller: controller,
                                      tab: tab,
                                      sourceView: sourceView,
                                      sourceRect: sourceRect,
                                      arrowDirection: arrowDirection)
    }

    private func handleActivityViewDismiss(with success: Bool, using tab: Browser?) {
        // After dismissing, check to see if there were any prompts we queued up
        showQueuedAlertIfAvailable()
        
        // Usually the popover delegate would handle nil'ing out the references we have to it
        // on the BVC when displaying as a popover but the delegate method doesn't seem to be
        // invoked on iOS 10. See Bug 1297768 for additional details.
        displayedPopoverController = nil
        updateDisplayedPopoverProperties = nil
        helper = nil
        
        if success {
            // We don't know what share action the user has chosen so we simply always
            // update the toolbar and reader mode bar to reflect the latest status.
            updateURLBarDisplayURL(tab: tab)
        }
    }
    
    func presentActivityViewController(controller: UIActivityViewController,
                                       tab: Browser?,
                                       sourceView: UIView?,
                                       sourceRect: CGRect,
                                       arrowDirection: UIPopoverArrowDirection) {
        if controller.completionWithItemsHandler == nil {
            controller.completionWithItemsHandler = {
                [weak self] _, completed, _, _ in
                self?.handleActivityViewDismiss(with: completed, using: tab)
            }
        }
        let setupPopover = { [unowned self] in
            if let popoverPresentationController = controller.popoverPresentationController {
                popoverPresentationController.sourceView = sourceView
                popoverPresentationController.sourceRect = sourceRect
                popoverPresentationController.permittedArrowDirections = arrowDirection
                popoverPresentationController.delegate = self
            }
        }
        
        setupPopover()
        
        if controller.popoverPresentationController != nil {
            displayedPopoverController = controller
            updateDisplayedPopoverProperties = setupPopover
        }
        
        self.present(controller, animated: true, completion: nil)
    }
    
    func updateFindInPageVisibility(_ visible: Bool) {
        if visible {
            if findInPageBar == nil {
                let findInPageBar = FindInPageBar()
                self.findInPageBar = findInPageBar
                findInPageBar.delegate = self
                findInPageContainer.addSubview(findInPageBar)

                findInPageBar.snp.makeConstraints { make in
                    make.edges.equalTo(findInPageContainer)
                    make.height.equalTo(UIConstants.ToolbarHeight)
                }

                updateViewConstraints()

                // We make the find-in-page bar the first responder below, causing the keyboard delegates
                // to fire. This, in turn, will animate the Find in Page container since we use the same
                // delegate to slide the bar up and down with the keyboard. We don't want to animate the
                // constraints added above, however, so force a layout now to prevent these constraints
                // from being lumped in with the keyboard animation.
                findInPageBar.layoutIfNeeded()
            }

            // Workaround for #1297.
            // We need to set this flag so `keyboardWillShow` notication won't show password manager button when not needed
            showKeyboardFromFindInPage = true
            self.findInPageBar?.becomeFirstResponder()
        } else if let findInPageBar = self.findInPageBar {
            findInPageBar.endEditing(true)
            guard let webView = tabManager.selectedTab?.webView else { return }
            webView.evaluateJavaScript("__firefox__.findDone()", completionHandler: nil)
            findInPageBar.removeFromSuperview()
            self.findInPageBar = nil
            updateViewConstraints()
        }
    }
    
    /// There is only one case when search bar needs additional bottom inset:
    /// iPhoneX horizontal with keyboard hidden.
    fileprivate func adjustFindInPageBar(safeArea: Bool) {
        if #available(iOS 11, *), DeviceDetector.iPhoneX, let bar = findInPageBar {
            bar.snp.updateConstraints { make in
                if safeArea && BraveApp.isIPhoneLandscape() {
                    make.bottom.equalTo(findInPageContainer).inset(self.view.safeAreaInsets.bottom)
                } else {
                    make.bottom.equalTo(findInPageContainer)
                }
            }
        }
    }

    override var canBecomeFirstResponder : Bool {
        return true
    }

//    override func becomeFirstResponder() -> Bool {
//        // Make the web view the first responder so that it can show the selection menu.
//        return tabManager.selectedTab?.webView?.becomeFirstResponder() ?? false
//    }
}

/**
 * History visit management.
 * TODO: this should be expanded to track various visit types; see Bug 1166084.
 */
extension BrowserViewController {
    func ignoreNavigationInTab(_ tab: Browser, navigation: WKNavigation) {
        self.ignoredNavigation.insert(navigation)
    }

    func recordNavigationInTab(_ tab: Browser, navigation: WKNavigation) {
        //self.typedNavigation[navigation] = visitType
    }
}

extension BrowserViewController: WindowCloseHelperDelegate {
    func windowCloseHelper(_ helper: WindowCloseHelper, didRequestToCloseBrowser browser: Browser) {
        tabManager.removeTab(browser, createTabIfNoneLeft: true)
    }
}


extension BrowserViewController: HomePanelViewControllerDelegate {
    func homePanelViewController(_ homePanelViewController: HomePanelViewController, didSelectURL url: URL) {
        hideHomePanelController()
        finishEditingAndSubmit(url)
    }

    func homePanelViewController(_ homePanelViewController: HomePanelViewController, didSelectPanel panel: Int) {
        if AboutUtils.isAboutHomeURL(tabManager.selectedTab?.url) {
            tabManager.selectedTab?.webView?.evaluateJavaScript("history.replaceState({}, '', '#panel=\(panel)')", completionHandler: nil)
        }
    }
}

extension BrowserViewController: SearchViewControllerDelegate {
    func searchViewController(_ searchViewController: SearchViewController, didSelectURL url: URL) {
        finishEditingAndSubmit(url)
    }

    func presentSearchSettingsController() {
        let settingsNavigationController = SearchSettingsTableViewController()
        settingsNavigationController.model = self.profile.searchEngines

        let navController = UINavigationController(rootViewController: settingsNavigationController)

        self.present(navController, animated: true, completion: nil)
    }
    
    func searchViewController(_ searchViewController: SearchViewController, shouldFindInPage query: String) {
        cancelSearch()
        updateFindInPageVisibility(true)
        findInPageBar?.text = query
    }
    
    func searchViewControllerAllowFindInPage() -> Bool {
        // Hides find in page for new tabs.
        if let st = tabManager.selectedTab, let wv = st.webView {
            if AboutUtils.isAboutHomeURL(wv.URL) == false {
                return true
            }
        }
        return false
    }
}

extension BrowserViewController: ReaderModeDelegate {
    func readerMode(_ readerMode: ReaderMode, didChangeReaderModeState state: ReaderModeState, forBrowser browser: Browser) {
        // If this reader mode availability state change is for the tab that we currently show, then update
        // the button. Otherwise do nothing and the button will be updated when the tab is made active.
        if tabManager.selectedTab === browser {
            urlBar.updateReaderModeState(state)
        }
    }

    func readerMode(_ readerMode: ReaderMode, didDisplayReaderizedContentForBrowser browser: Browser) {
        browser.showContent(true)
    }

    // Returning None here makes sure that the Popover is actually presented as a Popover and
    // not as a full-screen modal, which is the default on compact device classes.
    func adaptivePresentationStyle(for controller: UIPresentationController, traitCollection: UITraitCollection) -> UIModalPresentationStyle {
        return UIModalPresentationStyle.none
    }
}

// MARK: - UIPopoverPresentationControllerDelegate

extension BrowserViewController: UIPopoverPresentationControllerDelegate {
    func popoverPresentationControllerDidDismissPopover(_ popoverPresentationController: UIPopoverPresentationController) {
        displayedPopoverController = nil
        updateDisplayedPopoverProperties = nil
    }
}

extension BrowserViewController: IntroViewControllerDelegate {
    @discardableResult func presentIntroViewController(_ force: Bool = false) -> Bool {
        struct autoShowOnlyOnce { static var wasShownThisSession = false } // https://github.com/brave/browser-ios/issues/424
        if force || (profile.prefs.intForKey(IntroViewControllerSeenProfileKey) == nil && !autoShowOnlyOnce.wasShownThisSession) {
            autoShowOnlyOnce.wasShownThisSession = true
            let introViewController = IntroViewController()
            introViewController.delegate = self
            // On iPad we present it modally in a controller
            if UIDevice.current.userInterfaceIdiom == .pad {
                introViewController.preferredContentSize = CGSize(width: IntroViewControllerUX.Width, height: IntroViewControllerUX.Height)
                introViewController.modalPresentationStyle = UIModalPresentationStyle.formSheet
            }
            present(introViewController, animated: true) {}

            return true
        }

        return false
    }

    func introViewControllerDidFinish(_ introViewController: IntroViewController) {
        introViewController.dismiss(animated: true) { finished in
            if self.navigationController?.viewControllers.count ?? 0 > 1 {
                self.navigationController?.popToRootViewController(animated: true)
            }
        }
    }
}

extension BrowserViewController: KeyboardHelperDelegate {
    func keyboardHelper(_ keyboardHelper: KeyboardHelper, keyboardWillShowWithState state: KeyboardState) {
        keyboardState = state
        updateViewConstraints()

        UIView.animate(withDuration: state.animationDuration) {
            UIView.setAnimationCurve(state.animationCurve)
            self.findInPageContainer.layoutIfNeeded()
            self.snackBars.layoutIfNeeded()
        }

        adjustFindInPageBar(safeArea: false)

        if let loginsHelper = tabManager.selectedTab?.getHelper(LoginsHelper) {
            // keyboardWillShowWithState is called during a hide (brilliant), and because PW button setup is async make sure to exit here if already showing the button, or the show code will be called after kb hide
            if !urlBar.pwdMgrButton.isHidden || loginsHelper.getKeyboardAccessory() != nil {
                return
            }
            
            // Workaround for #1297. We don't want to check for password manager when find in page action is tapped.
            // Both use keyboard notification so there is no easy way to distinguish between the two.
            if showKeyboardFromFindInPage {
                showKeyboardFromFindInPage = false
                return
            }
            
            loginsHelper.passwordManagerButtonSetup({ (shouldShow) in
                if UIDevice.current.userInterfaceIdiom == .pad {
                    self.urlBar.pwdMgrButton.isHidden = !shouldShow
                    
                    let icon = ThirdPartyPasswordManagerType.icon(PasswordManagerButtonSetting.currentSetting)
                    self.urlBar.pwdMgrButton.setImage(icon, for: .normal)

                    self.urlBar.setNeedsUpdateConstraints()
                }
            })
        }
    }

    func keyboardHelper(_ keyboardHelper: KeyboardHelper, keyboardDidShowWithState state: KeyboardState) {
    }

    func keyboardHelper(_ keyboardHelper: KeyboardHelper, keyboardWillHideWithState state: KeyboardState) {
        keyboardState = nil
        updateViewConstraints()
        
        adjustFindInPageBar(safeArea: true)

        UIView.animate(withDuration: state.animationDuration) {
            UIView.setAnimationCurve(state.animationCurve)
            self.findInPageContainer.layoutIfNeeded()
            self.snackBars.layoutIfNeeded()
        }
        
        if let loginsHelper = tabManager.selectedTab?.getHelper(LoginsHelper) {
            loginsHelper.hideKeyboardAccessory()
            urlBar.pwdMgrButton.isHidden = true
            urlBar.setNeedsUpdateConstraints()
        }
    }
}

extension BrowserViewController: SessionRestoreHelperDelegate {
    func sessionRestoreHelper(_ helper: SessionRestoreHelper, didRestoreSessionForBrowser browser: Browser) {
        browser.restoring = false

        if let tab = tabManager.selectedTab, tab.webView === browser.webView {
            updateUIForReaderHomeStateForTab(tab)
        }
    }
}

extension BrowserViewController: TabTrayDelegate {
    // This function animates and resets the browser chrome transforms when
    // the tab tray dismisses.
    func tabTrayDidDismiss(_ tabTray: TabTrayController) {
        resetBrowserChrome()
    }

    func tabTrayDidAddBookmark(_ tab: Browser) {
        self.addBookmark(tab.url, title: tab.title)
    }


    func tabTrayDidAddToReadingList(_ tab: Browser) -> ReadingListClientRecord? {
        guard let url = tab.url?.absoluteString, url.characters.count > 0 else { return nil }
        return profile.readingList?.createRecordWithURL(url, title: tab.title ?? url, addedBy: UIDevice.current.name).successValue
    }

    func tabTrayRequestsPresentationOf(_ viewController: UIViewController) {
        self.present(viewController, animated: false, completion: nil)
    }
}

// MARK: Browser Chrome Theming
extension BrowserViewController: Themeable {

    func applyTheme(_ themeName: String) {
        urlBar.applyTheme(themeName)
        toolbar?.applyTheme(themeName)
        //readerModeBar?.applyTheme(themeName)

        // TODO: Check if blur is enabled
        // Should be added to theme, instead of handled here
        switch(themeName) {
        case Theme.NormalMode:
            statusBarOverlay.backgroundColor = BraveUX.ToolbarsBackgroundSolidColor
            footerBackground?.backgroundColor = BraveUX.ToolbarsBackgroundSolidColor
            footer?.backgroundColor = BraveUX.ToolbarsBackgroundSolidColor
        case Theme.PrivateMode:
            statusBarOverlay.backgroundColor = BraveUX.DarkToolbarsBackgroundSolidColor
            footerBackground?.backgroundColor = BraveUX.DarkToolbarsBackgroundSolidColor
            footer?.backgroundColor = BraveUX.DarkToolbarsBackgroundSolidColor
        default:
            log.debug("Unknown Theme \(themeName)")
        }
        
        self.currentThemeName = themeName
    }
}

// A small convienent class for wrapping a view with a blur background that can be modified
class BlurWrapper: UIView {
    var blurStyle: UIBlurEffectStyle = .extraLight {
        didSet {
            let newEffect = UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
            effectView.removeFromSuperview()
            effectView = newEffect
            insertSubview(effectView, belowSubview: wrappedView)
            effectView.snp.remakeConstraints { make in
                make.edges.equalTo(self)
            }
        }
    }

    var effectView: UIVisualEffectView
    fileprivate var wrappedView: UIView

    init(view: UIView) {
        wrappedView = view
        effectView = UIVisualEffectView(effect: UIBlurEffect(style: blurStyle))
        super.init(frame: CGRect.zero)

        addSubview(effectView)
        addSubview(wrappedView)

        effectView.snp.makeConstraints { make in
            make.edges.equalTo(self)
        }

        wrappedView.snp.makeConstraints { make in
            make.edges.equalTo(self)
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

protocol Themeable {
    func applyTheme(_ themeName: String)
}

extension BrowserViewController: JSPromptAlertControllerDelegate {
    func promptAlertControllerDidDismiss(_ alertController: JSPromptAlertController) {
        showQueuedAlertIfAvailable()
    }
}
