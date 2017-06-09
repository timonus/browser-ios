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

    private var writeMOC: NSManagedObjectContext?
    private var mainThreadMOC: NSManagedObjectContext?
    private var workerMOC: NSManagedObjectContext? = nil

    static var moc: NSManagedObjectContext {
        get {
            guard let moc = DataController.shared.mainThreadMOC else {
                fatalError("DataController: Access to .moc contained nil value. A db connection has not yet been instantiated.")
            }

            if !NSThread.isMainThread() {
                fatalError("DataController: Access to .moc must be on main thread.")
            }
            
            return moc
        }
    }
    
    private var managedObjectModel: NSManagedObjectModel!
    private var persistentStoreCoordinator: NSPersistentStoreCoordinator!
    
    private override init() {
        super.init()

       // TransformerUUID.setValueTransformer(transformer: NSValueTransformer?, forName name: String)

        guard let modelURL = NSBundle.mainBundle().URLForResource("Model", withExtension:"momd") else {
            fatalError("Error loading model from bundle")
        }
        guard let mom = NSManagedObjectModel(contentsOfURL: modelURL) else {
            fatalError("Error initializing mom from: \(modelURL)")
        }
        
        self.managedObjectModel = mom
        self.persistentStoreCoordinator = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)
        
        let urls = NSFileManager.defaultManager().URLsForDirectory(.DocumentDirectory, inDomains: .UserDomainMask)
        if let docURL = urls.last {
            do {
                
                let options: [String: AnyObject] = [
                    NSMigratePersistentStoresAutomaticallyOption: true,
                    NSInferMappingModelAutomaticallyOption: true,
                    NSPersistentStoreFileProtectionKey : NSFileProtectionComplete
                ]
                
                // Old store URL from old beta, can be removed at some point (thorough migration testing though)
                var storeURL = docURL.URLByAppendingPathComponent("Brave.sqlite")
                try self.persistentStoreCoordinator.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: storeURL, options: options)
                
                storeURL = docURL.URLByAppendingPathComponent("Model.sqlite")
                try self.persistentStoreCoordinator.addPersistentStoreWithType(NSSQLiteStoreType, configuration: nil, URL: storeURL, options: options)
            }
            catch {
                fatalError("Error migrating store: \(error)")
            }
        }

        mainThreadContext()
    }

    private func writeContext() -> NSManagedObjectContext {
        if writeMOC == nil {
            writeMOC = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
            writeMOC?.persistentStoreCoordinator = persistentStoreCoordinator
            writeMOC?.undoManager = nil
            writeMOC?.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        }
        return writeMOC!
    }

    func workerContext() -> NSManagedObjectContext {
        if workerMOC == nil {
            workerMOC = NSManagedObjectContext(concurrencyType: .PrivateQueueConcurrencyType)
            workerMOC!.parentContext = mainThreadContext()
            workerMOC!.undoManager = nil
            workerMOC!.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        }
        return workerMOC!
    }

    private func mainThreadContext() -> NSManagedObjectContext {
        if mainThreadMOC != nil {
            return mainThreadMOC!
        }

        mainThreadMOC = NSManagedObjectContext(concurrencyType: .MainQueueConcurrencyType)
        mainThreadMOC?.undoManager = nil
        mainThreadMOC?.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        mainThreadMOC?.parentContext = writeContext()
        return mainThreadMOC!
    }

    static func saveContext(context: NSManagedObjectContext? = DataController.moc) {
        guard let context = context  else {
            print("No context on save")
            return
        }
        
        if context === DataController.shared.writeMOC {
            print("Do not use with the write moc, this save is handled internally here.")
            return
        }

        if context.hasChanges {
            do {
                try context.save()

                if context === DataController.shared.mainThreadMOC {
                    // Data has changed on main MOC. Let the existing worker threads continue as-is,
                    // but create a new workerMOC (which is a copy of main MOC data) for next time a worker is used.
                    // By design we only merge changes 'up' the stack from child-to-parent.
                    DataController.shared.workerMOC = nil
                    DataController.shared.workerMOC = DataController.shared.workerContext()

                    // ensure event loop complete, so that child-to-parent moc merge is complete (no cost, and docs are not clear on whether this is required)
                    postAsyncToMain(0.1) {
                        DataController.shared.writeMOC!.performBlock {
                            if !DataController.shared.writeMOC!.hasChanges {
                                return
                            }
                            do {
                                try DataController.shared.writeMOC!.save()
                            } catch {
                                fatalError("Error saving DB to disk: \(error)")
                            }
                        }
                    }
                } else {
                    postAsyncToMain(0.1) {
                        DataController.saveContext(DataController.shared.mainThreadMOC!)
                    }
                }
            } catch {
                fatalError("Error saving DB: \(error)")
            }
        }
    }
}
