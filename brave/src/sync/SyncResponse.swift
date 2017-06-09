/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import SwiftyJSON

public final class SyncResponse {
    
    // MARK: Declaration for string constants to be used to decode and also serialize.
    fileprivate struct SerializationKeys {
        static let arg2 = "arg2"
        static let message = "message"
        static let arg1 = "arg1"
        static let arg3 = "arg3"
        static let arg4 = "arg4" // isTruncated
    }
    
    // MARK: Properties
    public var rootElements: [SyncRoot]? // arg2
    public var message: String?
    public var arg1: String?
    public var lastFetchedTimestamp: Int? // arg3
    public var isTruncated: Bool? // arg4
    
    /// Initiates the instance based on the object.
    ///
    /// - parameter object: The object of either Dictionary or Array kind that was passed.
    /// - returns: An initialized instance of the class.
    public convenience init(object: AnyObject) {
        self.init(json: JSON(string: object as? String ?? ""))
    }
    
    /// Initiates the instance based on the JSON that was passed.
    ///
    /// - parameter json: JSON object from SwiftyJSON.
    public required init(json: JSON?) {
        if let items = json?[SerializationKeys.arg2].asArray { rootElements = items.map { SyncRoot(json: $0) } }
        message = json?[SerializationKeys.message].asString
        arg1 = json?[SerializationKeys.arg1].asString
        lastFetchedTimestamp = json?[SerializationKeys.arg3].asInt
        isTruncated = json?[SerializationKeys.arg4].asBool
    }
    
    /// Generates description of the object in the form of a NSDictionary.
    ///
    /// - returns: A Key value pair containing all valid values in the object.
    public func dictionaryRepresentation() -> [String: Any] {
        var dictionary: [String: Any] = [:]
        if let value = rootElements { dictionary[SerializationKeys.arg2] = value.map { $0.dictionaryRepresentation() } }
        if let value = message { dictionary[SerializationKeys.message] = value }
        if let value = arg1 { dictionary[SerializationKeys.arg1] = value }
        if let value = lastFetchedTimestamp { dictionary[SerializationKeys.arg3] = value }
        if let value = isTruncated { dictionary[SerializationKeys.arg4] = value }
        return dictionary
    }
    
}
