/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import CoreData
import Foundation

typealias SavedTab = (id: String, title: String, url: String, isSelected: Bool, order: Int16, screenshot: UIImage?, history: [String], historyIndex: Int16)

extension TabManager {
    
    func preserveTabs() {
        print("preserveTabs()")
        var _tabs = [SavedTab]()
        var i = 0
        for tab in tabs.internalTabList {
            if tab.isPrivate || tab.url?.absoluteString == nil || tab.tabID == nil {
                continue
            }
            
            // Ignore session restore data.
            if let url = tab.url?.absoluteString {
                if url.contains("localhost") {
                    continue
                }
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
                let data = SavedTab(id, tab.title ?? "", tab.url!.absoluteString, self.selectedTab === tab, Int16(i), tab.screenshot.image, urls, Int16(currentPage))
                _tabs.append(data)
                i += 1
            }
        }

        let context = DataController.shared.workerContext()
        context.perform {
            for t in _tabs {
                TabMO.add(t, context: context)
            }
            DataController.saveContext(context)
        }
    }

    func restoreTabs() {
//        struct RunOnceAtStartup { static var token: Int = 0 }
//        dispatch_once(&RunOnceAtStartup.token, restoreTabsInternal)
    }

    fileprivate func restoreTabsInternal() {
        var tabToSelect: Browser?
        let savedTabs = TabMO.getAll()
        for savedTab in savedTabs {
            if savedTab.url == nil {
                if let id = savedTab.syncUUID {
                    TabMO.removeTab(id)
                }
                continue
            }
            
            guard let tab = addTab(nil, configuration: nil, zombie: true, id: savedTab.syncUUID) else { return }
            
            debugPrint(savedTab)
            
            tab.setScreenshot(savedTab.screenshotImage)
            if savedTab.isSelected {
                tabToSelect = tab
            }
            tab.lastTitle = savedTab.title
            if let w = tab.webView, let history = savedTab.urlHistorySnapshot as? [String], let tabID = savedTab.syncUUID {
                let data = SavedTab(id: tabID, title: savedTab.title ?? "", url: savedTab.url ?? "", isSelected: savedTab.isSelected, order: savedTab.order, screenshot: nil, history: history, historyIndex: savedTab.urlHistoryCurrentIndex)
                tab.restore(w, restorationData: data)
            }
        }
        if tabToSelect == nil {
            tabToSelect = tabs.displayedTabsForCurrentPrivateMode.first
        }

        // Only tell our delegates that we restored tabs if we actually restored a tab(s)
        // Base this off of the actual, physical tabs, not what was stored in CD, as we could have edited removed broken CD records
        if tabCount > 0 {
            delegates.forEach { $0.value?.tabManagerDidRestoreTabs(self) }
        } else {
            tabToSelect = addTab()
        }

        if let tab = tabToSelect {
            selectTab(tab)
        }
    }
}

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
        let context = DataController.moc
        let tab = TabMO(entity: TabMO.entity(context), insertInto: context)
        // TODO: replace with logic to create sync uuid then buble up new uuid to browser.
        tab.syncUUID = UUID().uuidString
        DataController.saveContext(context)
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
        fetchRequest.entity = TabMO.entity(DataController.moc)
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "order", ascending: true)]
        do {
            return try DataController.moc.fetch(fetchRequest) as? [TabMO] ?? []
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
        if let tab: TabMO = getByID(id, context: DataController.moc) {
            DataController.moc.delete(tab)
            DataController.saveContext()
        }
    }
}
