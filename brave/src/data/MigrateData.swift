/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Storage
import CoreData

class MigrateData: NSObject {
    
    private var files: FileAccessor!
    private var db: COpaquePointer = nil
    
    enum ProcessOrder: Int {
        case Bookmarks = 0
        case History = 1
        case Domains = 2
        case Favicons = 3
        case Tabs = 4
        case Delete = 5
    }
    var completedCalls: [ProcessOrder: Bool] = [.Bookmarks: false, .History: false, .Domains: false, .Favicons: false, .Tabs: false] {
        didSet {
            checkCompleted()
        }
    }
    var completedCallback: ((success: Bool) -> Void)?
    
    required convenience init(completed: ((success: Bool) -> Void)?) {
        self.init()
        self.files = ProfileFileAccessor(localName: "profile")
        
        completedCallback = completed
        process()
    }
    
    override init() {
        super.init()
    }
    
    private func process() {
        if hasOldDb() {
            debugPrint("Found old database...")
            
            migrateDomainData { (success) in
                debugPrint("Migrate domains... \(success ? "Done" : "Failed")")
                self.completedCalls[ProcessOrder.Domains] = success
            }
            migrateFavicons { (success) in
                debugPrint("Migrate favicons... \(success ? "Done" : "Failed")")
                self.completedCalls[ProcessOrder.Favicons] = success
            }
            migrateHistory { (success) in
                debugPrint("Migrate history... \(success ? "Done" : "Failed")")
                self.completedCalls[ProcessOrder.History] = success
            }
            migrateBookmarks { (success) in
                debugPrint("Migrate bookmarks... \(success ? "Done" : "Failed")")
                self.completedCalls[ProcessOrder.Bookmarks] = success
            }
            migrateTabs { (success) in
                debugPrint("Migrate tabs... \(success ? "Done" : "Failed")")
                self.completedCalls[ProcessOrder.Tabs] = success
            }
        }
    }
    
    private func hasOldDb() -> Bool {
        let file = ((try! files.getAndEnsureDirectory()) as NSString).stringByAppendingPathComponent("browser.db")
        let status = sqlite3_open_v2(file.cStringUsingEncoding(NSUTF8StringEncoding)!, &db, SQLITE_OPEN_READONLY, nil)
        if status != SQLITE_OK {
            debugPrint("Error: Opening Database with Flags")
            return false
        }
        return true
    }
    
    internal var domainHash: [Int32: Domain] = [:]
    
    private func migrateDomainData(completed: (success: Bool) -> Void) {
        let query: String = "SELECT id, domain, showOnTopSites FROM domains"
        var results: COpaquePointer = nil
        
        if sqlite3_prepare_v2(db, query, -1, &results, nil) == SQLITE_OK {
            while sqlite3_step(results) == SQLITE_ROW {
                let id = sqlite3_column_int(results, 0)
                let domain = String.fromCString(UnsafePointer<CChar>(sqlite3_column_text(results, 1))) ?? ""
                let showOnTopSites = sqlite3_column_int(results, 2)
                
                if let d = Domain.getOrCreateForUrl(NSURL(string: domain)!, context: DataController.shared.workerContext()) {
                    d.topsite = (showOnTopSites == 1)
                    domainHash[id] = d
                }
            }
            DataController.saveContext(DataController.shared.workerContext())
        } else {
            debugPrint("SELECT statement could not be prepared")
        }
        
        if sqlite3_finalize(results) != SQLITE_OK {
            let error = String.fromCString(sqlite3_errmsg(db))
            debugPrint("Error finalizing prepared statement: \(error)")
        }
        results = nil
        completed(success: true)
    }
    
    private func migrateHistory(completed: (success: Bool) -> Void) {
        let query: String = "SELECT url, title FROM history WHERE is_deleted = 0"
        var results: COpaquePointer = nil
        
        if sqlite3_prepare_v2(db, query, -1, &results, nil) == SQLITE_OK {
            while sqlite3_step(results) == SQLITE_ROW {
                let url = String.fromCString(UnsafePointer<CChar>(sqlite3_column_text(results, 0))) ?? ""
                let title = String.fromCString(UnsafePointer<CChar>(sqlite3_column_text(results, 1))) ?? ""
                
                History.add(title: title, url: NSURL(string: url)!)
            }
        } else {
            debugPrint("SELECT statement could not be prepared")
        }
        
        if sqlite3_finalize(results) != SQLITE_OK {
            let error = String.fromCString(sqlite3_errmsg(db))
            debugPrint("Error finalizing prepared statement: \(error)")
        }
        results = nil
        completed(success: true)
    }
    
