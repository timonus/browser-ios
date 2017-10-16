/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import CoreData
import Foundation
import FastImageCache
import Shared

typealias SavedTab = (id: String, title: String, url: String, isSelected: Bool, order: Int16, screenshot: UIImage?, history: [String], historyIndex: Int16)

class TabMO: NSManagedObject {
    
    @NSManaged var title: String?
    @NSManaged var url: String?
    @NSManaged var syncUUID: String?
    @NSManaged var order: Int16
    @NSManaged var urlHistorySnapshot: NSArray? // array of strings for urls
    @NSManaged var urlHistoryCurrentIndex: Int16
    @NSManaged var screenshot: Data?
    @NSManaged var isSelected: Bool
    @NSManaged var isClosed: Bool
    @NSManaged var isPrivate: Bool
    
    var imageUrl: URL? {
        if let objectId = self.syncUUID, let url = URL(string: "https://imagecache.mo/\(objectId).png") {
            return url
        }
        return nil
    }

    override func awakeFromInsert() {
        super.awakeFromInsert()
    }
    
    override func prepareForDeletion() {
        super.prepareForDeletion()
        
        // Remove cached image
        if let url = imageUrl, !PrivateBrowsing.singleton.isOn {
            ImageCache.shared.remove(url, type: .portrait)
        }
    }

    static func entity(_ context: NSManagedObjectContext) -> NSEntityDescription {
        return NSEntityDescription.entity(forEntityName: "TabMO", in: context)!
    }
    
    class func freshTab(_ context: NSManagedObjectContext = DataController.shared.mainThreadContext) -> TabMO {
        let tab = TabMO(entity: TabMO.entity(context), insertInto: context)
        // TODO: replace with logic to create sync uuid then buble up new uuid to browser.
        tab.syncUUID = UUID().uuidString
        tab.title = Strings.New_Tab
        tab.isPrivate = PrivateBrowsing.singleton.isOn
        DataController.saveContext(context: context)
        return tab
    }

    @discardableResult class func add(_ tabInfo: SavedTab, context: NSManagedObjectContext = DataController.shared.mainThreadContext) -> TabMO? {
        let tab: TabMO? = getByID(tabInfo.id, context: context)
        if tab == nil {
            return nil
        }
        if let s = tabInfo.screenshot {
            tab?.screenshot = UIImageJPEGRepresentation(s, 1)
        }
        tab?.url = tabInfo.url
        tab?.order = tabInfo.order
        tab?.title = tabInfo.title
        tab?.urlHistorySnapshot = tabInfo.history as NSArray
        tab?.urlHistoryCurrentIndex = tabInfo.historyIndex
        tab?.isSelected = tabInfo.isSelected
        return tab!
    }

    class func getAll() -> [TabMO] {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>()
        let context = DataController.shared.mainThreadContext
        
        fetchRequest.entity = TabMO.entity(context)
        fetchRequest.predicate = NSPredicate(format: "isPrivate == false OR isPrivate == nil")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
        do {
            return try context.fetch(fetchRequest) as? [TabMO] ?? []
        } catch {
            let fetchError = error as NSError
            print(fetchError)
        }
        return []
    }
    
    class func clearAllPrivate() {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>()
        let context = DataController.shared.mainThreadContext
        
        fetchRequest.entity = TabMO.entity(context)
        fetchRequest.predicate = NSPredicate(format: "isPrivate == true")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
        do {
            let results = try context.fetch(fetchRequest) as? [TabMO] ?? []
            for tab in results {
                DataController.remove(object: tab)
            }
        } catch {
            let fetchError = error as NSError
            print(fetchError)
        }
    }
    
    class func getByID(_ id: String?, context: NSManagedObjectContext = DataController.shared.mainThreadContext) -> TabMO? {
        guard let id = id else { return nil }
        
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>()
        fetchRequest.entity = TabMO.entity(context)
        fetchRequest.predicate = NSPredicate(format: "syncUUID == %@", id)
        var result: TabMO? = nil
        do {
            let results = try context.fetch(fetchRequest) as? [TabMO]
            if let item = results?.first {
                result = item
            }
        } catch {
            let fetchError = error as NSError
            print(fetchError)
        }
        return result
    }
    
    class func preserveTab(tab: Browser) {
        if let data = savedTabData(tab: tab) {
            let context = DataController.shared.workerContext
            context.perform {
                _ = TabMO.add(data, context: context)
                DataController.saveContext(context: context)
            }
        }
    }
    
    class func savedTabData(tab: Browser, context: NSManagedObjectContext = DataController.shared.mainThreadContext, urlOverride: String? = nil) -> SavedTab? {
        guard let tabManager = getApp().tabManager, let webView = tab.webView, let order = tabManager.indexOfWebView(webView) else { return nil }
        
        // Ignore session restore data.
        if let url = tab.lastRequest?.url?.absoluteString, url.contains("localhost") {
            return nil
        }
        
        var urls = [String]()
        var currentPage = 0
        if let currentItem = tab.webView?.backForwardList.currentItem {
            // Freshly created web views won't have any history entries at all.
            let backList = tab.webView?.backForwardList.backList ?? []
            let forwardList = tab.webView?.backForwardList.forwardList ?? []
            urls += (backList + [currentItem] + forwardList).map { $0.URL.absoluteString }
            currentPage = -forwardList.count
        }
        if let id = TabMO.getByID(tab.tabID, context: context)?.syncUUID {
            let urlTitle = tab.title ?? tab.lastRequest?.url?.absoluteString ?? urlOverride ?? ""
            let data = SavedTab(id, urlTitle, urlOverride ?? tab.lastRequest!.url!.absoluteString, tabManager.selectedTab === tab, Int16(order), nil, urls, Int16(currentPage))
            return data
        }
        
        return nil
    }
}

