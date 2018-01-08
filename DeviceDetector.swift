/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

/// Checks what device model is used based on its screen height.
struct DeviceDetector {
    static var iPhone4s: Bool {
        return UIScreen.main.nativeBounds.height == 960
    }
    
    static var iPhoneX: Bool {
        return UIScreen.main.nativeBounds.height == 2436
    }

    static let isIpad = UIDevice.current.userInterfaceIdiom == .pad
}
