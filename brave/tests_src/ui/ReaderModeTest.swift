/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import XCTest

class ReaderModeTest : XCTestCase {
    func testReaderMode() {
        UITestUtils.restart()
        let app = XCUIApplication()
        UITestUtils.loadSite(app, "www.google.com/intl/en/about")

        app.buttons["Reader View"].tap()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0)).withOffset(CGVector(dx: 100, dy: 75)).tap()

        app.buttons["Serif"].tap()
        app.buttons["Sans-serif"].tap()
        app.buttons["Decrease text size"].tap()
        app.buttons["Increase text size"].tap()
        app.buttons["Light"].tap()
        app.buttons["Dark"].tap()
        app.buttons["Sepia"].tap()

    }
}
