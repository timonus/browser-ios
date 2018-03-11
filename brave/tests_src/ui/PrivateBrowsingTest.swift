    /* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import XCTest

class PrivateBrowsingTest: XCTestCase {
    func testPrivateBrowsing() {
        UITestUtils.restart()
        let app = XCUIApplication()

        let uuid = UUID().uuidString
        let searchString = "foo\(uuid.substring(to: uuid.characters.index(uuid.startIndex, offsetBy: 5)))"

        let tabButton = UITestUtils.tabButton(app)
        tabButton.tap()
        

        let privModeButton = app.buttons["TabTrayController.togglePrivateMode"]
        privModeButton.tap()
        sleep(1)
        // Automatically shows new private tab window
        tabButton.tap()
        
        XCTAssert(privModeButton.isSelected)
        privModeButton.tap()
        sleep(1)
        XCTAssert(!privModeButton.isSelected)

        privModeButton.tap()
        sleep(1)
        tabButton.tap()
        
        if !privModeButton.isSelected {
            privModeButton.tap()
            sleep(1)
        }

        XCTAssert(privModeButton.isSelected)

        app.buttons["TabTrayController.searchButton"].tap()
        
        UITestUtils.loadSite(app, "www.google.ca")

        let googleSearchField = app.webViews.otherElements["Search"]
        
        googleSearchField.tap()
        UITestUtils.pasteTextFieldText(app, element: googleSearchField, value: "\(searchString)\r")

        app.webViews.buttons["Google Search"].tap()
        
        // After paste action, toolbar with 'done' button is shown, overlapping brave bottom toolbar.
        // We need to wait a seconds until it hides.
        sleep(1)
        
        tabButton.tap()

        privModeButton.tap() // off

        sleep(1)
        app.otherElements["Tabs Tray"].collectionViews.cells.element(boundBy: 0).tap()

        UITestUtils.loadSite(app, "www.google.ca")

        googleSearchField.tap()

        XCTAssert(!app.otherElements["\(searchString) ×"].exists)
        let predicate = NSPredicate(format: "label BEGINSWITH[cd] '\(searchString)'")
        XCTAssert(!app.otherElements.element(matching: predicate).exists)
    }
}
