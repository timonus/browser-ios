/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import XCTest

class WebViewTest: XCTestCase {

    func testUnicodeUrl() {
        UITestUtils.restart()
        let app = XCUIApplication()
        UITestUtils.loadSite(app, "nordølum.no")
        let urlTextField = app.textFields["url"]
        let value = urlTextField.value as? String
        XCTAssert(value != nil && value!.contains("nordoelum.no"))
    }

    func testLongPress() {
        UITestUtils.restart()
        let app = XCUIApplication()
        UITestUtils.loadSite(app, "www.google.com")

        app.staticTexts["IMAGES"].press(forDuration: 1.5);
        app.sheets.element(boundBy: 0).buttons["Open In New Tab"].tap()
        app.buttons["2"].tap()
        app.collectionViews.children(matching: .cell).matching(identifier: "Google").element(boundBy: 1).tap()
    }

    func testLongPressAndCopyUrl() {
        UITestUtils.restart()
        let app = XCUIApplication()
        UITestUtils.loadSite(app, "www.google.com")

        app.staticTexts["IMAGES"].press(forDuration: 1.5);

        UIPasteboard.general.string = ""
        app.sheets.element(boundBy: 0).buttons["Copy Link"].tap()
        let string = UIPasteboard.general.string
        XCTAssert(string != nil && string!.contains("output=search"), "copy url context menu failed")
    }

    func testShowDesktopSite() {
        UITestUtils.restart()
        let app = XCUIApplication()
        UITestUtils.loadSite(app, "www.whatsmyua.com")

        var search = NSPredicate(format: "label contains[c] %@", "CPU iPhone")
        var found = app.staticTexts.element(matching: search)
        XCTAssert(found.exists, "didn't find UA for iPhone")

        app.buttons["BrowserToolbar.shareButton"].tap()
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
}
