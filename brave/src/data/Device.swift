/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */


import UIKit
import CoreData
import Foundation
import Shared

class Device: NSManagedObject, Syncable {
    @NSManaged var created: NSDate?
    @NSManaged var deviceDisplayId: String?
    @NSManaged var syncDisplayUUID: String?
    @NSManaged var name: String?

    // Just a facade around the displayId, for easier access and better CD storage
    var deviceId: [Int]? {
        get { return syncUUID(fromString: deviceDisplayId) }
        set(value) { deviceDisplayId = Bookmark.syncDisplay(fromUUID: value) }
    }
    
    func asDictionary(deviceId deviceId: [Int]?, action: Int?) -> [String: AnyObject] {
        // TODO:
        return ["": ""]
    }
    
}
