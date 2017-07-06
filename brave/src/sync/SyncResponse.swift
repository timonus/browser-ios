/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import SwiftyJSON

// TODO: Make follow API convetion (e.g. super generic names)
// TODO: Remove public declarations

typealias SyncDefaultResponseType = SyncRecord
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
    // TODO: rename this property
    public var rootElements: JSON? // arg2
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
        rootElements = json?[SerializationKeys.arg2]
        
        message = json?[SerializationKeys.message].asString
        arg1 = json?[SerializationKeys.arg1].asString
        lastFetchedTimestamp = json?[SerializationKeys.arg3].asInt
        isTruncated = json?[SerializationKeys.arg4].asBool
    }
}
