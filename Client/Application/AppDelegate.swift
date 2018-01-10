/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared
import Storage
import AVFoundation
import XCGLogger
import MessageUI
import WebImage
import SwiftKeychainWrapper
import LocalAuthentication

private let log = Logger.browserLogger

let LatestAppVersionProfileKey = "latestAppVersion"
let AllowThirdPartyKeyboardsKey = "settings.allowThirdPartyKeyboards"

class AppDelegate: UIResponder, UIApplicationDelegate, UIViewControllerRestoration {
    
    public static func viewController(withRestorationIdentifierPath identifierComponents: [Any], coder: NSCoder) -> UIViewController? {
        return nil
    }
    
    // TODO: Having all of these global opens up lots of abuse potential (open via getApp())
    
    
    private var launchTimer: Timer?
    
    var window: UIWindow?
    var securityWindow: UIWindow?
    var securityViewController: PinProtectOverlayViewController?
    var browserViewController: BrowserViewController!
    var rootViewController: UINavigationController!
    weak var profile: BrowserProfile?
    var tabManager: TabManager!
    var braveTopViewController: BraveTopViewController!

    weak var application: UIApplication?
    var launchOptions: [AnyHashable: Any]?

    let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String

    var openInBraveParams: LaunchParams? = nil

    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {

        BraveApp.willFinishLaunching_begin()

        // Hold references to willFinishLaunching parameters for delayed app launch
        self.application = application
        self.launchOptions = launchOptions

        log.debug("Configuring window…")

        self.window = BraveMainWindow(frame: UIScreen.main.bounds)
        self.window!.backgroundColor = UIConstants.AppBackgroundColor

        // Short circuit the app if we want to email logs from the debug menu
        if DebugSettingsBundleOptions.launchIntoEmailComposer {
            self.window?.rootViewController = UIViewController()
            presentEmailComposerWithLogs()
            return true
        } else {
            return startApplication(application, withLaunchOptions: launchOptions)
        }
    }

    // Swift Selectors hate class method on extensions, this just wraps the behavior
    // Also, must be public
    func updateDauStatWrapper() {
        guard let prefs = profile?.prefs else {
            log.warning("Couldn't find profile, unable to send dau stats!")
            return
        }
        
        let dau = DAU(prefs: prefs)
        dau.sendPingToServer()
    }

    private func isFirstLaunch() -> Bool{
        guard let prefs = profile?.prefs else {
            log.warning("Couldn't find profile to check for first launch")
            return false
        }

        // Reusing dau logic for first launch check to avoid introducing another 'firstLaunch' flag
        return prefs.arrayForKey(DAU.preferencesKey) == nil
    }
    
