/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import CoreData

@objc protocol WebsitePresentable {
    var title: String? { get }
    var url: String? { get }
}

protocol Syncable {
    // Used to enforce CD conformity
    /* @NSManaged */ var syncDisplayUUID: String? { get set }
    /* @NSManaged */ var created: NSDate? { get set}

    static func entity(context:NSManagedObjectContext) -> NSEntityDescription

    var syncUUID: [Int]? { get }
    
    func asDictionary(deviceId deviceId: [Int]?, action: Int?) -> [String: AnyObject]
    
    func update(syncRecord record: SyncRecord)
    
    static func add(rootObject root: SyncRecord?, save: Bool, sendToSync: Bool) -> Syncable?
}

// ??
extension Syncable where Self: Syncable {
    static func get(syncUUIDs syncUUIDs: [[Int]]?) -> [NSManagedObject]? {
        
        guard let syncUUIDs = syncUUIDs else {
            return nil
        }
        
        // TODO: filter a unique set of syncUUIDs
        
        let searchableUUIDs = syncUUIDs.map { SyncHelpers.syncDisplay(fromUUID: $0) }.flatMap { $0 }
        return get2(predicate: NSPredicate(format: "syncDisplayUUID IN %@", searchableUUIDs ))
    }
    
    static func get2(predicate predicate: NSPredicate?) -> [NSManagedObject]? {
        let fetchRequest = NSFetchRequest()
        
        fetchRequest.entity = Self.entity(DataController.moc)
        fetchRequest.predicate = predicate
        
        do {
            return try DataController.moc.executeFetchRequest(fetchRequest) as? [NSManagedObject]
        } catch {
            let fetchError = error as NSError
            print(fetchError)
        }
        
        return nil
    }
}

//extension Syncable where Self: NSManagedObject {
extension Syncable {
    
    // Is conveted to better store in CD
    var syncUUID: [Int]? { 
        get { return SyncHelpers.syncUUID(fromString: syncDisplayUUID) }
        set(value) { syncDisplayUUID = SyncHelpers.syncDisplay(fromUUID: value) }
    }
    
    // Maybe use 'self'?
    static func get<T: NSManagedObject where T: Syncable>(predicate predicate: NSPredicate?) -> [T]? {
        let fetchRequest = NSFetchRequest()
        
        fetchRequest.entity = T.entity(DataController.moc)
        fetchRequest.predicate = predicate
        
        do {
            return try DataController.moc.executeFetchRequest(fetchRequest) as? [T]
        } catch {
            let fetchError = error as NSError
            print(fetchError)
        }
        
        return nil
    }
}

extension Syncable /* where Self: NSManagedObject */ {
    func remove(save: Bool = true) {
        
        // This is super annoying, and can be fixed in Swift 4, but since objects can't be cast to a class & protocol,
        //  but given extension on Syncable, if this passes the object is both Syncable and an NSManagedObject subclass
        guard let s = self as? NSManagedObject else { return }
        
        // Must happen before, otherwise bookmark is gone
        
        // TODO: Make type dynamic
        Sync.shared.sendSyncRecords(.bookmark, action: .delete, records: [self])
        
        DataController.moc.deleteObject(s)
        if save {
            DataController.saveContext()
        }
    }
}

class SyncHelpers {
    // Converters
    
    /// UUID -> DisplayUUID
    static func syncDisplay(fromUUID uuid: [Int]?) -> String? {
        return uuid?.map{ $0.description }.joinWithSeparator(",")
    }
    
    /// DisplayUUID -> UUID
    static func syncUUID(fromString string: String?) -> [Int]? {
        return string?.componentsSeparatedByString(",").map { Int($0) }.flatMap { $0 }
    }
    
    static func syncUUID(fromJSON json: JSON?) -> [Int]? {
        return json?.asArray?.map { $0.asInt }.flatMap { $0 }
    }
}
