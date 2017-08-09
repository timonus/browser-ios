    /* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import XCTest

class PrivateBrowsingTest: XCTestCase {
    func testPrivateBrowsing() {
        UITestUtils.restart()
        let app = XCUIApplication()

        let uuid = UUID().uuidString
        let searchString = "foo\(uuid.substring(to: uuid.characters.index(uuid.startIndex, offsetBy: 5)))"

        app.buttons["Toolbar.ShowTabs"].tap()

        let privModeButton = app.buttons["TabTrayController.togglePrivateMode"]
        privModeButton.tap()
        sleep(1)
        XCTAssert(privModeButton.isSelected)
        privModeButton.tap()
        sleep(1)
        XCTAssert(!privModeButton.isSelected)

        privModeButton.tap()
        sleep(1)
        if !privModeButton.isSelected {
            privModeButton.tap()
            sleep(1)
        }

        XCTAssert(privModeButton.isSelected)

        app.buttons["TabTrayController.addTabButton"].tap()
        
        UITestUtils.loadSite(app, "www.google.com")

        let googleSearchField = app.otherElements["Web content"].otherElements["Search"]
        googleSearchField.tap()
        UITestUtils.pasteTextFieldText(app, element: googleSearchField, value: "\(searchString)\r")

        app.otherElements["Web content"].buttons["Google Search"].tap()

        app.buttons["Toolbar.ShowTabs"].tap()

        privModeButton.tap() // off

        sleep(1)
        app.otherElements["Tabs Tray"].collectionViews.cells.element(boundBy: 0).tap()

        UITestUtils.loadSite(app, "www.google.com")

        googleSearchField.tap()

        XCTAssert(!app.otherElements["\(searchString) ×"].exists)
        let predicate = NSPredicate(format: "label BEGINSWITH[cd] '\(searchString)'")
        XCTAssert(!app.otherElements.element(matching: predicate).exists)
    }
}
