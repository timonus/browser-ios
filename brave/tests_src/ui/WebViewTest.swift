/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import XCTest

class WebViewTest: XCTestCase {

    func testUnicodeUrl() {
        UITestUtils.restart()
        let app = XCUIApplication()
        UITestUtils.loadSite(app, "nordølum.no")
        sleep(1)
        XCTAssertTrue(getUrl(app).contains("northernviking.net"))
    }

    func testLongPress() {
        UITestUtils.restart()
        let app = XCUIApplication()
        UITestUtils.loadSite(app, "www.google.ca")

        let tabButton = UITestUtils.tabButton(app)
        let tabCount = Int(tabButton.value as! String)!

        app.staticTexts["IMAGES"].press(forDuration: 1.5);
        
        app.sheets.element(boundBy: 0).buttons["Open Link In New Tab"].tap()
        tabButton.tap()
        
        if UITestUtils.isIpad {
            app.collectionViews.children(matching: .cell).matching(identifier: "Google Images").element(boundBy: 0).tap()
        } else {
            app.collectionViews.children(matching: .cell).matching(identifier: "Google").element(boundBy: 1).tap()
        }
        
        let newTabCount = Int(tabButton.value as! String)!
        
        XCTAssert(newTabCount == tabCount + 1)
    }

    func testLongPressAndCopyUrl() {
        UITestUtils.restart()
        let app = XCUIApplication()
        UITestUtils.loadSite(app, "www.google.ca")

        app.staticTexts["IMAGES"].press(forDuration: 1.5);

        UIPasteboard.general.string = ""
        app.sheets.element(boundBy: 0).buttons["Copy Link"].tap()
        let string = UIPasteboard.general.string
        XCTAssert(string != nil && string!.contains("output=search"), "copy url context menu failed")
    }

    func testShowDesktopSite() {
        UITestUtils.restart()
        let app = XCUIApplication()
        UITestUtils.loadSite(app, "www.useragents.com")

        let label = UITestUtils.isIpad ? "iPad" : "CPU iPhone"
        
        var search = NSPredicate(format: "label contains[c] %@", label)
        var found = app.staticTexts.element(matching: search)
        XCTAssert(found.exists, "didn't find UA for iPhone")
        
        UITestUtils.shareButton(app).tap()
        app.collectionViews.collectionViews.buttons["Open Desktop Site tab"].tap()

        sleep(1)
        search = NSPredicate(format: "label contains[c] %@", "Intel Mac")
        found = app.staticTexts.element(matching: search)
        XCTAssert(found.exists, "didn't find UA for desktop")
    }

    func testSafeBrowsing() {
        UITestUtils.restart()
        let app = XCUIApplication()
        UITestUtils.loadSite(app, "excellentmovies.net")

        let search = NSPredicate(format: "label contains[c] %@", "brave shield blocked page")
        let found = app.staticTexts.element(matching: search)
        XCTAssert(found.exists, "safe browsing failed")
    }
  
    func testRegionalAdblock() {
        UITestUtils.restart(["LOCALE=RU"])
        let app = XCUIApplication()
        UITestUtils.loadSite(app, "https://sputniknews.com/russia")

        // waitForExpecation with `exists` predicate is randomly failing, sigh. do this instead
        for _ in 0..<5 {
            let blockedUrl = app.staticTexts["blocked-url"]
            if !blockedUrl.exists {
                sleep(1)
                continue
            }

            let str = blockedUrl.value as? String
            XCTAssert(str?.hasPrefix("ru ") ?? false)
            break
        }
    }
    
    func testPushStateURL() {
        UITestUtils.restart()
        let app = XCUIApplication()
        // Testing in landscape to catch full url, on portrait it's cut
        XCUIDevice.shared().orientation = .landscapeLeft
        UITestUtils.loadSite(app, "brianbondy.com")
        sleep(1)
        
        let tapUrl = "brianbondy.com/other"
        
        // Home page url
        XCTAssertFalse(getUrl(app).contains(tapUrl))
        
        // Tap 'Other' section, should change url
        app.webViews.staticTexts["Other"].tap()
        sleep(1)
        XCTAssert(getUrl(app).contains(tapUrl))
        
        // Tap back, url should point to homepage url again
        app.buttons["Back"].tap()
        sleep(1)
        XCTAssertFalse(getUrl(app).contains(tapUrl))
        
        XCUIDevice.shared().orientation = .portrait
    }
    
    private func getUrl(_ app: XCUIApplication) -> String {
        return app.textFields["url"].value as! String
    }
}
