/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import XCTest

class IntroScreenTest: XCTestCase {

    override func setUp() {
        super.setUp()
    }

    override func tearDown() {
        super.tearDown()
    }
    
    // Intro screen is removed for now
    /*
    func testFirstRunIntroScreen() {
        UITestUtils.restart(["BRAVE-TEST-CLEAR-PREFS"])
        let app = XCUIApplication()
        app.buttons["Start Browsing"].tap()
        //app.buttons["Accept & Continue"].tap()
    }
     */

//    func testOptInDialogWithoutIntroScreen() {
//        UITestUtils.restart(["BRAVE-TEST-NO-SHOW-INTRO", "BRAVE-TEST-SHOW-OPT-IN"])
//        UITestUtils.restart(["BRAVE-TEST-NO-SHOW-INTRO", "BRAVE-TEST-SHOW-OPT-IN"])
//        let app = XCUIApplication()
//        app.buttons["Accept & Continue"].tap()
//
//        UITestUtils.restart()
//        // Ensure UI isn't blocked with modal dialog
//        sleep(1)
//        app.buttons["Bookmarks and History Panel"].tap()
//        app.scrollViews.otherElements.buttons["Settings"].tap()
//    }
}
