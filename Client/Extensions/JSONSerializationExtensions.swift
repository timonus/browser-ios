/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */


import Foundation

extension NSJSONSerialization {
    
    class func swiftObject(withJSON json: AnyObject?) -> [String: AnyObject]? {
        
        guard let jsonData = json?.dataUsingEncoding(NSUTF8StringEncoding) else  {
            return nil
        }
        
        guard let nativeObject = try? NSJSONSerialization.JSONObjectWithData(jsonData, options: []) as? [String: AnyObject] else {
            return nil
        }
        
        return nativeObject
    }
    
    class func jsObject(withNative native: AnyObject?, escaped: Bool = false) -> String? {
        
        guard let native = native, let data = try? NSJSONSerialization.dataWithJSONObject(native, options: NSJSONWritingOptions(rawValue: 0)) else {
            return nil
        }
        
        // Convert to string of JSON data, encode " for JSON to JS conversion
        var encoded = String(data: data, encoding: NSUTF8StringEncoding)
        
        if escaped {
            encoded = encoded?.stringByReplacingOccurrencesOfString("\"", withString: "\\\"")
        }
        
        encoded = encoded?.stringByReplacingOccurrencesOfString("\"null\"", withString: "null")
        
        return encoded
    }
}
