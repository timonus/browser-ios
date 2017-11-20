/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import Deferred

var kIsDevelomentBuild: Bool = {
    var isDev = false
    
    #if DEBUG || BETA
        isDev = true
    #endif
    
    return isDev
}()

#if !NO_FABRIC
    import Fabric
    import Crashlytics
    import Mixpanel
#endif

#if !DEBUG
    func print(_ items: Any..., separator: String = " ", terminator: String = "\n") {}
#endif

private let _singleton = BraveApp()

let kAppBootingIncompleteFlag = "kAppBootingIncompleteFlag"
let kDesktopUserAgent = "Mozilla/5.0 (Macintosh; U; Intel Mac OS X 10_12) AppleWebKit/603.3.8 (KHTML, like Gecko) Version/10.0 Safari/602.1.31"

#if !TEST
    func getApp() -> AppDelegate {
//        assertIsMainThread("App Delegate must be accessed on main thread")
        return UIApplication.shared.delegate as! AppDelegate
    }
#endif

extension URL {
    // The url is a local webserver url or an about url, a.k.a something we don't display to users
    public func isSpecialInternalUrl() -> Bool {
        assert(WebServer.sharedInstance.base.startsWith("http"))
        return absoluteString.startsWith(WebServer.sharedInstance.base) || AboutUtils.isAboutURL(self)
    }
}

// Any app-level hooks we need from Firefox, just add a call to here
class BraveApp {
    static var isSafeToRestoreTabs = true
    // If app runs for this long, clear the saved pref that indicates it is safe to restore tabs
    static let kDelayBeforeDecidingAppHasBootedOk = (Int64(NSEC_PER_SEC) * 10) // 10 sec

    class var singleton: BraveApp {
        return _singleton
    }

    #if !TEST
    class func getCurrentWebView() -> BraveWebView? {
        return getApp().browserViewController.tabManager.selectedTab?.webView
    }
    #endif

    fileprivate init() {
    }

    class func isIPhoneLandscape() -> Bool {
        return UIDevice.current.userInterfaceIdiom == .phone &&
            UIInterfaceOrientationIsLandscape(UIApplication.shared.statusBarOrientation)
    }

    class func isIPhonePortrait() -> Bool {
        return UIDevice.current.userInterfaceIdiom == .phone &&
            UIInterfaceOrientationIsPortrait(UIApplication.shared.statusBarOrientation)
    }
    
    class func isIPhoneX() -> Bool {
        if #available(iOS 11.0, *) {
            if isIPhonePortrait() && getApp().window!.safeAreaInsets.top > 0 {
                return true
            } else if isIPhoneLandscape() && (getApp().window!.safeAreaInsets.left > 0 || getApp().window!.safeAreaInsets.right > 0) {
                return true
            }
        }
        
