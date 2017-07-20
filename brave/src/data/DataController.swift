/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import CoreData

// Follow the stack design from http://floriankugler.com/2013/04/02/the-concurrent-core-data-stack/
// workerMOC is-child-of mainThreadMOC is-child-of writeMOC
// Data flows up through the stack only (child-to-parent), the bottom being the `writeMOC` which is used only for saving to disk.
//
// Notice no merge notifications are needed using this method.

class DataController: NSObject {
    static let shared = DataController()
    
    func merge(notification: Notification) {
        self.mainThreadMOC?.perform {
            self.mainThreadMOC?.mergeChanges(fromContextDidSave: notification)
        }
    }
    
    lazy var workerContext: NSManagedObjectContext = {
        let worker = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
        worker.persistentStoreCoordinator = self.persistentStoreCoordinator
        worker.undoManager = nil
        worker.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        
        NotificationCenter.default.addObserver(self, selector: #selector(merge(notification:)), name: NSNotification.Name.NSManagedObjectContextDidSave, object: worker)
        
        return worker
    }()
    
    fileprivate var mainThreadMOC: NSManagedObjectContext?
    

//    static var moc: NSManagedObjectContext {
//        get {
//            guard let moc = DataController.shared.mainThreadMOC else {
//                fatalError("DataController: Access to .moc contained nil value. A db connection has not yet been instantiated.")
//            }
//
//            if !Thread.isMainThread {
//                fatalError("DataController: Access to .moc must be on main thread.")
//            }
//            
//            return moc
//        }
//    }
    
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

        _ = mainThreadContext()
    }

    func mainThreadContext() -> NSManagedObjectContext {
        if mainThreadMOC != nil {
            return mainThreadMOC!
        }

        mainThreadMOC = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        mainThreadMOC?.undoManager = nil
        mainThreadMOC?.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        mainThreadMOC?.parent = self.workerContext
        return mainThreadMOC!
    }

    static func saveContext(context: NSManagedObjectContext?) {
        guard let context = context  else {
            print("No context on save")
            return
        }
        
//        if context === DataController.shared.writeContext {
//            print("Do not use with the write moc, this save is handled internally here.")
//            return
//        }
//        
//        if context == DataController.shared.mainThreadMOC && !Thread.isMainThread {
//            // Super bad
//        }

        if context.hasChanges {
            
            context.perform {
                
//            }
            do {
                try context.save()
                
                if context == DataController.shared.mainThreadMOC {
                    
                    // Just recall this method
                    let worker = DataController.shared.workerContext
                    if worker.hasChanges {
                        worker.perform {
                            try? worker.save()
                        }
                    }
                    
                }
                
                // ensure event loop complete, so that child-to-parent moc merge is complete (no cost, and docs are not clear on whether this is required)
//                postAsyncToMain(0.1) {
                
                
//                DataController.shared.writeContext.perform {
//                    if !DataController.shared.writeContext.hasChanges {
//                        return
//                    }
//                    do {
//                        try DataController.shared.writeContext.save()
//                    } catch {
//                        fatalError("Error saving DB to disk: \(error)")
//                    }
//                }
                
                
//                
//                return
//                if context === DataController.shared.mainThreadMOC {
//                    // Data has changed on main MOC. Let the existing worker threads continue as-is,
//                    // but create a new workerMOC (which is a copy of main MOC data) for next time a worker is used.
//                    // By design we only merge changes 'up' the stack from child-to-parent.
//                    let context = DataController.shared.workerContext
//                    DataController.shared.worker = nil
//                    DataController.shared.workerMOC = DataController.shared.workerContext()
//
//
//                } else {
//                    postAsyncToMain(0.1) {
//                        DataController.saveContext(context: DataController.shared.mainThreadMOC!)
//                    }
//                }
            } catch {
                fatalError("Error saving DB: \(error)")
            }
            }
        }
    }
}
