/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

@objc protocol WebsitePresentable {
    var title: String? { get }
    var url: String? { get }
}

protocol Syncable {
    // Used to enforce CD conformity
    /* @NSManaged */ var syncDisplayUUID: String? { get set }
    /* @NSManaged */ var created: NSDate? { get set}

    
    var syncUUID: [Int]? { get }
    
    func asDictionary(deviceId deviceId: [Int]?, action: Int?) -> [String: AnyObject]
}

extension Syncable {

    // Is conveted to better store in CD
    var syncUUID: [Int]? {
        get { return syncUUID(fromString: syncDisplayUUID) }
        set(value) { syncDisplayUUID = Bookmark.syncDisplay(fromUUID: value) }
    }
    
    // Converters
    
    /// UUID -> DisplayUUID
    internal static func syncDisplay(fromUUID uuid: [Int]?) -> String? {
        return uuid?.map{ $0.description }.joinWithSeparator(",")
    }
    
    /// DisplayUUID -> UUID
    internal func syncUUID(fromString string: String?) -> [Int]? {
        return string?.componentsSeparatedByString(",").map { Int($0) }.flatMap { $0 }
    }
}
