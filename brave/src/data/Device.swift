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
    
    class func deviceSettings(profile profile: Profile) -> [SyncDeviceSetting]? {
        // Building settings off of device objects
        let deviceSettings: [SyncDeviceSetting]? = (Device.get2(predicate: nil) as? [Device])?.map {
            // Even if no 'real' title, still want it to show up in list
            return SyncDeviceSetting(profile: profile, title: $0.name ?? "")
        }
        return deviceSettings
    }
    
    // This should be abstractable
    func asDictionary(deviceId deviceId: [Int]?, action: Int?) -> [String: AnyObject] {
        return SyncDevice(record: self, deviceId: deviceId, action: action).dictionaryRepresentation()
    }
    
    static func add(rootObject root: SyncRecord?, save: Bool, sendToSync: Bool) -> Syncable? {
        guard let root = root as? SyncDevice else { return nil }
        var device = Device(entity: Device.entity(DataController.moc), insertIntoManagedObjectContext: DataController.moc)
        
        device.created = root.syncNativeTimestamp ?? NSDate()
        device.syncUUID = root.objectId ?? Niceware.shared.uniqueSerialBytes(count: 16)
        device.name = root.name
        
        return device
    }
    
    class func add(save save: Bool = false) -> Device? {
        return add(rootObject: nil, save: save, sendToSync: false) as? Device
    }
    
    func update(syncRecord record: SyncRecord) {
        guard let device = record as? SyncDevice else { return }
        // TODO: Handle updating
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
