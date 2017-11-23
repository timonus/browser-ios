/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import XCTest
@testable import Client
import Shared

class DauTest: XCTestCase {
    var prefs: MockProfilePrefs!
    
    override func setUp() {
        super.setUp()
        prefs = MockProfilePrefs()
    }
    
    override func tearDown() {
        super.tearDown()
        prefs = nil
    }
    
    func testFirstLaunch() {
        let date = dateFrom(string: "2017-11-22")
        let dau = DAU(prefs: prefs, date: date)
        
        XCTAssertNil(prefs.arrayForKey(DAU.preferencesKey))
        XCTAssertNil(prefs.stringForKey(DAU.weekOfInstallationKeyPrefKey))
        
        let params = dau.paramsAndPrefsSetup()
        
        XCTAssertNotNil(params)
        XCTAssertNotNil(prefs.arrayForKey(DAU.preferencesKey))
        XCTAssertNotNil(prefs.stringForKey(DAU.weekOfInstallationKeyPrefKey))
        
        XCTAssertEqual(params!,
                       "&channel=beta&version=\(appVersion)&daily=true&weekly=true&monthly=true&first=true&woi=2017-11-20")
    }
    
    func testNotFirstLaunchSkipDau() {
        let date = dateFrom(string: "2017-11-20")
        
        XCTAssertNil(prefs.arrayForKey(DAU.preferencesKey))
        XCTAssertNil(prefs.stringForKey(DAU.weekOfInstallationKeyPrefKey))
        
        // Acting like a first launch so preferences are going to be set up
        let dauFirstLaunch = DAU(prefs: prefs, date: date)
        _ = dauFirstLaunch.paramsAndPrefsSetup()
        
        let dauSecondLaunch = DAU(prefs: prefs, date: date)
        
        XCTAssertNotNil(prefs.arrayForKey(DAU.preferencesKey))
        XCTAssertNotNil(prefs.stringForKey(DAU.weekOfInstallationKeyPrefKey))
        
        let params = dauSecondLaunch.paramsAndPrefsSetup()
        XCTAssertNil(params) // params nil, not pinging the server
    }
    
    func testNotFirstLaunchSetDau() {
        var woiPrefs: String {
            return prefs.stringForKey(DAU.weekOfInstallationKeyPrefKey)!
        }
        
        let date = dateFrom(string: "2017-11-20")
        
        XCTAssertNil(prefs.arrayForKey(DAU.preferencesKey))
        XCTAssertNil(prefs.stringForKey(DAU.weekOfInstallationKeyPrefKey))
        
        // Acting like a first launch so preferences are going to be set up
        let dauFirstLaunch = DAU(prefs: prefs, date: date)
        _ = dauFirstLaunch.paramsAndPrefsSetup()
        
        // Needs to wait at least day since last launch to send dau update
        let dailyFutureDate = dateFrom(string: "2017-11-22")
        let dauSecondLaunch = DAU(prefs: prefs, date: dailyFutureDate)
        
        // Daily check
        let dailyParams = dauSecondLaunch.paramsAndPrefsSetup()
        XCTAssertNotNil(dailyParams)
        XCTAssertEqual(dailyParams!,
                       "&channel=beta&version=\(appVersion)&daily=true&weekly=false&monthly=false&first=false&woi=\(woiPrefs)")
        
        // Weekly check
        let weeklyFutureDate = dateFrom(string: "2017-11-30")
        let weeklyParams = DAU(prefs: prefs, date: weeklyFutureDate).paramsAndPrefsSetup()
        XCTAssertNotNil(weeklyParams)
        XCTAssertEqual(weeklyParams!,
                       "&channel=beta&version=\(appVersion)&daily=true&weekly=true&monthly=false&first=false&woi=\(woiPrefs)")
        
        // Monthly check
        let monthlyFutureDate = dateFrom(string: "2017-12-20")
        let monthlyParams = DAU(prefs: prefs, date: monthlyFutureDate).paramsAndPrefsSetup()
        XCTAssertNotNil(monthlyParams)
        XCTAssertEqual(monthlyParams!,
                       "&channel=beta&version=\(appVersion)&daily=true&weekly=true&monthly=true&first=false&woi=\(woiPrefs)")
    }
    
    func testArbitraryWoiDate() {
        let date = dateFrom(string: "2017-11-22")
        
        prefs.setObject([10, 10, 10], forKey: DAU.preferencesKey)
        
        let dau = DAU(prefs: prefs, date: date)
        
        XCTAssertNil(prefs.stringForKey(DAU.weekOfInstallationKeyPrefKey))
        
        let params = dau.paramsAndPrefsSetup()
        let defaultDate = DAU.defaultWoiDate
        
        XCTAssertEqual(params!,
                       "&channel=beta&version=\(appVersion)&daily=true&weekly=true&monthly=true&first=false&woi=\(defaultDate)")
        
        XCTAssertNotNil(prefs.stringForKey(DAU.weekOfInstallationKeyPrefKey))
    }
    
    func testMondayOfWeek() {
        let monday = componentsOfDate("2017-11-20")
        XCTAssertEqual(monday.weeksMonday, "2017-11-20")
        
        let tuesday = componentsOfDate("2017-11-21")
        XCTAssertEqual(tuesday.weeksMonday, "2017-11-20")
        
        let wednesday = componentsOfDate("2017-11-22")
        XCTAssertEqual(wednesday.weeksMonday, "2017-11-20")
        
        let thursday = componentsOfDate("2017-11-22")
        XCTAssertEqual(thursday.weeksMonday, "2017-11-20")
        
        let friday = componentsOfDate("2017-12-01")
        XCTAssertEqual(friday.weeksMonday, "2017-11-27")
        
        let saturday = componentsOfDate("2017-12-02")
        XCTAssertEqual(saturday.weeksMonday, "2017-11-27")
        
        let sunday = componentsOfDate("2017-12-03")
        XCTAssertEqual(sunday.weeksMonday, "2017-11-27")
    }
    
    func testAppend0ToAppVersion() {
        XCTAssertFalse(DAU.shouldAppend0ToAppVersion("1.5.2"))
        XCTAssertFalse(DAU.shouldAppend0ToAppVersion("1.52.2"))
        XCTAssertFalse(DAU.shouldAppend0ToAppVersion("11.5.23"))
        XCTAssertFalse(DAU.shouldAppend0ToAppVersion("11.55.23"))
        
        XCTAssertTrue(DAU.shouldAppend0ToAppVersion("1.5"))
        XCTAssertTrue(DAU.shouldAppend0ToAppVersion("11.5"))
        XCTAssertTrue(DAU.shouldAppend0ToAppVersion("1.10"))
    }
    
    private func componentsOfDate(_ dateString: String) -> DateComponents {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        let date = dateFormatter.date(from: dateString)!
        
        return (Calendar.current as NSCalendar).components([.day, .month , .year, .weekday], from: date)
    }
    
    private func dateFrom(string: String) -> Date {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        
        return dateFormatter.date(from: string)!
    }
    
    private var appVersion: String {
        return DAU.shouldAppend0ToAppVersion(AppInfo.appVersion) ? AppInfo.appVersion + ".0" : AppInfo.appVersion
    }
}