    internal var domainFaviconHash: [Int32: Domain] = [:]
    
    private func buildDomainFaviconHash() {
        let query: String = "SELECT siteID, faviconID FROM favicon_sites"
        var results: COpaquePointer = nil
        
        if sqlite3_prepare_v2(db, query, -1, &results, nil) == SQLITE_OK {
            while sqlite3_step(results) == SQLITE_ROW {
                let domainId = sqlite3_column_int(results, 0)
                let faviconId = sqlite3_column_int(results, 1)
                if let domain = domainHash[domainId] {
                    domainFaviconHash[faviconId] = domain
                }
            }
        } else {
            debugPrint("SELECT statement could not be prepared")
        }
        
        if sqlite3_finalize(results) != SQLITE_OK {
            let error = String.fromCString(sqlite3_errmsg(db))
            debugPrint("Error finalizing prepared statement: \(error)")
        }
        results = nil
    }
    
    private func migrateFavicons(completed: (success: Bool) -> Void) {
        buildDomainFaviconHash()
        
        let query: String = "SELECT id, url, width, height, type FROM favicons"
        var results: COpaquePointer = nil
        
        if sqlite3_prepare_v2(db, query, -1, &results, nil) == SQLITE_OK {
            while sqlite3_step(results) == SQLITE_ROW {
                let id = sqlite3_column_int(results, 0)
                let url = String.fromCString(UnsafePointer<CChar>(sqlite3_column_text(results, 1))) ?? ""
                let width = sqlite3_column_int(results, 2)
                let height = sqlite3_column_int(results, 3)
                let type = sqlite3_column_int(results, 4)
                
                let favicon = Favicon(url: url, type: IconType(rawValue: Int(type))!)
                favicon.width = Int(width)
                favicon.height = Int(height)
                
                if let domain = domainFaviconHash[id] {
                    if let url = domain.url {
                        FaviconMO.add(favicon: favicon, forSiteUrl: NSURL(string: url)!)
                    }
                }
            }
        } else {
            debugPrint("SELECT statement could not be prepared")
        }
        
        if sqlite3_finalize(results) != SQLITE_OK {
            let error = String.fromCString(sqlite3_errmsg(db))
            debugPrint("Error finalizing prepared statement: \(error)")
        }
        results = nil
        completed(success: true)
    }
    
    internal var bookmarkOrderHash: [String: Int16] = [:]
    
    private func buildBookmarkOrderHash() {
        let query: String = "SELECT child, idx FROM bookmarksLocalStructure"
        var results: COpaquePointer = nil
        
        if sqlite3_prepare_v2(db, query, -1, &results, nil) == SQLITE_OK {
            while sqlite3_step(results) == SQLITE_ROW {
                let child = String.fromCString(UnsafePointer<CChar>(sqlite3_column_text(results, 0))) ?? ""
                let idx = sqlite3_column_int(results, 1)
                bookmarkOrderHash[child] = Int16(idx)
            }
        } else {
            debugPrint("SELECT statement could not be prepared")
        }
        
        if sqlite3_finalize(results) != SQLITE_OK {
            let error = String.fromCString(sqlite3_errmsg(db))
            debugPrint("Error finalizing prepared statement: \(error)")
        }
        results = nil
    }
    
