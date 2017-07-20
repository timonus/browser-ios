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
        self.mainThreadContext.perform {
            self.mainThreadContext.mergeChanges(fromContextDidSave: notification)
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
    
    
    lazy var mainThreadContext: NSManagedObjectContext = {
        let main = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        main.undoManager = nil
        main.mergePolicy = NSMergeByPropertyStoreTrumpMergePolicy
        main.parent = self.workerContext
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
        guard let context = context  else {
            print("No context on save")
            return
        }

        if context.hasChanges {
            context.perform {
                do {
                    try context.save()
                    
                    if context == DataController.shared.mainThreadContext {
                        // Changes have been merged to worker context, save this to the store
                        self.saveContext(context: DataController.shared.workerContext)
                        
                    }
                } catch {
                    fatalError("Error saving DB: \(error)")
                }
            }
        }
    }
}
