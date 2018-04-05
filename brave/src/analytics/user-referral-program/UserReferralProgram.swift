/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared

private let log = Logger.browserLogger

class UserReferralProgram {
    private static let hostPlistKey = "URP_HOST"
    private static let apiKeyPlistKey = "API_KEY"

    private static let urpDateCheckPrefsKey = "urpDateCheckPrefsKey"
    private static let urpRetryCountdownPrefsKey = "urpRetryCountdownPrefsKey"

    private static let stagingUrl = "https://laptop-updates-staging.herokuapp.com"

    let service: UrpService
    let prefs: Prefs

    init?() {
        func getPlistString(for key: String) -> String? {
            return Bundle.main.infoDictionary?[key] as? String
        }

        guard let host = getPlistString(for: UserReferralProgram.hostPlistKey),
            let apiKey = getPlistString(for: UserReferralProgram.apiKeyPlistKey), let prefs = getApp().profile?.prefs else {
                log.error("Urp init error, failed to get values from Brave.plist.")
                return nil
        }

        guard let urpService = UrpService(host: host, apiKey: apiKey) else { return nil }

        self.prefs = prefs
        self.service = urpService
    }

    /// Looks for referral and returns its landing page if possible.
    func referralLookup(completion: @escaping (String?) -> ()) {
        UrpLog.log("first run referral lookup")

        service.referralCodeLookup { referral, _ in
            guard let ref = referral else {
                self.getCustomHeaders()
                log.info("No referral code found")
                UrpLog.log("No referral code found")
                return
            }

            if ref.isExtendedUrp() {
                if let headers = ref.customHeaders {
                    self.prefs.setObject(NSKeyedArchiver.archivedData(withRootObject: headers), forKey: CustomHeaderData.prefsKey)
                }

                completion(ref.offerPage)
                UrpLog.log("Extended referral code found, opening landing page: \(ref.offerPage ?? "404")")
                // We do not want to persist referral data for extended URPs
                return
            }

            self.prefs.setString(ref.downloadId, forKey: ReferralData.PrefKeys.downloadId)
            self.prefs.setString(ref.referralCode, forKey: ReferralData.PrefKeys.referralCode)

            UrpLog.log("Found referral: downloadId: \(ref.downloadId), code: \(ref.referralCode)")
            // In case of network errors or getting `isFinalized = false`, we retry the api call.
            self.initRetryPingConnection(numberOfTimes: 30)

            completion(nil)
        }
    }

    private func initRetryPingConnection(numberOfTimes: Int32) {
        let _10minutes: TimeInterval = 10 * 60
        if kIsDevelomentBuild {
            self.prefs.setObject(Date().timeIntervalSince1970 + _10minutes, forKey: UserReferralProgram.urpDateCheckPrefsKey)
        } else {
            let _30daysInSeconds = Double(30 * 24 * 60 * 60)
            // Adding some time offset to be extra safe.
            let offset = Double(1 * 60 * 60)
            let _30daysFromToday = Date().timeIntervalSince1970 + _30daysInSeconds + offset

            self.prefs.setObject(_30daysFromToday, forKey: UserReferralProgram.urpDateCheckPrefsKey)
        }
        self.prefs.setInt(numberOfTimes, forKey: UserReferralProgram.urpRetryCountdownPrefsKey)
    }