    private func migrateBookmarks(completed: (success: Bool) -> Void) {
        buildBookmarkOrderHash()
        
        let query: String = "SELECT guid, type, parentid, title, description, bmkUri, faviconID FROM bookmarksLocal WHERE (id > 4 AND is_deleted = 0) ORDER BY type DESC"
        var results: COpaquePointer = nil
        
        if sqlite3_prepare_v2(db, query, -1, &results, nil) == SQLITE_OK {
            var relationshipHash: [String: Bookmark] = [:]
            while sqlite3_step(results) == SQLITE_ROW {
                let guid = String.fromCString(UnsafePointer<CChar>(sqlite3_column_text(results, 0))) ?? ""
                let type = sqlite3_column_int(results, 1)
                let parentid = String.fromCString(UnsafePointer<CChar>(sqlite3_column_text(results, 2))) ?? ""
                let title = String.fromCString(UnsafePointer<CChar>(sqlite3_column_text(results, 3))) ?? ""
                let description = String.fromCString(UnsafePointer<CChar>(sqlite3_column_text(results, 4))) ?? ""
                let url = String.fromCString(UnsafePointer<CChar>(sqlite3_column_text(results, 5))) ?? ""
                
                if let bk = Bookmark.addForMigration(url: url, title: title, customTitle: description, parentFolder: relationshipHash[parentid] ?? nil, isFolder: (type == 2)) {
                    let parent = relationshipHash[parentid]
                    bk.parentFolder = parent
                    bk.syncParentUUID = parent?.syncUUID
                    if let baseUrl = NSURL(string: url)?.baseURL {
                        bk.domain = Domain.getOrCreateForUrl(baseUrl, context: DataController.shared.workerContext())
                    }
                    
                    if let order = bookmarkOrderHash[guid] {
                        bk.order = order
                        debugPrint("__ order set \(order) for \((type == 2) ? "folder" : "bookmark")")
                    }
                    relationshipHash[guid] = bk
                }
            }
        } else {
            let errmsg = String(UTF8String: sqlite3_errmsg(db))
            debugPrint("SELECT statement could not be prepared \(errmsg)")
        }
        
        if sqlite3_finalize(results) != SQLITE_OK {
            let error = String.fromCString(sqlite3_errmsg(db))
            debugPrint("Error finalizing prepared statement: \(error)")
        }
        results = nil
        completed(success: true)
    }
    
    private func migrateTabs(completed: (success: Bool) -> Void) {
        let query: String = "SELECT url, title, history FROM tabs ORDER BY last_used"
        var results: COpaquePointer = nil
        
        if sqlite3_prepare_v2(db, query, -1, &results, nil) == SQLITE_OK {
            var order: Int16 = 0
            while sqlite3_step(results) == SQLITE_ROW {
                let url = String.fromCString(UnsafePointer<CChar>(sqlite3_column_text(results, 0))) ?? ""
                let title = String.fromCString(UnsafePointer<CChar>(sqlite3_column_text(results, 1))) ?? ""
                let history = String.fromCString(UnsafePointer<CChar>(sqlite3_column_text(results, 2))) ?? ""
                let historyData = history.stringByReplacingOccurrencesOfString("[", withString: "").stringByReplacingOccurrencesOfString("]", withString: "").stringByReplacingOccurrencesOfString("\"", withString: "").stringByReplacingOccurrencesOfString("\\", withString: "")
                let historyList: [String] = historyData.characters.split{$0 == ","}.map(String.init)
                let tab = SavedTab(id: TabMO.freshTab(), title: title, url: url, isSelected: false, order: order, screenshot: nil, history: historyList, historyIndex: Int16(historyList.count-1))
                
                debugPrint("History restored [\(historyList)]")
                
                TabMO.add(tab, context: DataController.moc)
                order = order + 1
            }
            DataController.saveContext()
        } else {
            debugPrint("SELECT statement could not be prepared")
        }
        
        if sqlite3_finalize(results) != SQLITE_OK {
            let error = String.fromCString(sqlite3_errmsg(db))
            debugPrint("Error finalizing prepared statement: \(error)")
        }
        results = nil
        completed(success: true)
    }
    
    private func removeOldDb(completed: (success: Bool) -> Void) {
        do {
            let documentDirectory = NSURL(fileURLWithPath: self.files.rootPath as String)
            let originPath = documentDirectory.URLByAppendingPathComponent("browser.db")
            let destinationPath = documentDirectory.URLByAppendingPathComponent("old-browser.db")
            try NSFileManager.defaultManager().moveItemAtURL(originPath!, toURL: destinationPath!)
            completed(success: true)
        } catch let error as NSError {
            debugPrint("Cannot clear profile data: \(error)")
            completed(success: false)
        }
    }
    
    private func checkCompleted() {
        var completedAllCalls = true
        for (_, value) in completedCalls {
            if value == false {
                completedAllCalls = false
                break
            }
        }
        
        // All migrations completed, delete the db.
        if completedAllCalls {
            removeOldDb { (success) in
                debugPrint("Delete old database... \(success ? "Done" : "Failed")")
                if let callback = self.completedCallback {
                    callback(success: success)
                }
            }
        }
    }
}
