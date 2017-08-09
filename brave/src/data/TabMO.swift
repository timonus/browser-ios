/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import CoreData
import Foundation

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

    var screenshotImage: UIImage?

    override func awakeFromInsert() {
        super.awakeFromInsert()

        if let data = screenshot {
            screenshotImage = UIImage(data: data)
        }
    }

    static func entity(_ context: NSManagedObjectContext) -> NSEntityDescription {
        return NSEntityDescription.entity(forEntityName: "TabMO", in: context)!
    }
    
    class func freshTab() -> String {
        let context = DataController.shared.mainThreadContext
        let tab = TabMO(entity: TabMO.entity(context), insertInto: context)
        // TODO: replace with logic to create sync uuid then buble up new uuid to browser.
        tab.syncUUID = UUID().uuidString
        DataController.saveContext(context: context)
        return tab.syncUUID!
    }

    class func add(_ tabInfo: SavedTab, context: NSManagedObjectContext) -> TabMO? {
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
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
        do {
            return try context.fetch(fetchRequest) as? [TabMO] ?? []
        } catch {
            let fetchError = error as NSError
            print(fetchError)
        }
        return []
    }
    
    class func getByID(_ id: String, context: NSManagedObjectContext) -> TabMO? {
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
    
    class func removeTab(_ id: String) {
        let context = DataController.shared.mainThreadContext
        if let tab: TabMO = getByID(id, context: context) {
            context.delete(tab)
            DataController.saveContext(context: context)
        }
    }
    
    class func preserveTab(tab: Browser) {
        guard let tabManager = getApp().tabManager else {
            return
        }
        
        if tab.isPrivate || tab.lastRequest?.url?.absoluteString == nil || tab.tabID == nil {
            return
        }
        
        // Ignore session restore data.
        if let url = tab.lastRequest?.url?.absoluteString, url.contains("localhost") {
            debugPrint(url)
            return
        }
        
        var order = 0
        for t in tabManager.tabs.internalTabList {
            if t === tab { break }
            order += 1
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
        if let id = tab.tabID {
            let data = SavedTab(id, tab.title ?? tab.lastRequest!.url!.absoluteString, tab.lastRequest!.url!.absoluteString, tabManager.selectedTab === tab, Int16(order), tab.screenshot.image, urls, Int16(currentPage))
            let context = DataController.shared.workerContext
            context.perform {
                _ = TabMO.add(data, context: context)
                DataController.saveContext(context: context)
            }
        }
    }
}

