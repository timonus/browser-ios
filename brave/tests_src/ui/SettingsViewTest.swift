/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import XCTest

class SettingsViewTest : XCTestCase {

    func navToSettings() -> XCUIElement {
        UITestUtils.restart()
        let app = XCUIApplication()
        app.buttons["Bookmarks and History Panel"].tap()
        app.otherElements.buttons["Settings"].tap()
        let table = app.tables["AppSettingsTableViewController.tableView"]
        return table
    }

    func testReportABug() {
        let table = navToSettings()
        let app = XCUIApplication()
        table.swipeUp()
        table.staticTexts["Report a bug"].tap()
        sleep(1)
        app.textFields["url"].tap()
        
        let addressTextField = app.textFields["address"]
        addressTextField.tap()
        let url = addressTextField.value as? String
        XCTAssertTrue(url != nil && url!.contains("https://community.brave.com"))
    }

    func testPrivacyPolicy() {
        let table = navToSettings()
        let app = XCUIApplication()
        table.swipeUp()
        table.staticTexts["Privacy Policy"].tap()
        sleep(1)
        let search = NSPredicate(format: "label contains %@", "Brave Privacy Policy") // case sensitive
        let found = app.staticTexts.element(matching: search)
        XCTAssertTrue(found.exists)
    }

    func testTermsOfUse() {
        let table = navToSettings()
        let app = XCUIApplication()
        table.swipeUp()
        table.staticTexts["Terms of Use"].tap()
        sleep(1)
        let search = NSPredicate(format: "label contains[c] %@", "Please read these terms of use") // case insensitive
        let found = app.staticTexts.element(matching: search)
        XCTAssertTrue(found.exists)
    }

}
