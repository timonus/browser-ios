import Shared
import Deferred
import Crashlytics
import Shared

private let _singleton = PrivateBrowsing()

class PrivateBrowsing {
    class var singleton: PrivateBrowsing {
        return _singleton
    }

    fileprivate(set) var isOn = false {
        didSet {
            getApp().braveTopViewController.setNeedsStatusBarAppearanceUpdate()
        }
    }

    var nonprivateCookies = [HTTPCookie: Bool]()

    // On startup we are no longer in private mode, if there is a .public cookies file, it means app was killed in private mode, so restore the cookies file
    func startupCheckIfKilledWhileInPBMode() {
        webkitDirLocker(false)
        cookiesFileDiskOperation(.restore)
    }

    enum MoveCookies {
        case savePublicBackup
        case restore
        case deletePublicBackup
    }

    // GeolocationSites.plist cannot be blocked any other way than locking the filesystem so that webkit can't write it out
    // TODO: after unlocking, verify that sites from PB are not in the written out GeolocationSites.plist, based on manual testing this
    // doesn't seem to be the case, but more rigourous test cases are needed
    fileprivate func webkitDirLocker(_ lock: Bool) {
        let fm = FileManager.default
        let baseDir = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true)[0]
        let webkitDirs = [baseDir + "/WebKit", baseDir + "/Caches"]
        for dir in webkitDirs {
            do {
                try fm.setAttributes([FileAttributeKey.posixPermissions: (lock ? NSNumber(value: 0 as Int16) : NSNumber(value: 0o755 as Int16))], ofItemAtPath: dir)
            } catch {
                print(error)
            }
        }
    }

    fileprivate func cookiesFileDiskOperation( _ type: MoveCookies) {
        let fm = FileManager.default
        let baseDir = NSSearchPathForDirectoriesInDomains(.libraryDirectory, .userDomainMask, true)[0]
        let cookiesDir = baseDir + "/Cookies"
        let originSuffix = type == .savePublicBackup ? "cookies" : ".public"

        do {
            let contents = try fm.contentsOfDirectory(atPath: cookiesDir)
            for item in contents {
                if item.hasSuffix(originSuffix) {
                    if type == .deletePublicBackup {
                        try fm.removeItem(atPath: cookiesDir + "/" + item)
                    } else {
                        var toPath = cookiesDir + "/"
                        if type == .restore {
                            toPath += NSString(string: item).deletingPathExtension
                        } else {
                            toPath += item + ".public"
                        }
                        if fm.fileExists(atPath: toPath) {
                            do { try fm.removeItem(atPath: toPath) } catch {}
                        }
                        try fm.moveItem(atPath: cookiesDir + "/" + item, toPath: toPath)
                    }
                }
            }
        } catch {
            print(error)
        }
    }

    func enter() {
        if isOn {
            return
        }

        isOn = true

        getApp().tabManager.enterPrivateBrowsingMode(self)

        cookiesFileDiskOperation(.savePublicBackup)

        URLCache.shared.memoryCapacity = 0;
        URLCache.shared.diskCapacity = 0;

        let storage = HTTPCookieStorage.shared
        if let cookies = storage.cookies {
            for cookie in cookies {
                nonprivateCookies[cookie] = true
                storage.deleteCookie(cookie)
            }
        }

        NotificationCenter.default.addObserver(self, selector: #selector(PrivateBrowsing.cookiesChanged(_:)), name: NSNotification.Name.NSHTTPCookieManagerCookiesChanged, object: nil)

        webkitDirLocker(true)

        UserDefaults.standard.set(true, forKey: "WebKitPrivateBrowsingEnabled")
        
        NotificationCenter.default.post(name: NotificationPrivacyModeChanged, object: nil)
    }

    fileprivate var exitDeferred = Deferred<Void>()
    @discardableResult func exit() -> Deferred<Void> {
        let isAlwaysPrivate = getApp().profile?.prefs.boolForKey(kPrefKeyPrivateBrowsingAlwaysOn) ?? false

        exitDeferred = Deferred<Void>()
        if isAlwaysPrivate || !isOn {
            exitDeferred.fill(())
            return exitDeferred
        }

        isOn = false
        UserDefaults.standard.set(false, forKey: "WebKitPrivateBrowsingEnabled")
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(self, selector: #selector(allWebViewsKilled), name: NSNotification.Name(rawValue: kNotificationAllWebViewsDeallocated), object: nil)

        if getApp().tabManager.tabs.privateTabs.count < 1 {
            postAsyncToMain {
                self.allWebViewsKilled()
            }
        } else {
            getApp().tabManager.removeAllPrivateTabsAndNotify(false)

            postAsyncToMain(2) {
                if !self.exitDeferred.isFilled {
                    #if !NO_FABRIC
                        Answers.logCustomEvent(withName: "PrivateBrowsing exit failed", customAttributes: nil)
                    #endif
                    #if DEBUG
                        BraveApp.showErrorAlert(title: "PrivateBrowsing", error: "exit failed")
                    #endif
                    self.allWebViewsKilled()
                }
            }
        }
        
        NotificationCenter.default.post(name: NotificationPrivacyModeChanged, object: nil)

        return exitDeferred
    }

    @objc func allWebViewsKilled() {
        struct ReentrantGuard {
            static var inFunc = false
        }

        if ReentrantGuard.inFunc {
            return
        }
        ReentrantGuard.inFunc = true

        NotificationCenter.default.removeObserver(self)
        postAsyncToMain(0.1) { // just in case any other webkit object cleanup needs to complete
            if let clazz = NSClassFromString("Web" + "StorageManager") as? NSObjectProtocol {
                if clazz.responds(to: Selector("shared" + "WebStorageManager")) {
                    if let storage = clazz.perform(Selector("shared" + "WebStorageManager")) {
                        let o = storage.takeUnretainedValue()
                        o.perform(Selector("delete" + "AllOrigins"))
                    }
                }
            }
            if let clazz = NSClassFromString("Web" + "History") as? NSObjectProtocol {
                if clazz.responds(to: Selector("optional" + "SharedHistory")) {
                    if let webHistory = clazz.perform(Selector("optional" + "SharedHistory")) {
                        let o = webHistory.takeUnretainedValue()
                        o.perform(Selector("remove" + "AllItems"))
                    }
                }
            }

            self.webkitDirLocker(false)
            getApp().profile?.shutdown()
            getApp().profile?.db.reopenIfClosed()
            BraveApp.setupCacheDefaults()


            // clears PB in-memory-only shield data, loads from disk
            Domain.loadShieldsIntoMemory {
                let clear: [Clearable] = [CookiesClearable()]
                ClearPrivateDataTableViewController.clearPrivateData(clear).uponQueue(DispatchQueue.main) { _ in
                    self.cookiesFileDiskOperation(.deletePublicBackup)
                    let storage = HTTPCookieStorage.shared
                    for cookie in self.nonprivateCookies {
                        storage.setCookie(cookie.0)
                    }
                    self.nonprivateCookies = [HTTPCookie: Bool]()

                    getApp().tabManager.exitPrivateBrowsingMode(self)

                    self.exitDeferred.fillIfUnfilled(())
                    ReentrantGuard.inFunc = false
                }
            }
        }
    }

    @objc func cookiesChanged(_ info: Notification) {
        NotificationCenter.default.removeObserver(self)
        let storage = HTTPCookieStorage.shared
        var newCookies = [HTTPCookie]()
        if let cookies = storage.cookies {
            for cookie in cookies {
                if let readOnlyProps = cookie.properties {
                    var props = readOnlyProps as [HTTPCookiePropertyKey: Any]
                    let discard = props[HTTPCookiePropertyKey.discard] as? String
                    if discard == nil || discard! != "TRUE" {
                        props.removeValue(forKey: HTTPCookiePropertyKey.expires)
                        props[HTTPCookiePropertyKey.discard] = "TRUE"
                        storage.deleteCookie(cookie)
                        if let newCookie = HTTPCookie(properties: props) {
                            newCookies.append(newCookie)
                        }
                    }
                }
            }
        }
        for c in newCookies {
            storage.setCookie(c)
        }

        NotificationCenter.default.addObserver(self, selector: #selector(PrivateBrowsing.cookiesChanged(_:)), name: NSNotification.Name.NSHTTPCookieManagerCookiesChanged, object: nil)
    }
}
