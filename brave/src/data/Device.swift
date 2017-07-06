/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */


import UIKit
import CoreData
import Foundation
import Shared

class Device: NSManagedObject, Syncable {
    
    // Check if this can be nested inside the method
    private static var sharedCurrentDevice: Device?
    
    // Assign on parent model via CD
    @NSManaged var isSynced: Bool
    
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
        let deviceSettings: [SyncDeviceSetting]? = (Device.get(predicate: nil, context: DataController.shared.workerContext()) as? [Device])?.map {
            // Even if no 'real' title, still want it to show up in list
            let title = "\($0.deviceDisplayId ?? "") :: \($0.name ?? "")"
            return SyncDeviceSetting(profile: profile, title: title)
        }
        return deviceSettings
    }
    
    // This should be abstractable
    func asDictionary(deviceId deviceId: [Int]?, action: Int?) -> [String: AnyObject] {
        return SyncDevice(record: self, deviceId: deviceId, action: action).dictionaryRepresentation()
    }
    
    static func add(rootObject root: SyncRecord?, save: Bool, sendToSync: Bool, context: NSManagedObjectContext) -> Syncable? {
        
        // No guard, let bleed through to allow 'empty' devices (e.g. local)
        let root = root as? SyncDevice
        
        var device = Device(entity: Device.entity(context), insertIntoManagedObjectContext: context)
        
        device.created = root?.syncNativeTimestamp ?? NSDate()
        device.syncUUID = root?.objectId ?? Niceware.shared.uniqueSerialBytes(count: 16)
        device.name = root?.name
        
        if save {
            DataController.saveContext(context)
        }
        
        return device
    }
    
    class func add(save save: Bool = false, context: NSManagedObjectContext) -> Device? {
        return add(rootObject: nil, save: save, sendToSync: false, context: context) as? Device
    }
    
    func update(syncRecord record: SyncRecord) {
        guard let device = record as? SyncDevice else { return }
        // TODO: Handle updating
    }
    
    static func currentDevice() -> Device? {
        
        if sharedCurrentDevice == nil {
            // Since we cache this, we want it in a consistent context.
            //  Worker context is constantly changing out, main thread does not.
            let context = DataController.moc
            // Create device
            let predicate = NSPredicate(format: "isCurrentDevice = %@", true)
            // Should only ever be one current device!
            var localDevice: Device? = get(predicate: predicate, context: context)?.first
            
            if localDevice == nil {
                // Create
                localDevice = add(context: context)
                localDevice?.isCurrentDevice = true
                DataController.saveContext(context)
            }
            
            sharedCurrentDevice = localDevice
        }
        return sharedCurrentDevice
    }
    
    class func deleteAll(completionOnMain: ()->()) {
        let context = DataController.shared.workerContext()
        context.performBlock {
            let fetchRequest = NSFetchRequest()
            fetchRequest.entity = Device.entity(context)
            fetchRequest.includesPropertyValues = false
            do {
                let results = try context.executeFetchRequest(fetchRequest)
                for result in results {
                    context.deleteObject(result as! NSManagedObject)
                }
                
            } catch {
                let fetchError = error as NSError
                print(fetchError)
            }

            // Destroy handle to local device instance, otherwise it is locally retained and will throw console errors
            sharedCurrentDevice = nil
            
            DataController.saveContext(context)
        }
    }
    
}