    fileprivate func startApplication(_ application: UIApplication,  withLaunchOptions launchOptions: [AnyHashable: Any]?) -> Bool {
        log.debug("Setting UA…")
        
        // Ping server for stats
        
        // Sets up X second timer to represent an active user
        self.launchTimer = Timer.scheduledTimer(timeInterval: 1.0, target: self, selector: #selector(self.updateDauStatWrapper), userInfo: nil, repeats: false)

        setUserAgents()

        log.debug("Starting keyboard helper…")
        // Start the keyboard helper to monitor and cache keyboard state.
        KeyboardHelper.defaultHelper.startObserving()

        log.debug("Starting dynamic font helper…")
        // Start the keyboard helper to monitor and cache keyboard state.
        DynamicFontHelper.defaultHelper.startObserving()

        log.debug("Setting custom menu items…")
        MenuHelper.defaultHelper.setItems()

        log.debug("Creating Sync log file…")
        let logDate = Date()
        // Create a new sync log file on cold app launch. Note that this doesn't roll old logs.
        Logger.syncLogger.newLogWithDate(logDate)

        log.debug("Creating corrupt DB logger…")
        Logger.corruptLogger.newLogWithDate(logDate)

        log.debug("Creating Browser log file…")
        Logger.browserLogger.newLogWithDate(logDate)
        log.debug("Getting profile…")
        let profile = getProfile(application)

        if !DebugSettingsBundleOptions.disableLocalWebServer {
            log.debug("Starting web server…")
            // Set up a web server that serves us static content. Do this early so that it is ready when the UI is presented.
            setUpWebServer(profile)
        }

        log.debug("Setting AVAudioSession category…")
        do {
            // for aural progress bar: play even with silent switch on, and do not stop audio from other apps (like music)
            try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayback, with: AVAudioSessionCategoryOptions.mixWithOthers)
        } catch _ {
            log.error("Failed to assign AVAudioSession category to allow playing with silent switch on for aural progress bar")
        }

        Bookmark.favoritesInit()

        let defaultRequest = URLRequest(url: UIConstants.DefaultHomePage as URL)
        let imageStore = DiskImageStore(files: profile.files, namespace: "TabManagerScreenshots", quality: UIConstants.ScreenshotQuality)

        log.debug("Configuring tabManager…")
        self.tabManager = TabManager(defaultNewTabRequest: defaultRequest, prefs: profile.prefs, imageStore: imageStore)
        self.tabManager.stateDelegate = self

        browserViewController = BraveBrowserViewController(profile: profile, tabManager: self.tabManager)
        browserViewController.restorationIdentifier = NSStringFromClass(BrowserViewController.self)
        browserViewController.restorationClass = AppDelegate.self
        browserViewController.automaticallyAdjustsScrollViewInsets = false

        braveTopViewController = BraveTopViewController(browserViewController: browserViewController as! BraveBrowserViewController)

        rootViewController = UINavigationController(rootViewController: braveTopViewController)
        rootViewController.automaticallyAdjustsScrollViewInsets = false
        rootViewController.delegate = self
        rootViewController.isNavigationBarHidden = true
        self.window!.rootViewController = rootViewController
        
        // TODO: Show activity indicator instead of launching app.
        _ = MigrateData(completed: { (success) in
            if success {
                // TODO: Remove activity indicator.
            }
        })

        log.debug("Adding observers…")
        NotificationCenter.default.addObserver(forName: NSNotification.Name.FSReadingListAddReadingListItem, object: nil, queue: nil) { (notification) -> Void in
            if let userInfo = notification.userInfo, let url = userInfo["URL"] as? URL {
                let title = (userInfo["Title"] as? String) ?? ""
                profile.readingList?.createRecordWithURL(url.absoluteString, title: title, addedBy: UIDevice.current.name)
            }
        }

        // check to see if we started 'cos someone tapped on a notification.
        if let localNotification = launchOptions?[UIApplicationLaunchOptionsKey.localNotification] as? UILocalNotification {
            viewURLInNewTab(localNotification)
        }

        // We need to check if the app is a clean install to use for
        // preventing the What's New URL from appearing.
        if getProfile(application).prefs.intForKey(IntroViewControllerSeenProfileKey) == nil {
            getProfile(application).prefs.setString(AppInfo.appVersion, forKey: LatestAppVersionProfileKey)
        }

        log.debug("Updating authentication keychain state to reflect system state")
        self.updateAuthenticationInfo()
        SystemUtils.onFirstRun()
        
        log.debug("Done with setting up the application.")

        BraveApp.willFinishLaunching_end()
        return true
    }

    func applicationWillTerminate(_ application: UIApplication) {
        log.debug("Application will terminate.")
        
        var task: UIBackgroundTaskIdentifier = UIBackgroundTaskIdentifier()
        task = UIApplication.shared.beginBackgroundTask(withName: "deactivateQueue", expirationHandler: { () -> Void in
            UIApplication.shared.endBackgroundTask(task)
            task = UIBackgroundTaskInvalid
        })
        
        DispatchQueue.global(qos: .background).async {
            TabMO.clearAllPrivate()
            
            self.shutdownProfileWhenNotActive()
            BraveGlobalShieldStats.singleton.save()
            
            // Allow deinitializers to close our database connections.
            self.profile = nil
            self.tabManager = nil
            self.browserViewController = nil
            self.rootViewController = nil
            
            log.debug("Background cleanup completed.")
            task = UIBackgroundTaskInvalid
        }
    }