        return false
    }

    class func setupCacheDefaults() {
        URLCache.shared.memoryCapacity = 6 * 1024 * 1024; // 6 MB
        URLCache.shared.diskCapacity = 40 * 1024 * 1024;
    }

    class func didFinishLaunching() {
        #if !NO_FABRIC
            let telemetryOn = getApp().profile!.prefs.intForKey(BraveUX.PrefKeyUserAllowsTelemetry) ?? 1 == 1
            if telemetryOn {
                Fabric.with([Crashlytics.self])

                if let dict = Bundle.main.infoDictionary, let token = dict["MIXPANEL_TOKEN"] as? String {
                    // note: setting this in willFinishLaunching is causing a crash, keep it in didFinish
                    mixpanelInstance = Mixpanel.initialize(token: token)
                    mixpanelInstance?.serverURL = "https://metric-proxy.brave.com"
                    checkMixpanelGUID()
                    
                    // Eventually GCDWebServer `base` could be used with monitoring outgoing posts to /track endpoint
                    //  this would allow data to be swapped out in realtime without the need for a full Mixpanel fork
                }
            }
       #endif
        
        UINavigationBar.appearance().tintColor = BraveUX.DefaultBlue
    }
    
    private class func checkMixpanelGUID() {
        let calendar = NSCalendar(calendarIdentifier: NSCalendar.Identifier.gregorian)
        let unit: NSCalendar.Unit = [NSCalendar.Unit.month, NSCalendar.Unit.year]
        guard let dateComps = calendar?.components(unit, from: Date()), let month = dateComps.month, let year = dateComps.year else {
            print("Failed to pull date components for GUID rotation")
            return
        }
        
        // We only rotate on 'odd' months
        let rotationMonth = Int(round(Double(month) / 2.0) * 2 - 1)
        
        // The key for the last reset date
        let resetDate = "\(rotationMonth)-\(year)"
        
        let mixpanelGuidKey = "kMixpanelGuid"
        let lastResetDate = getApp().profile!.prefs.stringForKey(mixpanelGuidKey)
        
        if lastResetDate != resetDate {
            // We have not rotated for this iteration (do not care _how_ far off it is, just that it is not the same)
            mixpanelInstance?.distinctId = UUID().uuidString
            getApp().profile?.prefs.setString(resetDate, forKey: mixpanelGuidKey)
        }
        
    }

    // Be aware: the Prefs object has not been created yet
    class func willFinishLaunching_begin() {
        BraveApp.setupCacheDefaults()
        Foundation.URLProtocol.registerClass(URLProtocol);

        NotificationCenter.default.addObserver(BraveApp.singleton,
             selector: #selector(BraveApp.didEnterBackground(_:)), name: NSNotification.Name.UIApplicationDidEnterBackground, object: nil)

        NotificationCenter.default.addObserver(BraveApp.singleton,
             selector: #selector(BraveApp.willEnterForeground(_:)), name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)

        NotificationCenter.default.addObserver(BraveApp.singleton,
             selector: #selector(BraveApp.memoryWarning(_:)), name: NSNotification.Name.UIApplicationDidReceiveMemoryWarning, object: nil)

        #if !TEST
            //  these quiet the logging from the core of fx ios
            // GCDWebServer.setLogLevel(5)
            Logger.syncLogger.setup(level: .none)
            Logger.browserLogger.setup(level: .none)
        #endif

        #if DEBUG
            // desktop UA for testing
            //      let defaults = NSUserDefaults(suiteName: AppInfo.sharedContainerIdentifier())!
            //      defaults.registerDefaults(["UserAgent": kDesktopUserAgent])

        #endif
    }

    // Prefs are created at this point
    class func willFinishLaunching_end() {
        BraveApp.isSafeToRestoreTabs = BraveApp.getPrefs()?.stringForKey(kAppBootingIncompleteFlag) == nil
        BraveApp.getPrefs()?.setString("remove me when booted", forKey: kAppBootingIncompleteFlag)

        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(BraveApp.kDelayBeforeDecidingAppHasBootedOk) / Double(NSEC_PER_SEC), execute: {
                        BraveApp.getPrefs()?.removeObjectForKey(kAppBootingIncompleteFlag)
        })


        let args = ProcessInfo.processInfo.arguments
        if args.contains("BRAVE-TEST-CLEAR-PREFS") {
            BraveApp.getPrefs()!.clearAll()
        }
        if args.contains("BRAVE-TEST-NO-SHOW-INTRO") {
            BraveApp.getPrefs()!.setInt(1, forKey: IntroViewControllerSeenProfileKey)
        }
        if args.contains("BRAVE-TEST-SHOW-OPT-IN") {
            BraveApp.getPrefs()!.removeObjectForKey(BraveUX.PrefKeyOptInDialogWasSeen)
        }
        
        // Be careful, running it in production will result in destroying all bookmarks
        if args.contains("BRAVE-DELETE-BOOKMARKS") {
            Bookmark.removeAll()
        }
        if args.contains("BRAVE-UI-TEST") || AppConstants.IsRunningTest {
            // Maybe we will need a specific flag to keep tabs for restoration testing
            BraveApp.isSafeToRestoreTabs = false
            
            if args.filter({ $0.startsWith("BRAVE") }).count == 1 || AppConstants.IsRunningTest { // only contains 1 arg
                BraveApp.getPrefs()!.setInt(1, forKey: IntroViewControllerSeenProfileKey)
                BraveApp.getPrefs()!.setInt(1, forKey: BraveUX.PrefKeyOptInDialogWasSeen)
            }
        }

        if args.contains("LOCALE=RU") {
            AdBlocker.singleton.currentLocaleCode = "ru"
        }

        AdBlocker.singleton.startLoading()
        SafeBrowsing.singleton.networkFileLoader.loadData()
        TrackingProtection.singleton.networkFileLoader.loadData()
        HttpsEverywhere.singleton.networkFileLoader.loadData()

        #if !TEST
            PrivateBrowsing.singleton.startupCheckIfKilledWhileInPBMode()
            CookieSetting.setupOnAppStart()
            PasswordManagerButtonSetting.setupOnAppStart()
            //BlankTargetLinkHandler.updatedEnabledState()
        #endif

        Domain.loadShieldsIntoMemory {
            guard let shieldState = getApp().tabManager.selectedTab?.braveShieldStateSafeAsync.get() else { return }
            if let wv = getCurrentWebView(), let url = wv.URL?.normalizedHost, let dbState = BraveShieldState.perNormalizedDomain[url], shieldState.isNotSet() {
                // on init, the webview's shield state doesn't match the db
                getApp().tabManager.selectedTab?.braveShieldStateSafeAsync.set(dbState)
                wv.reloadFromOrigin()
            }
        }
    }

    // This can only be checked ONCE, the flag is cleared after this.
    // This is because BrowserViewController asks this question after the startup phase,
    // when tabs are being created by user actions. So without more refactoring of the
    // Firefox logic, this is the simplest solution.
    class func shouldRestoreTabs() -> Bool {
        let ok = BraveApp.isSafeToRestoreTabs
        BraveApp.isSafeToRestoreTabs = false
        return ok
    }

    @objc func memoryWarning(_: Notification) {
        URLCache.shared.memoryCapacity = 0
        BraveApp.setupCacheDefaults()
    }

    @objc func didEnterBackground(_: Notification) {
    }

    @objc func willEnterForeground(_ : Notification) {
    }

    class func shouldHandleOpenURL(_ components: URLComponents) -> Bool {
        // TODO look at what x-callback is for
        let handled = components.scheme == "brave" || components.scheme == "brave-x-callback"
        return handled
    }

    class func getPrefs() -> NSUserDefaultsPrefs? {
        return getApp().profile?.prefs
    }

    static func showErrorAlert(title: String,  error: String) {
        postAsyncToMain(0) { // this utility function can be called from anywhere
            UIAlertView(title: title, message: error, delegate: nil, cancelButtonTitle: "Close").show()
        }
    }

    static func statusBarHeight() -> CGFloat {
        if UIScreen.main.traitCollection.verticalSizeClass == .compact {
            return 0
        }
        return 20
    }

    static var isPasswordManagerInstalled: Bool?

    static func is3rdPartyPasswordManagerInstalled(_ refreshLookup: Bool) -> Deferred<Bool> {
        let deferred = Deferred<Bool>()
        if refreshLookup || isPasswordManagerInstalled == nil {
            postAsyncToMain {
                isPasswordManagerInstalled = OnePasswordExtension.shared().isAppExtensionAvailable()
                deferred.fill(isPasswordManagerInstalled!)
            }
        } else {
            deferred.fill(isPasswordManagerInstalled!)
        }
        return deferred
    }
}

extension BraveApp {

    static func updateDauStat() {

        guard let prefs = getApp().profile?.prefs else { return }
        let prefName = "dau_stat"
        let dauStat = prefs.arrayForKey(prefName)

        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        var statsQuery = "https://laptop-updates.brave.com/1/usage/ios?platform=ios" + "&channel=\(BraveUX.IsRelease ? "stable" : "beta")"
            + "&version=\(appVersion)"
            + "&first=\(dauStat != nil)"

        let today = Date()
        let components = (Calendar.current as NSCalendar).components([.month , .year], from: today)
        let year =  components.year
        let month = components.month

        if let stat = dauStat as? [Int], stat.count == 3 {
            let dSecs = Int(today.timeIntervalSince1970) - stat[0]
            let _month = stat[1]
            let _year = stat[2]
            let SECONDS_IN_A_DAY = 86400
            let SECONDS_IN_A_WEEK = 7 * 86400
            let daily = dSecs >= SECONDS_IN_A_DAY
            let weekly = dSecs >= SECONDS_IN_A_WEEK
            let monthly = month != _month || year != _year
            print(daily, weekly, monthly, dSecs)
            if (!daily && !weekly && !monthly) {
                // No changes, so no server ping
                return
            }
            statsQuery += "&daily=\(daily)&weekly=\(weekly)&monthly=\(monthly)"
        }

        let secsMonthYear = [Int(today.timeIntervalSince1970), month, year]
        prefs.setObject(secsMonthYear, forKey: prefName)

        guard let url = URL(string: statsQuery) else {
            if !BraveUX.IsRelease {
                BraveApp.showErrorAlert(title: "Debug", error: "failed stats update")
            }
            return
        }
        let task = URLSession.shared.dataTask(with: url) {
            (_, _, error) in
            if let e = error { NSLog("status update error: \(e)") }
        }
        task.resume()
    }
}