    func pingIfEnoughTimePassed() {
        if !DeviceInfo.hasConnectivity() {
            UrpLog.log("No internet connection, not sending update ping.")
            return
        }

        guard let downloadId = prefs.stringForKey(ReferralData.PrefKeys.downloadId) else {
            log.info("Could not retrieve download id model from preferences.")
            UrpLog.log("Update ping, no download id found.")
            return
        }

        guard let checkDate = self.prefs.objectForKey(UserReferralProgram.urpDateCheckPrefsKey) as TimeInterval? else {
            log.error("Could not retrieve check date from preferences.")
            return
        }

        let todayInSeconds = Date().timeIntervalSince1970

        if todayInSeconds <= checkDate {
            log.debug("Not enough time has passed for referral ping.")
            UrpLog.log("Not enough time has passed for referral ping.")
            return
        }

        UrpLog.log("Update ping")
        service.checkIfAuthorizedForGrant(with: downloadId) { initialized, error in
            guard let counter = self.prefs.intForKey(UserReferralProgram.urpRetryCountdownPrefsKey) else {
                log.error("Could not retrieve retry countdown from preferences.")
                return
            }

            var shouldRemoveData = false

            if error == .downloadIdNotFound {
                UrpLog.log("Download id not found on server.")
                shouldRemoveData = true
            }

            if initialized == true {
                UrpLog.log("Got initialized = true from server.")
                shouldRemoveData = true
            }

            // Last retry attempt
            if counter <= 1 {
                UrpLog.log("Last retry and failed to get data from server.")
                shouldRemoveData = true
            }

            if shouldRemoveData {
                UrpLog.log("Removing all referral data from device")
                self.prefs.removeObjectForKey(ReferralData.PrefKeys.downloadId)
                self.prefs.removeObjectForKey(UserReferralProgram.urpDateCheckPrefsKey)
                self.prefs.removeObjectForKey(UserReferralProgram.urpRetryCountdownPrefsKey)
            } else {
                UrpLog.log("Network error or isFinalized returned false, decrementing retry counter and trying again next time.")
                // Decrement counter, next retry happens on next day
                self.prefs.setInt(counter - 1, forKey: UserReferralProgram.urpRetryCountdownPrefsKey)
                let _1dayInSeconds = Double(1 * 24 * 60 * 60)
                self.prefs.setObject(checkDate + _1dayInSeconds, forKey: UserReferralProgram.urpDateCheckPrefsKey)
            }
        }
    }

    /// Returns referral code and sets expiration day for its deletion from DAU pings(if needed).
    class func getReferralCode(prefs: Prefs?) -> String? {
        if let referralCodeDeleteDate = prefs?.objectForKey(ReferralData.PrefKeys.referralCodeDeleteDate) as TimeInterval?,
            Date().timeIntervalSince1970 >= referralCodeDeleteDate {
            prefs?.removeObjectForKey(ReferralData.PrefKeys.referralCode)
            prefs?.removeObjectForKey(ReferralData.PrefKeys.referralCodeDeleteDate)
            UrpLog.log("Enough time has passed, removing referral code data")
            return nil
        } else if let referralCode = prefs?.stringForKey(ReferralData.PrefKeys.referralCode) {
            // Appending ref code to dau ping if user used installed the app via user referral program.
            if prefs?.objectForKey(ReferralData.PrefKeys.referralCodeDeleteDate) as TimeInterval? == nil {
                UrpLog.log("Setting new date for deleting referral code.")
                let timeToDelete = kIsDevelomentBuild ? TimeInterval(20 * 60) : TimeInterval(90 * 24 * 60 * 60)

                prefs?.setObject(Date().timeIntervalSince1970 + timeToDelete, forKey: ReferralData.PrefKeys.referralCodeDeleteDate)
            }

            return referralCode
        }
        return nil
    }

    func getCustomHeaders() {
        service.fetchCustomHeaders() { headers, error in
            if headers.isEmpty { return }

            self.prefs.setObject(NSKeyedArchiver.archivedData(withRootObject: headers), forKey: CustomHeaderData.prefsKey)
        }
    }

    class func addCustomHeaders(to request: URLRequest) -> URLRequest {

        guard let prefs = BraveApp.getPrefs(), let customHeadersAsData: Data = prefs.objectForKey(CustomHeaderData.prefsKey) as Any? as? Data,
            let customHeaders = NSKeyedUnarchiver.unarchiveObject(with: customHeadersAsData) as? [CustomHeaderData],
            let hostUrl = request.url?.host else { return request }

        var newRequest = request

        for customHeader in customHeaders {
            innerLoop: for domain in customHeader.domainList {
                if hostUrl.contains(domain) {
                    UrpLog.log("Adding custom header: [\(customHeader.headerField): \(customHeader.headerValue)] for domain: \(domain)")
                    newRequest.addValue(customHeader.headerValue, forHTTPHeaderField: customHeader.headerField)
                    break innerLoop
                }
            }
        }

        return newRequest
    }
}
