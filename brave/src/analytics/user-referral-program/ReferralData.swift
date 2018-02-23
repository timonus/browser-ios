/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import SwiftyJSON

private let log = Logger.browserLogger

struct ReferralData {
    struct PrefKeys {
        static let downloadId = "downloadIdPrefsKey"
        static let referralCode = "referralCodePrefsKey"
        static let referralCodeDeleteDate = "referralCodeDeleteTimePrefsKey"
    }

    let downloadId: String
    let referralCode: String

    init(downloadId: String, code: String) {
        self.downloadId = downloadId
        self.referralCode = code
    }

    init?(json: JSON) {
        guard let downloadId = json["download_id"].string, let code = json["referral_code"].string else {
            log.error("Failed to unwrap json to Referral struct.")
            return nil
        }

        self.downloadId = downloadId
        self.referralCode = code
    }
}
