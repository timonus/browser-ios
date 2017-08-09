/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import XCTest

extension XCUIElement {
    func forceTapElement() {
        if self.isHittable {
            self.tap()
        }
        else {
            let coordinate: XCUICoordinate = self.coordinate(withNormalizedOffset: CGVector(dx: 0.0, dy: 0.0))
            coordinate.tap()
        }
    }
}

class UITestUtils {
    static func loadSite(_ app:XCUIApplication, _ site: String) {
        app.textFields["url"].tap()
        app.textFields["address"].typeText(site)
        app.typeText("\r")
    }

    static func pasteTextFieldText(_ app:XCUIApplication, element:XCUIElement, value:String) {
        UIPasteboard.general.string = value
        element.tap()
        app.menuItems["Paste"].tap()
    }

    static func restart(_ bootArgs: [String] = []) {
        let app = XCUIApplication()

        app.terminate()
        app.launchArguments.append("BRAVE-UI-TEST")
        bootArgs.forEach {
            app.launchArguments.append($0)
        }
        app.launch()
    }

    static func waitForGooglePageLoad(_ test: XCTestCase) {
        let app = XCUIApplication()
        // TODO: find a better way to see if google is loaded, other than looking for links on the page
        [app.links["IMAGES"], app.links["Advertising"]].forEach {
            let predicate = NSPredicate(format: "exists == 1")
            test.expectation(for: predicate, evaluatedWith: $0, handler: nil)
            test.waitForExpectations(timeout: 3, handler: nil)
        }
    }
}