    /**
     * We maintain a weak reference to the profile so that we can pause timed
     * syncs when we're backgrounded.
     *
     * The long-lasting ref to the profile lives in BrowserViewController,
     * which we set in application:willFinishLaunchingWithOptions:.
     *
     * If that ever disappears, we won't be able to grab the profile to stop
     * syncing... but in that case the profile's deinit will take care of things.
     */
    func getProfile(_ application: UIApplication) -> Profile {
        if let profile = self.profile {
            return profile
        }
        let p = BrowserProfile(localName: "profile", app: application)
        self.profile = p
        return p
    }
    
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        var shouldPerformAdditionalDelegateHandling = true

        log.debug("Did finish launching.")

        log.debug("Making window key and visible…")
        self.window!.makeKeyAndVisible()

        // Now roll logs.
        log.debug("Triggering log roll.")
        DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.background).async {
            Logger.syncLogger.deleteOldLogsDownToSizeLimit()
            Logger.browserLogger.deleteOldLogsDownToSizeLimit()
        }

        // If a shortcut was launched, display its information and take the appropriate action
        if let shortcutItem = launchOptions?[UIApplicationLaunchOptionsKey.shortcutItem] as? UIApplicationShortcutItem {

            QuickActions.sharedInstance.launchedShortcutItem = shortcutItem
            // This will block "performActionForShortcutItem:completionHandler" from being called.
            shouldPerformAdditionalDelegateHandling = false
        }

        log.debug("Done with applicationDidFinishLaunching.")

        BraveApp.didFinishLaunching()
        
        let appProfile = getProfile(application)
        requirePinIfNeeded(profile: appProfile)
        
        return shouldPerformAdditionalDelegateHandling
    }

    func application(_ application: UIApplication, open url: URL, sourceApplication: String?, annotation: Any) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }

        if !BraveApp.shouldHandleOpenURL(components) { return false }

        var url: String?
        var isPrivate: Bool = false
        for item in (components.queryItems ?? []) as [URLQueryItem] {
            switch item.name {
            case "url":
                url = item.value
            case "private":
                isPrivate = NSString(string: item.value ?? "false").boolValue
            default: ()
            }
        }

        let params: LaunchParams

        if let url = url, let newURL = URL(string: url.unescape()) {
            params = LaunchParams(url: newURL, isPrivate: isPrivate)
        } else {
            params = LaunchParams(url: nil, isPrivate: isPrivate)
        }

        if application.applicationState == .active {
            // If we are active then we can ask the BVC to open the new tab right away. 
            // Otherwise, we remember the URL and we open it in applicationDidBecomeActive.
            launchFromURL(params)
        } else {
            openInBraveParams = params
        }

        return true
    }

    func launchFromURL(_ params: LaunchParams) {
        let isPrivate = params.isPrivate ?? false
        if let newURL = params.url {
            self.browserViewController.switchToTabForURLOrOpen(newURL, isPrivate: isPrivate)
        } else {
            self.browserViewController.openBlankNewTabAndFocus(isPrivate: isPrivate)
        }
    }

    func application(_ application: UIApplication, shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplicationExtensionPointIdentifier) -> Bool {
        if let thirdPartyKeyboardSettingBool = getProfile(application).prefs.boolForKey(AllowThirdPartyKeyboardsKey), extensionPointIdentifier == UIApplicationExtensionPointIdentifier.keyboard {
            return thirdPartyKeyboardSettingBool
        }

        return true
    }

    // We sync in the foreground only, to avoid the possibility of runaway resource usage.
    // Eventually we'll sync in response to notifications.
    func applicationDidBecomeActive(_ application: UIApplication) {
        guard !DebugSettingsBundleOptions.launchIntoEmailComposer else {
            return
        }

        blurOverlayBehavior(.show)

        // We could load these here, but then we have to futz with the tab counter
        // and making NSURLRequests.
        self.browserViewController.loadQueuedTabs()

        // handle quick actions is available
        let quickActions = QuickActions.sharedInstance
        if let shortcut = quickActions.launchedShortcutItem {
            // dispatch asynchronously so that BVC is all set up for handling new tabs
            // when we try and open them
            quickActions.handleShortCutItem(shortcut, withBrowserViewController: browserViewController)
            quickActions.launchedShortcutItem = nil
        }

        // we've removed the Last Tab option, so we should remove any quick actions that we already have that are last tabs
        // we do this after we've handled any quick actions that have been used to open the app so that we don't b0rk if
        // the user has opened the app for the first time after upgrade with a Last Tab quick action
        QuickActions.sharedInstance.removeDynamicApplicationShortcutItemOfType(ShortcutType.OpenLastTab, fromApplication: application)

        // Check if we have a URL from an external app or extension waiting to launch,
        // then launch it on the main thread.
        if let params = openInBraveParams {
            openInBraveParams = nil
            DispatchQueue.main.async {
                self.launchFromURL(params)
            }
        }
        
        let profile = getProfile(application)
        if profile.prefs.boolForKey(kPrefKeyBrowserLock) == true && securityWindow?.isHidden == false {
            securityViewController?.auth()
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        print("Close database")
        shutdownProfileWhenNotActive()
        BraveGlobalShieldStats.singleton.save()
    }

    func applicationWillResignActive(_ application: UIApplication) {
        BraveGlobalShieldStats.singleton.save()
        
        self.launchTimer?.invalidate()
        self.launchTimer = nil

        blurOverlayBehavior(.hide)
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // The reason we need to call this method here instead of `applicationDidBecomeActive`
        // is that this method is only invoked whenever the application is entering the foreground where as 
        // `applicationDidBecomeActive` will get called whenever the Touch ID authentication overlay disappears.
        self.updateAuthenticationInfo()

        
        profile?.reopen()
        
        let appProfile = getProfile(application)
        requirePinIfNeeded(profile: appProfile)
    }

    private enum BlurLayoutBehavior { case show, hide }

    /// Toggles blurry overview when app is not active.
    /// If browser lock is enabled app switcher screenshot is not leaked.
    private func blurOverlayBehavior(_ behavior: BlurLayoutBehavior) {
        guard let profile = profile, profile.prefs.boolForKey(kPrefKeyBrowserLock) == true else { return }

        switch behavior {
        case .show:
            UIView.animate(withDuration: 0.1, animations: { _ in
                self.blurryLayout.alpha = 0
            }, completion: { _ in
                self.blurryLayout.removeFromSuperview()
            })
        case .hide:
            window?.addSubview(blurryLayout)
            UIView.animate(withDuration: 0.1, animations: { _ in
                self.blurryLayout.alpha = 1
            })
        }
    }

    private lazy var blurryLayout: UIView = {
        let view = UIView(frame: UIScreen.main.bounds)

        let blur: UIVisualEffectView
        blur = UIVisualEffectView(effect: UIBlurEffect(style: .light))
        blur.frame = view.frame
        view.addSubview(blur)
        view.alpha = 0

        return view
    }()
    
    func requirePinIfNeeded(profile: Profile) {
        // Check for browserLock settings
        if profile.prefs.boolForKey(kPrefKeyBrowserLock) == true {
            if securityWindow != nil  {
                securityViewController?.start()
                // This could have been changed elsewhere, not the best approach.
                securityViewController?.successCallback = { (success) in
                    if success {
                        postAsyncToMain {
                            self.securityWindow?.isHidden = true
                        }
                    }
                }
                securityWindow?.isHidden = false
                return
            }
            
            let vc = PinProtectOverlayViewController()
            securityViewController = vc
            
            let pinOverlay = UIWindow(frame: UIScreen.main.bounds)
            pinOverlay.backgroundColor = UIColor(white: 0.9, alpha: 0.7)
            pinOverlay.windowLevel = UIWindowLevelAlert
            pinOverlay.rootViewController = vc
            securityWindow = pinOverlay
            pinOverlay.makeKeyAndVisible()
            
            vc.successCallback = { (success) in
                postAsyncToMain {
                    self.securityWindow?.isHidden = true
                }
            }
        }
    }

    fileprivate func updateAuthenticationInfo() {
        if let authInfo = KeychainWrapper.standard.authenticationInfo() {
            if !LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
                authInfo.useTouchID = false
                KeychainWrapper.standard.setAuthenticationInfo(authInfo)
            }
        }
    }

    fileprivate func setUpWebServer(_ profile: Profile) {
        let server = WebServer.sharedInstance
        ReaderModeHandlers.register(server, profile: profile)
        ErrorPageHelper.register(server, certStore: profile.certStore)
        AboutHomeHandler.register(server)
        AboutLicenseHandler.register(server)
        SessionRestoreHandler.register(server)
        // Bug 1223009 was an issue whereby CGDWebserver crashed when moving to a background task
        // catching and handling the error seemed to fix things, but we're not sure why.
        // Either way, not implicitly unwrapping a try is not a great way of doing things
        // so this is better anyway.
        do {
            try server.start()
        } catch let err as NSError {
            log.error("Unable to start WebServer \(err)")
        }
    }

    fileprivate func setUserAgents() {
        let firefoxUA = UserAgent.defaultUserAgent()

        // Set the UA for WKWebView (via defaults), the favicon fetcher, and the image loader.
        // This only needs to be done once per runtime. Note that we use defaults here that are
        // readable from extensions, so they can just use the cached identifier.
        let defaults = UserDefaults(suiteName: AppInfo.sharedContainerIdentifier)!
        defaults.register(defaults: ["UserAgent": firefoxUA])

        SDWebImageDownloader.shared().setValue(firefoxUA, forHTTPHeaderField: "User-Agent")

        // Record the user agent for use by search suggestion clients.
        SearchViewController.userAgent = firefoxUA

        // Some sites will only serve HTML that points to .ico files.
        // The FaviconFetcher is explicitly for getting high-res icons, so use the desktop user agent.
        FaviconFetcher.userAgent = UserAgent.desktopUserAgent()
    }

    func application(_ application: UIApplication, handleActionWithIdentifier identifier: String?, for notification: UILocalNotification, completionHandler: @escaping () -> Void) {
        if let actionId = identifier {
            if let action = SentTabAction(rawValue: actionId) {
                viewURLInNewTab(notification)
                switch(action) {
                case .Bookmark:
                    //addBookmark(notification)
                    break
                case .ReadingList:
                    addToReadingList(notification)
                    break
                default:
                    break
                }
            } else {
                print("ERROR: Unknown notification action received")
            }
        } else {
            print("ERROR: Unknown notification received")
        }
    }

    func application(_ application: UIApplication, didReceive notification: UILocalNotification) {
        viewURLInNewTab(notification)
    }

    fileprivate func presentEmailComposerWithLogs() {
        if let buildNumber = Bundle.main.object(forInfoDictionaryKey: String(kCFBundleVersionKey)) as? NSString {
            let mailComposeViewController = MFMailComposeViewController()
            mailComposeViewController.mailComposeDelegate = self
            mailComposeViewController.setSubject("Debug Info for iOS client version v\(appVersion) (\(buildNumber))")

            if DebugSettingsBundleOptions.attachLogsToDebugEmail {
                do {
                    let logNamesAndData = try Logger.diskLogFilenamesAndData()
                    logNamesAndData.forEach { nameAndData in
                        if let data = nameAndData.1 {
                            mailComposeViewController.addAttachmentData(data, mimeType: "text/plain", fileName: nameAndData.0)
                        }
                    }
                } catch _ {
                    print("Failed to retrieve logs from device")
                }
            }

            self.window?.rootViewController?.present(mailComposeViewController, animated: true, completion: nil)
        }
    }

    func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]?) -> Void) -> Bool {
        if let url = userActivity.webpageURL {
            browserViewController.switchToTabForURLOrOpen(url)
            return true
        }
        return false
    }

    fileprivate func viewURLInNewTab(_ notification: UILocalNotification) {
        if let alertURL = notification.userInfo?[TabSendURLKey] as? String {
            if let urlToOpen = URL(string: alertURL) {
                browserViewController.openURLInNewTab(urlToOpen)
            }
        }
    }


    fileprivate func addToReadingList(_ notification: UILocalNotification) {
        if let alertURL = notification.userInfo?[TabSendURLKey] as? String,
           let title = notification.userInfo?[TabSendTitleKey] as? String {
            if let urlToOpen = URL(string: alertURL) {
                NotificationCenter.default.post(name: NSNotification.Name.FSReadingListAddReadingListItem, object: self, userInfo: ["URL": urlToOpen, "Title": title])
            }
        }
    }

    func application(_ application: UIApplication, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
        let handledShortCutItem = QuickActions.sharedInstance.handleShortCutItem(shortcutItem, withBrowserViewController: browserViewController)

        completionHandler(handledShortCutItem)
    }

