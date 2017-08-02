/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import CoreData
import Shared

// After testing many different MOC stacks, it became aparent that main thread context
// should contain no worker children since it will eventually propogate up and block the main
// thread on changes or saves

// Attempting to have the main thread MOC as the sole child of a private MOC seemed optimal 
// (and is recommended path via WWDC Apple CD video), but any associated work on mainMOC
// does not re-merge back into it self well from parent (background) context (tons of issues)
// This should be re-attempted when dropping iOS9, using some of the newer CD APIs for 10+
// (e.g. automaticallyMergesChangesFromParent = true, may allow a complete removal of `merge`)
// StoreCoordinator > writeMOC > mainMOC

// That being said, writeMOC (background) has two parallel children
// One being a mainThreadMOC, and the other a workerMOC. Since contexts seem to have significant
// issues merging their own changes from the parent save, they must merge changes directly from their
// parallel. This seems to work quite well and appears heavily reliable during heavy background work.
// StoreCoordinator > writeMOC (private, no direct work) > mainMOC && workerMOC

// Previoulsy attempted stack which had significant impact on main thread saves
// Follow the stack design from http://floriankugler.com/2013/04/02/the-concurrent-core-data-stack/

class DataController: NSObject {
    static let shared = DataController()
    
    func merge(notification: Notification) {

        guard let sender = notification.object as? NSManagedObjectContext else {
            fatalError("Merge notification must be from a managed object context")
        }
        
        if sender == self.writeContext {
            fatalError("Changes should not be merged from write context")
        }
        
        // Async, no issues with merging changes from 'self' context
        
        if sender == self.mainThreadContext {
            self.workerContext.perform {
                self.workerContext.mergeChanges(fromContextDidSave: notification)
            }
        } else if sender == self.workerContext {
            self.mainThreadContext.perform {
                self.mainThreadContext.mergeChanges(fromContextDidSave: notification)
                
                guard let info = notification.userInfo else {
                    return
                }
                
                let totalChanges = ["inserted", "updated", "deleted"].flatMap({ (info[$0] as? NSSet)?.count }).reduce(0, +)
                let largeChangeCount = 75
                
                // If there are more than `largeChangeCount`, better to send notification and allow UI to perform better refresh mechanisms
                // (e.g. refresh full table, rather than performing tons of individual table cell operations)
                if totalChanges > largeChangeCount {
                    NotificationCenter.default.post(name: NotificationMainThreadContextSignificantlyChanged, object: self, userInfo: nil)
                }
            }
        }
    }
    
    fileprivate lazy var writeContext: NSManagedObjectContext = {
        let write = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        write.persistentStoreCoordinator = self.persistentStoreCoordinator
        write.undoManager = nil
        write.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        return write
    }()
    
    lazy var workerContext: NSManagedObjectContext = {
        let worker = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        worker.undoManager = nil
        worker.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        worker.parent = self.writeContext
        
        NotificationCenter.default.addObserver(self, selector: #selector(merge(notification:)), name: NSNotification.Name.NSManagedObjectContextDidSave, object: worker)
        
        return worker
    }()
    
    lazy var mainThreadContext: NSManagedObjectContext = {
        let main = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        main.undoManager = nil
        main.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        main.parent = self.writeContext
        
        NotificationCenter.default.addObserver(self, selector: #selector(merge(notification:)), name: NSNotification.Name.NSManagedObjectContextDidSave, object: main)
        
        return main
    }()
    
    fileprivate var managedObjectModel: NSManagedObjectModel!
    fileprivate var persistentStoreCoordinator: NSPersistentStoreCoordinator!
    
    fileprivate override init() {
        super.init()

       // TransformerUUID.setValueTransformer(transformer: NSValueTransformer?, forName name: String)

        guard let modelURL = Bundle.main.url(forResource: "Model", withExtension:"momd") else {
            fatalError("Error loading model from bundle")
        }
        guard let mom = NSManagedObjectModel(contentsOf: modelURL) else {
            fatalError("Error initializing mom from: \(modelURL)")
        }
        
        self.managedObjectModel = mom
        self.persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)
        
        let urls = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        if let docURL = urls.last {
            do {
                
                let options: [String: AnyObject] = [
                    NSMigratePersistentStoresAutomaticallyOption: true as AnyObject,
                    NSInferMappingModelAutomaticallyOption: true as AnyObject,
                    NSPersistentStoreFileProtectionKey : FileProtectionType.complete as AnyObject
                ]
                
                // Old store URL from old beta, can be removed at some point (thorough migration testing though)
                var storeURL = docURL.appendingPathComponent("Brave.sqlite")
                try self.persistentStoreCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: options)
                
                storeURL = docURL.appendingPathComponent("Model.sqlite")
                try self.persistentStoreCoordinator.addPersistentStore(ofType: NSSQLiteStoreType, configurationName: nil, at: storeURL, options: options)
            }
            catch {
                fatalError("Error migrating store: \(error)")
            }
        }

        // Setup contexts
        _ = mainThreadContext
    }

    static func saveContext(context: NSManagedObjectContext?) {
        guard let context = context else {
            print("No context on save")
            return
        }

        if context.hasChanges {
            
            context.perform {
                do {
                    try context.save()
                    
                    // Just recall this method
                    let writter = DataController.shared.writeContext
                    if writter.hasChanges {
                        writter.perform {
                            try? writter.save()
                        }
                    }
                    
                } catch {
                    fatalError("Error saving DB: \(error)")
                }
            }
        }
    }
}
