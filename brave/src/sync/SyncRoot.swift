/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import SwiftyJSON

public final class SyncRoot {
    
    // MARK: Declaration for string constants to be used to decode and also serialize.
    fileprivate struct SerializationKeys {
        static let objectId = "objectId"
        static let deviceId = "deviceId"
        static let action = "action"
        static let bookmark = "bookmark"
        static let objectData = "objectData"
    }
    
    // MARK: Properties
    public var objectId: [Int]?
    public var deviceId: [Int]?
    public var action: Int?
    public var bookmark: SyncBookmark?
    public var objectData: String?
    
    public convenience init() {
        self.init(json: nil)
    }
    
    /// Initiates the instance based on the object.
    ///
    /// - parameter object: The object of either Dictionary or Array kind that was passed.
    /// - returns: An initialized instance of the class.
    public convenience init(object: [String: AnyObject]) {
        self.init(json: JSON(object))
    }
    
    convenience init(bookmark bm: Bookmark?, deviceId: [Int]?, action: Int?) {
        self.init(json: nil)
        
        let unixCreated = Int((bm?.created?.timeIntervalSince1970 ?? 0) * 1000)
        let unixAccessed = Int((bm?.lastVisited?.timeIntervalSince1970 ?? 0) * 1000)
        
        let site = SyncSite()
        site.title = bm?.title
        site.customTitle = bm?.customTitle
        site.location = bm?.url
        site.creationTime = unixCreated
        site.lastAccessedTime = unixAccessed
        // TODO: Does this work?
        site.favicon = bm?.domain?.favicon?.url
        
        let bookmark = SyncBookmark()
        bookmark.isFolder = bm?.isFolder
        bookmark.parentFolderObjectId = bm?.syncParentUUID
        bookmark.site = site
        
        self.objectId = bm?.syncUUID
        self.deviceId = deviceId
        self.action = action
        self.objectData = SyncRecordType.bookmark.rawValue
        self.bookmark = bookmark
    }
    
    /// Initiates the instance based on the JSON that was passed.
    ///
    /// - parameter json: JSON object from SwiftyJSON.
    public required init(json: JSON?) {
        // objectId can come in two different formats
        if let items = json?[SerializationKeys.objectId].array { objectId = items.map { $0.intValue } }
        if let items = json?[SerializationKeys.deviceId].array { deviceId = items.map { $0.intValue } }
        action = json?[SerializationKeys.action].int
        bookmark = SyncBookmark(json: json?[SerializationKeys.bookmark])
        objectData = json?[SerializationKeys.objectData].string
    }
    
    /// Generates description of the object in the form of a NSDictionary.
    ///
    /// - returns: A Key value pair containing all valid values in the object.
    public func dictionaryRepresentation() -> [String: AnyObject] {
        var dictionary: [String: AnyObject] = [:]
        // Override to use string value instead of array, to be uniform to CD
        if let value = objectId { dictionary[SerializationKeys.objectId] = value as AnyObject }
        if let value = deviceId { dictionary[SerializationKeys.deviceId] = value as AnyObject }
        if let value = action { dictionary[SerializationKeys.action] = value as AnyObject }
        if let value = bookmark { dictionary[SerializationKeys.bookmark] = value.dictionaryRepresentation() as AnyObject }
        if let value = objectData { dictionary[SerializationKeys.objectData] = value as AnyObject }
        return dictionary
    }
}

extension SyncRoot {
    static func syncObject(_ rootJSON: [JSON]) -> [SyncRoot]? {
        return rootJSON.map { SyncRoot(json: $0) }
    }
    
    static func syncObject(_ data: [[String: AnyObject]]) -> [SyncRoot]? {
        return data.map { SyncRoot(object: $0) }
    }
}
