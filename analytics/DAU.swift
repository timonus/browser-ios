/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared

// TODO: Separate logger for this kind of work?
private let log = Logger.browserLogger

struct DAU {
    public static let preferencesKey = "dau_stat"
    public static let weekOfInstallationKeyPrefKey = "week_of_installation"
    
    let prefs: Prefs
    
    private let baseUrl = "https://laptop-updates.brave.com/1/usage/ios?platform=ios"
    
    private let today: Date
    private var todayComponents: DateComponents {
        return (Calendar.current as NSCalendar).components([.day, .month , .year, .weekday], from: today)
    }
    
    init(prefs: Prefs, date: Date? = nil) {
        self.prefs = prefs
        today = date ?? Date()
    }
    
    public func sendPingToServer() {
        guard let params = paramsAndPrefsSetup() else {
            log.debug("dau, no changes detected, no server ping")
            print("bxx dau, no changes detected, no server ping")
            return
        }
        
        // Sending ping to server
        let fullUrl = baseUrl + params
        log.debug("send ping to server, url: \(fullUrl)")
        print("bxx send ping to server, url: \(fullUrl)")
        
        guard let url = URL(string: fullUrl) else {
            if !BraveUX.IsRelease {
                BraveApp.showErrorAlert(title: "Debug", error: "failed stats update")
            }
            return
        }
        let task = URLSession.shared.dataTask(with: url) { _, _, error in
            if let e = error { log.error("status update error: \(e)") }
        }
        task.resume()
    }
    
    
    /** Return params query or nil if no ping should be send to server. */
    func paramsAndPrefsSetup() -> String? {
        let dauStats = prefs.arrayForKey(DAU.preferencesKey)
        let isFirstLaunch = dauStats == nil
        
        let mondayOfCurrentWeek = todayComponents.weeksMonday
        
        var params = "&\(channelParam)"
            + "&\(versionParam)"
            + "&\(firstLaunchParam(isFirstLaunch))"
            + "&\(weekOfInstallationParam(value: mondayOfCurrentWeek, firstLaunch: isFirstLaunch))"
        
        // Setting preferences
        if isFirstLaunch {
            prefs.setString(mondayOfCurrentWeek, forKey: DAU.weekOfInstallationKeyPrefKey)
        } else {
            // If not first launch, ping to the server is only sent after enough time passed
            if let dauStatParams = dauStatParams(dauStats) {
                params += dauStatParams
            } else {
                log.debug("dau, no changes detected, no server ping")
                return nil
            }
        }
        
        let secsMonthYear = [Int(today.timeIntervalSince1970), todayComponents.month, todayComponents.year]
        prefs.setObject(secsMonthYear, forKey: DAU.preferencesKey)
        
        return params
    }
    
    var channelParam: String {
        return "channel=\(BraveUX.IsRelease ? "stable" : "beta")"
    }
    
    // TODO: Add leading `.0` to so app version is always in format x.x.x.
    // See issue #1337 for more info.
    var versionParam: String {
        return "version=\(AppInfo.appVersion)"
    }
    
    func firstLaunchParam(_ isFirst: Bool) -> String {
        return "first=\(isFirst)"
    }
    
    /** All first app installs are normalized to first day of the week.
     Eg. user installs app on wednesday 2017-22-11, his install date is recorded as of 2017-20-11(Monday) */
    func weekOfInstallationParam(value: String, firstLaunch: Bool) -> String {
        if firstLaunch {
            return "woi=\(value)"
        } else if let woi = prefs.stringForKey(DAU.weekOfInstallationKeyPrefKey) {
            return "woi=\(woi)"
        } else {
            // TODO: Set some arbitrary date, yet to be decided
            let woiOldDate = "2000-01-01"
            return "woi=\(woiOldDate)"
        }
    }
    
    /// Returns nil if no dau changes detected.
    func dauStatParams(_ dauStat: [Any]?) -> String? {
        let month = todayComponents.month
        let year = todayComponents.year
        
        guard let stat = dauStat as? [Int] else {
            log.error("Cannot cast dauStat to [Int]")
            return nil
        }
        
        guard stat.count == 3 else {
            log.error("dauStat array must contain exactly 3 elements")
            return nil
        }
        
        let dSecs = Int(today.timeIntervalSince1970) - stat[0]
        let _month = stat[1]
        let _year = stat[2]
        let SECONDS_IN_A_DAY = 86400
        let SECONDS_IN_A_WEEK = 7 * 86400
        let daily = dSecs >= SECONDS_IN_A_DAY
        let weekly = dSecs >= SECONDS_IN_A_WEEK
        let monthly = month != _month || year != _year
        log.debug("Dau stat params, daily: \(daily), weekly: \(weekly), monthly:\(monthly), dSecs: \(dSecs)")
        if (!daily && !weekly && !monthly) {
            // No changes, no ping
            return nil
        }
        
        return "&daily=\(daily)&weekly=\(weekly)&monthly=\(monthly)"
    }
}

extension DateComponents {
    /// Returns date of current week's monday in YYYY-MM-DD format
    var weeksMonday: String {
        var isSunday: Bool {
            guard let weekday = weekday else {
                log.error("Weekday is nil")
                return false
            }
            return weekday == 1
        }
        
        // Make sure all required date components are set.
        guard let _ = day, let _ = month, let _ = year, let weekday = weekday else {
            log.error("Date components are missing")
            return ""
        }
        
        guard let today = Calendar.current.date(from: self) else {
            log.error("Cannot create date from date components")
            return ""
        }
        
        let dayInSeconds = 60 * 60 * 24
        // Sunday is first weekday so we need to handle this day differently, can't just substract it.
        let sundayToMondayDayDifference = 6
        let dayDifference = isSunday ? sundayToMondayDayDifference : weekday - 2 // -2 because monday is second weekday
        
        let monday = Date(timeInterval: -TimeInterval(dayDifference * dayInSeconds), since: today)
        let mondayComponents = (Calendar.current as NSCalendar).components([.day, .month , .year], from: monday)
        
        guard let mYear = mondayComponents.year, let mMonth = mondayComponents.month, let mDay = mondayComponents.day else {
            log.error("First monday of the week components are nil")
            return ""
        }
        
        return "\(mYear)-\(mMonth)-\(mDay)"
    }
}
