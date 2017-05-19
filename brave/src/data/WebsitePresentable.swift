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
}

//extension Syncable where Self: NSManagedObject {
extension Syncable {
    
    // Is conveted to better store in CD
    var syncUUID: [Int]? { 
        get { return SyncHelpers.syncUUID(fromString: syncDisplayUUID) }
        set(value) { syncDisplayUUID = SyncHelpers.syncDisplay(fromUUID: value) }
    }
    
    static func get<T: NSManagedObject where T: Syncable>(syncUUIDs syncUUIDs: [[Int]]?) -> [T]? {
        
        guard let syncUUIDs = syncUUIDs else {
            return nil
        }
        
        // TODO: filter a unique set of syncUUIDs
        
        let searchableUUIDs = syncUUIDs.map { SyncHelpers.syncDisplay(fromUUID: $0) }.flatMap { $0 }
        return get(predicate: NSPredicate(format: "syncDisplayUUID IN %@", searchableUUIDs ))
    }
    
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
