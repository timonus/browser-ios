//
//  AutomaticProperties.swift
//  Mixpanel
//
//  Created by Yarden Eitan on 7/8/16.
//  Copyright © 2016 Mixpanel. All rights reserved.
//

import Foundation

#if !os(OSX)
import UIKit
#else
import Cocoa
#endif // os(OSX)

#if os(iOS)
import CoreTelephony
#endif // os(iOS

class AutomaticProperties {


    static var properties: InternalProperties = {
        objc_sync_enter(AutomaticProperties.self); defer { objc_sync_exit(AutomaticProperties.self) }
        var p = InternalProperties()
        // No data
        return p
    }()

    static var peopleProperties: InternalProperties = {
        objc_sync_enter(AutomaticProperties.self); defer { objc_sync_exit(AutomaticProperties.self) }
        var p = InternalProperties()
        // No data
        return p
    }()
}
