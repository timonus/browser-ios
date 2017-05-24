/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */


import UIKit
import CoreData
import Foundation
import Shared

class Device: NSManagedObject, Syncable {
    
    // Check if this can be nested inside the method
    private static var sharedCurrentDevice: Device?
    
    // Assign on parent model via CD
//    @NSManaged var isSynced: Bool
    
    @NSManaged var created: NSDate?
    @NSManaged var isCurrentDevice: Bool
    @NSManaged var deviceDisplayId: String?
    @NSManaged var syncDisplayUUID: String?
    @NSManaged var name: String?

    // Just a facade around the displayId, for easier access and better CD storage
    var deviceId: [Int]? {
        get { return SyncHelpers.syncUUID(fromString: deviceDisplayId) }
        set(value) { deviceDisplayId = SyncHelpers.syncDisplay(fromUUID: value) }
    }
    
    static func entity(context: NSManagedObjectContext) -> NSEntityDescription {
        return NSEntityDescription.entityForName("Device", inManagedObjectContext: context)!
    }
    
    // This should be abstractable
    func asDictionary(deviceId deviceId: [Int]?, action: Int?) -> [String: AnyObject] {
        return SyncDevice(record: self, deviceId: deviceId, action: action).dictionaryRepresentation()
    }
    
    class func add(save save: Bool = false) -> Device? {
        var device = Device(entity: Device.entity(DataController.moc), insertIntoManagedObjectContext: DataController.moc)
        device.syncUUID = Niceware.shared.uniqueSerialBytes(count: 16)
        device.created = NSDate()
        return device
    }
    
    static func currentDevice() -> Device? {
        
        if sharedCurrentDevice == nil {
            // Create device
            let predicate = NSPredicate(format: "isCurrentDevice = %@", true)
            // Should only ever be one current device!
            var localDevice: Device? = get(predicate: predicate)?.first
            
            if localDevice == nil {
                // Create
                localDevice = add()
                localDevice?.isCurrentDevice = true
                DataController.saveContext()
            }
            
            sharedCurrentDevice = localDevice
        }
        return sharedCurrentDevice
    }
    
}
