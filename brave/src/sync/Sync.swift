/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import WebKit
import Shared
import CoreData
import SwiftKeychainWrapper

/*
 module.exports.categories = {
 BOOKMARKS: '0',
 HISTORY_SITES: '1',
 PREFERENCES: '2'
 }

 module.exports.actions = {
 CREATE: 0,
 UPDATE: 1,
 DELETE: 2
 }
 */

let NotificationSyncReady = "NotificationSyncReady"

// TODO: Make capitals - pluralize - call 'categories' not 'type'
public enum SyncRecordType : String {
    case bookmark = "BOOKMARKS"
    case history = "HISTORY_SITES"
    case prefs = "PREFERENCES"
    
    // Please note, this is not a general fetch record string, sync Devices are part of the Preferences
    case devices = "DEVICES"
    //
    
    
    // These are instances, and do not change, make lazy to cache value
    var fetchedModelType: SyncRecord.Type? {
        let map: [SyncRecordType : SyncRecord.Type] = [.bookmark : SyncBookmark.self, .prefs : SyncDevice.self]
        return map[self]
    }
    
    var coredataModelType: Syncable.Type? {
        let map: [SyncRecordType : Syncable.Type] = [.bookmark : Bookmark.self, .prefs : Device.self]
        return map[self]
    }
    
    var syncFetchMethod: String {
        return self == .devices ? "fetch-sync-devices" : "fetch-sync-records"
    }
}

public enum SyncObjectDataType : String {
    case Bookmark = "bookmark"
    case Prefs = "preference" // Remove
    
    // Device is considered part of preferences, this is to just be used internally for tracking a constant.
    //  At some point if Sync migrates to further abstracting Device to its own record type, this will be super close
    //  to just working out of the box
    case Device = "device"
}

enum SyncActions: Int {
    case create = 0
    case update = 1
    case delete = 2

}

class Sync: JSInjector {
    
    static let SeedByteLength = 32
    /// Number of records that is considered a fetch limit as opposed to full data set
    static let RecordRateLimitCount = 985
    static let shared = Sync()

    /// This must be public so it can be added into the view hierarchy 
    var webView: WKWebView!

    // Should not be accessed directly
    private var syncReadyLock = false
    var isSyncFullyInitialized = (syncReady: Bool, fetchReady: Bool, sendRecordsReady: Bool, fetchDevicesReady: Bool, resolveRecordsReady: Bool, deleteUserReady: Bool, deleteSiteSettingsReady: Bool, deleteCategoryReady: Bool)(false, false, false, false, false, false, false, false)
    
    var isInSyncGroup: Bool {
        return syncSeed != nil
    }
    
    private var fetchTimer: NSTimer?

    // TODO: Move to a better place
    private let prefNameId = "device-id-js-array"
    private let prefNameName = "sync-device-name"
    private let prefNameSeed = "seed-js-array"
    private let prefFetchTimestamp = "sync-fetch-timestamp"
    
//    #if DEBUG
//    private let isDebug = true
//    private let serverUrl = "https://sync-staging.brave.com"
//    #else
    private let isDebug = false
    private let serverUrl = "https://sync.brave.com"
//    #endif

    private let apiVersion = 0

    private var webConfig:WKWebViewConfiguration {
        let webCfg = WKWebViewConfiguration()
        let userController = WKUserContentController()

        userController.addScriptMessageHandler(self, name: "syncToIOS_on")
        userController.addScriptMessageHandler(self, name: "syncToIOS_send")

        // ios-sync must be called before bundle, since it auto-runs
        ["fetch", "ios-sync", "bundle"].forEach() {
            userController.addUserScript(WKUserScript(source: Sync.getScript($0), injectionTime: .AtDocumentEnd, forMainFrameOnly: true))
        }

        webCfg.userContentController = userController
        return webCfg
    }
    
    override init() {
        super.init()
        
        self.isJavascriptReadyCheck = checkIsSyncReady
        self.maximumDelayAttempts = 15
        self.delayLengthInSeconds = Int64(3.0)
        
        webView = WKWebView(frame: CGRectMake(30, 30, 300, 500), configuration: webConfig)
        // Attempt sync setup
        initializeSync()
    }
    
    func leaveSyncGroup() {
        syncSeed = nil
        if let device = Device.currentDevice() {
            // TODO: Find better way to handle deletions
            self.sendSyncRecords(.prefs, action: .delete, records: [device])
            // TODO: Remove ALL devices, since using solf deletes, this will just set isCurrentDevice = false for currentDevice
        }
    }
    
