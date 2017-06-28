/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Alamofire
import Foundation

import ReadingList
import Shared
import Storage

import XCGLogger
import SwiftKeychainWrapper
import Deferred

private let log = Logger.syncLogger

public let NotificationProfileDidStartSyncing = NSNotification.Name(rawValue: "NotificationProfileDidStartSyncing")
public let NotificationProfileDidFinishSyncing = NSNotification.Name(rawValue: "NotificationProfileDidFinishSyncing")
public let ProfileRemoteTabsSyncDelay: TimeInterval = 0.1

typealias EngineIdentifier = String

class ProfileFileAccessor: FileAccessor {
    convenience init(profile: Profile) {
        self.init(localName: profile.localName())
    }

    init(localName: String) {
        let profileDirName = "profile.\(localName)"
        
        // Bug 1147262: First option is for device, second is for simulator.
        var rootPath: String
        let sharedContainerIdentifier = AppInfo.sharedContainerIdentifier
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: sharedContainerIdentifier) {
            rootPath = url.path
        } else {
            log.error("Unable to find the shared container. Defaulting profile location to ~/Documents instead.")
            rootPath = (NSSearchPathForDirectoriesInDomains(FileManager.SearchPathDirectory.documentDirectory, FileManager.SearchPathDomainMask.userDomainMask, true)[0])
        }
        
        super.init(rootPath: URL(fileURLWithPath: rootPath).appendingPathComponent(profileDirName).path)
    }
}

/**
 * This exists because the Sync code is extension-safe, and thus doesn't get
 * direct access to UIApplication.sharedApplication, which it would need to
 * display a notification.
 * This will also likely be the extension point for wipes, resets, and
 * getting access to data sources during a sync.
 */

let TabSendURLKey = "TabSendURL"
let TabSendTitleKey = "TabSendTitle"
let TabSendCategory = "TabSendCategory"

enum SentTabAction: String {
    case View = "TabSendViewAction"
    case Bookmark = "TabSendBookmarkAction"
    case ReadingList = "TabSendReadingListAction"
}


/**
 * A Profile manages access to the user's data.
 */
protocol Profile: class {
    var bookmarks: BookmarksModelFactorySource & ShareToDestination & SyncableBookmarks & LocalItemSource & MirrorItemSource { get }
    // var favicons: Favicons { get }
    var prefs: Prefs { get }
    var queue: TabQueue { get }
    var searchEngines: SearchEngines { get }
    var files: FileAccessor { get }
    var history: BrowserHistory & SyncableHistory & ResettableSyncStorage { get }
    var favicons: Favicons { get }
    var readingList: ReadingListService? { get }
    var logins: BrowserLogins & SyncableLogins & ResettableSyncStorage { get }
    var certStore: CertStore { get }

    func shutdown()
    func reopen()

    // I got really weird EXC_BAD_ACCESS errors on a non-null reference when I made this a getter.
    // Similar to <http://stackoverflow.com/questions/26029317/exc-bad-access-when-indirectly-accessing-inherited-member-in-swift>.
    func localName() -> String
}

open class BrowserProfile: Profile {
    fileprivate static var __once1: () = {
            if KeychainWrapper.hasValueForKey(key) {
                let value = KeychainWrapper.stringForKey(key)
                Singleton.instance = value
            } else {
                let Length: UInt = 256
                let secret = Bytes.generateRandomBytes(Length).base64EncodedString
                KeychainWrapper.setString(secret, forKey: key)
                Singleton.instance = secret
            }
        }()
    fileprivate static var __once: () = {
            Singleton.instance = BrowserDB(filename: "browser.db", files: self.files)
            BrowserProfile.dbCreated = true
        }()
    fileprivate let name: String
    internal let files: FileAccessor

    weak fileprivate var app: UIApplication?