#if !BRAVE
  var activeCrashReporter: CrashReporter?
  func configureActiveCrashReporter(_ optedIn: Bool?) {
    if let reporter = activeCrashReporter {
      configureCrashReporter(reporter, optedIn: optedIn)
    }
  }
#endif

    fileprivate func shutdownProfileWhenNotActive() {
        // Only shutdown the profile if we are not in the foreground
        guard UIApplication.shared.applicationState != UIApplicationState.active else { return }
        profile?.shutdown()
    }

}

// MARK: - Root View Controller Animations
extension AppDelegate: UINavigationControllerDelegate {
#if !BRAVE
    func navigationController(_ navigationController: UINavigationController,
        animationControllerFor operation: UINavigationControllerOperation,
        from fromVC: UIViewController,
        to toVC: UIViewController) -> UIViewControllerAnimatedTransitioning? {
            if operation == UINavigationControllerOperation.push {
                return BrowserToTrayAnimator()
            } else if operation == UINavigationControllerOperation.pop {
                return TrayToBrowserAnimator()
            } else {
                return nil
            }
    }
#endif
}

extension AppDelegate: TabManagerStateDelegate {
    func tabManagerWillStoreTabs(_ tabs: [Browser]) {
        // It is possible that not all tabs have loaded yet, so we filter out tabs with a nil URL.
        let storedTabs: [RemoteTab] = tabs.flatMap( Browser.toTab )

        // Don't insert into the DB immediately. We tend to contend with more important
        // work like querying for top sites.
        let queue = DispatchQueue.global(priority: DispatchQueue.GlobalQueuePriority.background)
        queue.asyncAfter(deadline: DispatchTime.now() + Double(Int64(ProfileRemoteTabsSyncDelay * Double(NSEC_PER_MSEC))) / Double(NSEC_PER_SEC)) {
            self.profile?.storeTabs(storedTabs)
        }
    }
}

extension AppDelegate: MFMailComposeViewControllerDelegate {
    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        // Dismiss the view controller and start the app up
        controller.dismiss(animated: true, completion: nil)
        startApplication(application!, withLaunchOptions: self.launchOptions)
    }
}

struct LaunchParams {
    let url: URL?
    let isPrivate: Bool?
}