    /// Sets up sync to actually start pulling/pushing data. This method can only be called once
    /// seed (optional): The user seed, in the form of string hex values. Must be even number : ["00", "ee", "4a", "42"]
    /// Notice:: seed will be ignored if the keychain already has one, a user must disconnect from existing sync group prior to joining a new one
    func initializeSync(seed: [Int]? = nil, deviceName: String? = nil) {
        
        if let joinedSeed = seed where joinedSeed.count == Sync.SeedByteLength {
            // Always attempt seed write, setter prevents bad overwrites
            syncSeed = "\(joinedSeed)"
        }
        
        // Check to not override deviceName with `nil` on sync init, which happens every app launch
        if let deviceName = deviceName {
            Device.currentDevice()?.name = deviceName
            DataController.saveContext(Device.currentDevice()?.managedObjectContext)
        }
        
        // Autoload sync if already connected to a sync group, otherwise just wait for user initiation
        if let _ = syncSeed {
            self.webView.loadHTMLString("<body>TEST</body>", baseURL: nil)
        }
    }
    
    func initializeNewSyncGroup(deviceName name: String?) {
        if syncSeed != nil {
            // Error, to setup new sync group, must have no seed
            return
        }
        
        Device.currentDevice()?.name = name
        DataController.saveContext(Device.currentDevice()?.managedObjectContext)
        
        self.webView.loadHTMLString("<body>TEST</body>", baseURL: nil)
    }

    class func getScript(name:String) -> String {
        // TODO: Add unwrapping warnings
        // TODO: Place in helper location
        let filePath = NSBundle.mainBundle().pathForResource(name, ofType:"js")
        return try! String(contentsOfFile: filePath!, encoding: NSUTF8StringEncoding)
    }

