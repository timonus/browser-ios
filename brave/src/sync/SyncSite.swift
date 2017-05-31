/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared

public final class SyncSite {
    
    // MARK: Declaration for string constants to be used to decode and also serialize.
    private struct SerializationKeys {
        static let customTitle = "customTitle"
        static let title = "title"
        static let favicon = "favicon"
        static let location = "location"
        static let creationTime = "creationTime"
        static let lastAccessedTime = "lastAccessedTime"
    }
    
    // MARK: Properties
    public var customTitle: String?
    public var title: String?
    public var favicon: String?
    public var location: String?
    public var creationTime: Int?
    public var lastAccessedTime: Int?
    
    public var creationNativeDate: NSDate? {
        return NSDate.fromTimestamp(Timestamp(creationTime ?? 0))
    }
    
    public var lastAccessedNativeDate: NSDate? {
        return NSDate.fromTimestamp(Timestamp(lastAccessedTime ?? 0))
    }
    
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
    
    /// Initiates the instance based on the JSON that was passed.
    ///
    /// - parameter json: JSON object from SwiftyJSON.
    public required init(json: JSON?) {
        customTitle = json?[SerializationKeys.customTitle].asString
        title = json?[SerializationKeys.title].asString
        favicon = json?[SerializationKeys.favicon].asString
        location = json?[SerializationKeys.location].asString
        creationTime = json?[SerializationKeys.creationTime].asInt
        lastAccessedTime = json?[SerializationKeys.lastAccessedTime].asInt
    }
    
    /// Generates description of the object in the form of a NSDictionary.
    ///
    /// - returns: A Key value pair containing all valid values in the object.
    public func dictionaryRepresentation() -> [String: AnyObject] {
        var dictionary: [String: AnyObject] = [:]
        if let value = customTitle { dictionary[SerializationKeys.customTitle] = value }
        if let value = title { dictionary[SerializationKeys.title] = value }
        if let value = favicon { dictionary[SerializationKeys.favicon] = value }
        if let value = location { dictionary[SerializationKeys.location] = value }
        if let value = creationTime { dictionary[SerializationKeys.creationTime] = value }
        if let value = lastAccessedTime { dictionary[SerializationKeys.lastAccessedTime] = value }
        return dictionary
    }
    
}