    /**
     * N.B., BrowserProfile is used from our extensions, often via a pattern like
     *
     *   BrowserProfile(…).foo.saveSomething(…)
     *
     * This can break if BrowserProfile's initializer does async work that
     * subsequently — and asynchronously — expects the profile to stick around:
     * see Bug 1218833. Be sure to only perform synchronous actions here.
     */
    init(localName: String, app: UIApplication?, clear: Bool = false) {
        log.debug("Initing profile \(localName) on thread \(Thread.current).")
        self.name = localName
        self.files = ProfileFileAccessor(localName: localName)
        self.app = app

        if clear {
            do {
                try FileManager.default.removeItem(atPath: self.files.rootPath as String)
            } catch {
                log.info("Cannot clear profile: \(error)")
            }
        }

        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(BrowserProfile.onProfileDidFinishSyncing(_:)), name: NotificationProfileDidFinishSyncing, object: nil)
        notificationCenter.addObserver(self, selector: #selector(BrowserProfile.onPrivateDataClearedHistory(_:)), name: NotificationPrivateDataClearedHistory, object: nil)


        if let baseBundleIdentifier = AppInfo.baseBundleIdentifier {
            KeychainWrapper.serviceName = baseBundleIdentifier
        } else {
            log.error("Unable to get the base bundle identifier. Keychain data will not be shared.")
        }

        // If the profile dir doesn't exist yet, this is first run (for this profile).
        if !files.exists("") {
            log.info("New profile. Removing old account metadata.")
            self.removeAccountMetadata()
            self.removeExistingAuthenticationInfo()
            prefs.clearAll()
        }

        // Always start by needing invalidation.
        // This is the same as self.history.setTopSitesNeedsInvalidation, but without the
        // side-effect of instantiating SQLiteHistory (and thus BrowserDB) on the main thread.
        prefs.setBool(false, forKey: PrefsKeys.KeyTopSitesCacheIsValid)
    }

    // Extensions don't have a UIApplication.
    convenience init(localName: String) {
        self.init(localName: localName, app: nil)
    }

    func reopen() {
        log.debug("Reopening profile.")

        if dbCreated {
            db.reopenIfClosed()
        }

        if loginsDBCreated {
            loginsDB.reopenIfClosed()
        }
    }

    func shutdown() {
        log.debug("Shutting down profile.")

        if self.dbCreated {
            db.forceClose()
        }

        if self.loginsDBCreated {
            loginsDB.forceClose()
        }
    }

    func onLocationChange(_ info: [String : AnyObject]) {
        if let v = info["visitType"] as? Int,
            let visitType = VisitType(rawValue: v),
            let url = info["url"] as? URL, !isIgnoredURL(url),
            let title = info["title"] as? NSString {
            // Only record local vists if the change notification originated from a non-private tab
            if !(info["isPrivate"] as? Bool ?? false) {
                // We don't record a visit if no type was specified -- that means "ignore me".
                let site = Site(url: url.absoluteString ?? "", title: title as String)
                let visit = SiteVisit(site: site, date: Date.nowMicroseconds(), type: visitType)
                succeed().upon() { _ in // move off main thread
                    self.history.addLocalVisit(visit)
                }
            }

            history.setTopSitesNeedsInvalidation()
        } else {
            log.debug("Ignoring navigation.")
        }
    }

    // These selectors run on which ever thread sent the notifications (not the main thread)
    @objc
    func onProfileDidFinishSyncing(_ notification: Notification) {
        history.setTopSitesNeedsInvalidation()
    }

    @objc
    func onPrivateDataClearedHistory(_ notification: Notification) {
        // Immediately invalidate the top sites cache
        history.refreshTopSitesCache()
    }

    deinit {
        log.debug("Deiniting profile \(self.localName).")
        NotificationCenter.default.removeObserver(self, name: NotificationPrivateDataClearedHistory, object: nil)
    }

    func localName() -> String {
        return name
    }

    lazy var queue: TabQueue = {
        withExtendedLifetime(self.history) {
            return SQLiteQueue(db: self.db)
        }
    }()