    private func webView(webView: WKWebView, didFinish navigation: WKNavigation!) {
        print(#function)
    }

    private var syncSeed: String? {
        get {
            if !NSUserDefaults.standardUserDefaults().boolForKey(prefNameSeed) {
                // This must be true to stay in sync group
                KeychainWrapper.defaultKeychainWrapper().removeObjectForKey(prefNameSeed)
                return nil
            }
            
            return KeychainWrapper.defaultKeychainWrapper().stringForKey(prefNameSeed)
        }
        set(value) {
            // TODO: Move syncSeed validation here, remove elsewhere
            
            if isInSyncGroup && value != nil {
                // Error, cannot replace sync seed with another seed
                //  must set syncSeed to nil prior to replacing it
                return
            }
            
            if let value = value {
                KeychainWrapper.defaultKeychainWrapper().setString(value, forKey: prefNameSeed)
                // Here, we are storing a value to signify a group has been joined
                //  this is _only_ used on a re-installation to know that the app was deleted and re-installed
                NSUserDefaults.standardUserDefaults().setBool(true, forKey: prefNameSeed)
                return
            }
            
            // Leave group:
            
            // Clean up group specific items
            
            // TODO: Update all records with originalSyncSeed
            
            
            Device.deleteAll {}
            
            lastFetchedRecordTimestamp = 0
            lastSuccessfulSync = 0
            lastFetchWasTrimmed = false
            syncReadyLock = false
            isSyncFullyInitialized = (false, false, false, false, false, false, false, false)
            
            fetchTimer?.invalidate()
            fetchTimer = nil
            
            KeychainWrapper.defaultKeychainWrapper().removeObjectForKey(prefNameSeed)
        }
    }
    
    var syncSeedArray: [Int]? {
        let splitBytes = syncSeed?.componentsSeparatedByCharactersInSet(NSCharacterSet(charactersInString: "[], ")).filter { !$0.isEmpty }
        let seed = splitBytes?.map{ Int($0) }.flatMap{ $0 }
        return seed?.count == Sync.SeedByteLength ? seed : nil
    }
    
    
    // TODO: Abstract into classes as static members, each object type needs their own sync time stamp!
    // This includes just the last record that was fetched, used to store timestamp until full process has been completed
    //  then set into defaults
    private var lastFetchedRecordTimestamp: Int? = 0
    // This includes the entire process: fetching, resolving, insertion/update, and save
    private var lastSuccessfulSync: Int {
        get {
            return NSUserDefaults.standardUserDefaults().integerForKey(prefFetchTimestamp)
        }
        set(value) {
            NSUserDefaults.standardUserDefaults().setInteger(value, forKey: prefFetchTimestamp)
            NSUserDefaults.standardUserDefaults().synchronize()
        }
    }
    
    // Same abstraction note as above
    //  Used to know if data on get-existing-objects was trimmed, this value is used inside resolved-sync-records
    private var lastFetchWasTrimmed: Bool = false
    ////////////////////////////////
    

    func checkIsSyncReady() -> Bool {
        
        if syncReadyLock {
            return true
        }

        let mirror = Mirror(reflecting: isSyncFullyInitialized)
        let ready = mirror.children.reduce(true) { $0 && $1.1 as! Bool }
        if ready {
            // Attempt to authorize device
            
            syncReadyLock = true
            NSNotificationCenter.defaultCenter().postNotificationName(NotificationSyncReady, object: nil)
            
            if let device = Device.currentDevice() where !device.isSynced {
                self.sendSyncRecords(.prefs, action: .create, records: [device])
                
                // Currently just force this, should use network, but too error prone currently
                Device.currentDevice()?.isSynced = true
                DataController.saveContext(Device.currentDevice()?.managedObjectContext)
            }
            
            func startFetching() {
                // Perform first fetch manually
                self.fetch(.bookmark)
                
                // Fetch timer to run on regular basis
                fetchTimer = NSTimer.scheduledTimerWithTimeInterval(30.0, target: self, selector: #selector(Sync.fetchWrapper), userInfo: nil, repeats: true)
            }
            
            // Just throw by itself, does not need to recover or retry due to lack of importance
            self.fetch(.devices)
            
            // Use proper variable and store in defaults
            if lastSuccessfulSync == 0 {
                // Sync local bookmarks, then proceed with fetching
                // Pull all local bookmarks
                // Insane .map required for mapping obj-c class to Swift, in order to use protocol instead of class for array param
                self.sendSyncRecords(.bookmark, action: .create, records: Bookmark.getAllBookmarks(DataController.shared.workerContext()).map{$0}) { error in
                    startFetching()
                }
            } else {
                startFetching()
            }
        }
        return ready
    }
    
    // Required since fetch is wrapped in extension and timer hates that.
    // This can be removed and fetch called directly via scheduledTimerBlock
    func fetchWrapper() {
        self.fetch(.bookmark)
    }
 }

// MARK: Native-initiated Message category
extension Sync {
    // TODO: Rename
    func sendSyncRecords(recordType: SyncRecordType, action: SyncActions, records: [Syncable], completion: (NSError? -> Void)? = nil) {
        
        // Consider protecting against (isSynced && .create)
        
        if records.isEmpty {
            completion?(nil)
            return
        }
        
        if !isInSyncGroup {
            completion?(nil)
            return
        }
        
        executeBlockOnReady() {
            
            // TODO: DeviceId should be sitting on each object already, use that
            let syncRecords = records.map { $0.asDictionary(deviceId: Device.currentDevice()?.deviceId, action: action.rawValue) }
            
            guard let json = NSJSONSerialization.jsObject(withNative: syncRecords, escaped: false) else {
                // Huge error
                return
            }

            /* browser -> webview, sends this to the webview with the data that needs to be synced to the sync server.
             @param {string} categoryName, @param {Array.<Object>} records */
            let evaluate = "callbackList['send-sync-records'](null, '\(recordType.rawValue)',\(json))"
            self.webView.evaluateJavaScript(evaluate,
                                       completionHandler: { (result, error) in
                                        if error != nil {
                                            print(error)
                                        }
                                        
                                        completion?(error)
            })
        }
    }

    func gotInitData() {
        let deviceId = Device.currentDevice()?.deviceId?.description ?? "null"
        let syncSeed = isInSyncGroup ? "new Uint8Array(\(self.syncSeed!))" : "null"
        
        let args = "(null, \(syncSeed), \(deviceId), {apiVersion: '\(apiVersion)', serverUrl: '\(serverUrl)', debug:\(isDebug)})"
        webView.evaluateJavaScript("callbackList['got-init-data']\(args)",
                                   completionHandler: { (result, error) in
//                                    print(result)
//                                    if error != nil {
//                                        print(error)
//                                    }
        })
    }
    
    /// Makes call to sync to fetch new records, instead of just returning records, sync sends `get-existing-objects` message
    func fetch(type: SyncRecordType, completion: (NSError? -> Void)? = nil) {
        /*  browser -> webview: sent to fetch sync records after a given start time from the sync server.
         @param Array.<string> categoryNames, @param {number} startAt (in seconds) **/
        
        executeBlockOnReady() {
            
            // Pass in `lastFetch` to get records since that time
            let evaluate = "callbackList['\(type.syncFetchMethod)'](null, ['\(type.rawValue)'], \(self.lastSuccessfulSync), 1000)"
            self.webView.evaluateJavaScript(evaluate,
                                       completionHandler: { (result, error) in
                                        completion?(error)
            })
        }
    }

    func resolvedSyncRecords(data: SyncResponse?) {
        
        // TODO: Abstract this logic, same used as in getExistingObjects
        guard let recordJSON = data?.rootElements, let apiRecodType = data?.arg1, let recordType = SyncRecordType(rawValue: apiRecodType) else { return }
        
        guard var fetchedRecords = recordType.fetchedModelType?.syncRecords(recordJSON) else { return }

        // Currently only prefs are device related
        if recordType == .prefs, let data = fetchedRecords as? [SyncDevice] {
            // Devices have really bad data filtering, so need to manually process more of it
            // Sort to not rely on API - Reverse sort, so unique pulls the `latest` not just the `first`
            fetchedRecords = data.sort { $0.0.syncTimestamp > $0.1.syncTimestamp }.unique { $0.objectId ?? [] == $1.objectId ?? [] }
        }
        
        let context = DataController.shared.workerContext()
        for fetchedRoot in fetchedRecords {
            
            guard
                let fetchedId = fetchedRoot.objectId
                else { return }
            
            let singleRecord = recordType.coredataModelType?.get(syncUUIDs: [fetchedId], context: context)?.first as? Syncable
            
            var action = SyncActions(rawValue: fetchedRoot.action ?? -1)
            if action == SyncActions.delete {
                singleRecord?.remove()
            } else if action == SyncActions.create {
                
                if singleRecord != nil {
                    // This can happen pretty often, especially for records that don't use diffs (e.g. prefs>devices)
                    // They always return a create command, even if they already "exist", since there is no real 'resolving'
                    //  Hence check below to prevent duplication
                }
                    
                // TODO: Needs favicon
                if singleRecord == nil {
                    recordType.coredataModelType?.add(rootObject: fetchedRoot, save: false, sendToSync: false, context: context)
                } else {
                    // TODO: use Switch with `fallthrough`
                    action = .update
                }
            }
            
            // Handled outside of else block since .create, can modify to an .update
            if action == .update {
                singleRecord?.update(syncRecord: fetchedRoot)
            }
        }
        
        DataController.saveContext(context)
        print("\(fetchedRecords.count) \(recordType.rawValue) processed")
        
        // Make generic when other record types are supported
        if recordType != .bookmark {
            // Currently only support bookmark timestamp, so do not want to adjust that
            return
        }
        
        // After records have been written, without issue, save timestamp
        // We increment by a single millisecond to make sure we don't re-fetch the same duplicate records over and over
        // If there are more records with the same timestamp than the batch size, they will be dropped,
        //  however this is unimportant, as it actually prevents an infinitely recursive loop, of refetching the same records over
        //  and over again
        if let stamp = self.lastFetchedRecordTimestamp { self.lastSuccessfulSync = stamp + 1 }
        
        if self.lastFetchWasTrimmed {
            // Do fast refresh, do not wait for timer
            self.fetch(.bookmark)
            self.lastFetchWasTrimmed = false
        }
    }

    func deleteSyncUser(data: [String: AnyObject]) {
        print("not implemented: deleteSyncUser() \(data)")
    }

    func deleteSyncCategory(data: [String: AnyObject]) {
        print("not implemented: deleteSyncCategory() \(data)")
    }

    func deleteSyncSiteSettings(data: [String: AnyObject]) {
        print("not implemented: delete sync site settings \(data)")
    }

}

// MARK: Server To Native Message category
extension Sync {

    func getExistingObjects(data: SyncResponse?) {
        
        guard let recordJSON = data?.rootElements, let apiRecodType = data?.arg1, let recordType = SyncRecordType(rawValue: apiRecodType) else { return }

        guard let fetchedRecords = recordType.fetchedModelType?.syncRecords(recordJSON) else { return }

        let ids = fetchedRecords.map { $0.objectId }.flatMap { $0 }
        let localbookmarks = recordType.coredataModelType?.get(syncUUIDs: ids, context: DataController.shared.workerContext()) as? [Bookmark]
        
        
        var matchedBookmarks = [[AnyObject]]()
        for fetchedBM in fetchedRecords {
            
            // TODO: Replace with find(where:) in Swift3
            var localBM: AnyObject = "null"
            for l in localbookmarks ?? [] {
                if let localId = l.syncUUID, let fetchedId = fetchedBM.objectId where localId == fetchedId {
                    localBM = l.asDictionary(deviceId: Device.currentDevice()?.deviceId, action: fetchedBM.action)
                    break
                }
            }
            
            matchedBookmarks.append([fetchedBM.dictionaryRepresentation(), localBM])
        }

        /* Top level keys: "bookmark", "action","objectId", "objectData:bookmark","deviceId" */
        
        // TODO: Check if parsing not required
        guard let serializedData = NSJSONSerialization.jsObject(withNative: matchedBookmarks, escaped: false) else {
            // Huge error
            return
        }
        
        // Only currently support bookmarks, this data will be abstracted (see variable definition note)
        if recordType == .bookmark {
            // Store the last record's timestamp, to know what timestamp to pass in next time if this one does not fail
            self.lastFetchedRecordTimestamp = data?.lastFetchedTimestamp
            self.lastFetchWasTrimmed = data?.isTruncated ?? false
        }
        
        self.webView.evaluateJavaScript("callbackList['resolve-sync-records'](null, '\(recordType.rawValue)', \(serializedData))",
            completionHandler: { (result, error) in })
    }

    // Only called when the server has info for client to save
    func saveInitData(data: JSON) {
        // Sync Seed
        if let seedJSON = data["arg1"].asArray {
            let seed = seedJSON.map({ $0.asInt }).flatMap({ $0 })
            
            // TODO: Move to constant
            if seed.count < Sync.SeedByteLength {
                // Error
                return
            }
            
            syncSeed = "\(seed)"

        } else if syncSeed == nil {
            // Failure
            print("Seed expected.")
        }
        
        // Device Id
        if let deviceArray = data["arg2"].asArray where deviceArray.count > 0 {
            // TODO: Just don't set, if bad, allow sync to recover on next init
            Device.currentDevice()?.deviceId = deviceArray.map { $0.asInt ?? 0 }
            DataController.saveContext(Device.currentDevice()?.managedObjectContext)
        } else if Device.currentDevice()?.deviceId == nil {
            print("Device Id expected!")
        }

    }

}

extension Sync: WKScriptMessageHandler {
    func userContentController(userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        //print("😎 \(message.name) \(message.body)")
        
        let syncResponse = SyncResponse(object: message.body)
        guard let messageName = syncResponse.message else {
            assert(false)
            return
        }

        switch messageName {
        case "get-init-data":
//            getInitData()
            break
        case "got-init-data":
            gotInitData()
        case "save-init-data" :
            // A bit hacky, but this method's data is not very uniform
            // (e.g. arg2 is [Int])
            let data = JSON(string: message.body as? String ?? "")
            saveInitData(data)
        case "get-existing-objects":
            getExistingObjects(syncResponse)
        case "resolved-sync-records":
            resolvedSyncRecords(syncResponse)
        case "sync-debug":
            let data = JSON(string: message.body as? String ?? "")
            print("---- Sync Debug: \(data)")
        case "sync-ready":
            isSyncFullyInitialized.syncReady = true
        case "fetch-sync-records":
            isSyncFullyInitialized.fetchReady = true
        case "send-sync-records":
            isSyncFullyInitialized.sendRecordsReady = true
        case "fetch-sync-devices":
            isSyncFullyInitialized.fetchDevicesReady = true
        case "resolve-sync-records":
            isSyncFullyInitialized.resolveRecordsReady = true
        case "delete-sync-user":
            isSyncFullyInitialized.deleteUserReady = true
        case "delete-sync-site-settings":
            isSyncFullyInitialized.deleteSiteSettingsReady = true
        case "delete-sync-category":
            isSyncFullyInitialized.deleteCategoryReady = true
        default:
            print("\(messageName) not handled yet")
        }

        checkIsSyncReady()
    }
}

