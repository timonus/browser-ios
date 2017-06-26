/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

extension Error {
    var code: Int { (self as NSError).code }
    var domain: String { (self as NSError).domain }
    var userInfo: [AnyHashable : Any] { (self as NSError).userInfo }
}
