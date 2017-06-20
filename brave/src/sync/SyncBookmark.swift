/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import SwiftyJSON

public final class SyncBookmark {
    
    // MARK: Declaration for string constants to be used to decode and also serialize.
    fileprivate struct SerializationKeys {
        static let isFolder = "isFolder"
        static let parentFolderObjectId = "parentFolderObjectId"
        static let site = "site"
    }
    
    // MARK: Properties
    public var isFolder: Bool? = false
    public var parentFolderObjectId: [Int]?
    public var site: SyncSite?
    
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
        isFolder = json?[SerializationKeys.isFolder].bool
        if let items = json?[SerializationKeys.parentFolderObjectId].array { parentFolderObjectId = items.map { $0.intValue } }
        site = SyncSite(json: json?[SerializationKeys.site])
    }
    
    /// Generates description of the object in the form of a NSDictionary.
    ///
    /// - returns: A Key value pair containing all valid values in the object.
    public func dictionaryRepresentation() -> [String: AnyObject] {
        var dictionary: [String: AnyObject] = [:]
        dictionary[SerializationKeys.isFolder] = isFolder as AnyObject
        if let value = parentFolderObjectId { dictionary[SerializationKeys.parentFolderObjectId] = value as AnyObject }
        if let value = site { dictionary[SerializationKeys.site] = value.dictionaryRepresentation() as AnyObject }
        return dictionary
    }
    
}