    fileprivate var dbCreated = false
    var db: BrowserDB {
        struct Singleton {
            static var token: Int = 0
            static var instance: BrowserDB!
        }
        _ = BrowserProfile.__once
        return Singleton.instance
    }

    /**
     * Favicons, history, and bookmarks are all stored in one intermeshed
     * collection of tables.
     *
     * Any other class that needs to access any one of these should ensure
     * that this is initialized first.
     */
    fileprivate lazy var places: BrowserHistory & Favicons & SyncableHistory & ResettableSyncStorage = {
        return SQLiteHistory(db: self.db, prefs: self.prefs)
    }()

    var favicons: Favicons {
        return self.places
    }

    var history: BrowserHistory & SyncableHistory & ResettableSyncStorage {
        return self.places
    }

    lazy var bookmarks: BookmarksModelFactorySource & ShareToDestination & SyncableBookmarks & LocalItemSource & MirrorItemSource = {
        // Make sure the rest of our tables are initialized before we try to read them!
        // This expression is for side-effects only.
        withExtendedLifetime(self.places) {
            return MergedSQLiteBookmarks(db: self.db)
        }
    }()

    lazy var mirrorBookmarks: BookmarkBufferStorage & BufferItemSource = {
        // Yeah, this is lazy. Sorry.
        return self.bookmarks as! MergedSQLiteBookmarks
    }()

    lazy var searchEngines: SearchEngines = {
        return SearchEngines(prefs: self.prefs)
    }()

    func makePrefs() -> Prefs {
        return NSUserDefaultsPrefs(prefix: self.localName())
    }

    lazy var prefs: Prefs = {
        return self.makePrefs()
    }()

    lazy var readingList: ReadingListService? = {
        return ReadingListService(profileStoragePath: self.files.rootPath as String)
    }()

    lazy var remoteClientsAndTabs: RemoteClientsAndTabs & ResettableSyncStorage & AccountRemovalDelegate = {
        return SQLiteRemoteClientsAndTabs(db: self.db)
    }()

    lazy var certStore: CertStore = {
        return CertStore()
    }()

    open func getCachedClientsAndTabs() -> Deferred<Maybe<[ClientAndTabs]>> {
        return self.remoteClientsAndTabs.getClientsAndTabs()
    } 

    func storeTabs(_ tabs: [RemoteTab]) -> Deferred<Maybe<Int>> {
        return self.remoteClientsAndTabs.insertOrUpdateTabs(tabs)
    }

    lazy var logins: BrowserLogins & SyncableLogins & ResettableSyncStorage = {
        return SQLiteLogins(db: self.loginsDB)
    }()

    // This is currently only used within the dispatch_once block in loginsDB, so we don't
    // have to worry about races giving us two keys. But if this were ever to be used
    // elsewhere, it'd be unsafe, so we wrap this in a dispatch_once, too.
    fileprivate var loginsKey: String? {
        let key = "sqlcipher.key.logins.db"
        struct Singleton {
            static var token: Int = 0
            static var instance: String!
        }
        _ = BrowserProfile.__once1
        return Singleton.instance
    }

    fileprivate var loginsDBCreated = false
    fileprivate lazy var loginsDB: BrowserDB = {
        struct Singleton {
            static var token: dispatch_once_t = 0
            static var instance: BrowserDB!
        }
        dispatch_once(&Singleton.token) {
            Singleton.instance = BrowserDB(filename: "logins.db", secretKey: self.loginsKey, files: self.files)
            self.loginsDBCreated = true
        }
        return Singleton.instance
    }()


    func removeAccountMetadata() {
        self.prefs.removeObjectForKey(PrefsKeys.KeyLastRemoteTabSyncTime)
        KeychainWrapper.removeObjectForKey(self.name + ".account")
    }

    func removeExistingAuthenticationInfo() {
        KeychainWrapper.setAuthenticationInfo(nil)
    }
}
