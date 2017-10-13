/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import XCTest
@testable import Client
import Shared

class HttpsEverywhereTest: XCTestCase {
    func testHTTPSE() {
        if !HttpsEverywhere.singleton.httpseDb.isLoaded() {
            expectation(forNotification: HttpsEverywhere.kNotificationDataLoaded, object: nil, handler:nil)
            HttpsEverywhere.singleton.networkFileLoader.loadData()
            var isOk = true
            waitForExpectations(timeout: 20) { error in
                if let _ = error {
                    isOk = false
                    XCTAssert(false, "load data failed")
                }
            }

            if !isOk {
                return
            }
        }

        let urls = ["motherboard.vice.com", "thestar.com", "www.thestar.com", "apple.com", "xkcd.com"]

        for url in urls {
            let redirected = HttpsEverywhere.singleton.tryRedirectingUrl(URL(string: "http://" + url)!)
            XCTAssert(redirected != nil && redirected!.scheme!.startsWith("https"), "failed:" + url)
        }

        let exceptions = ["m.slashdot.com"]

        for url in exceptions {
            let redirected = HttpsEverywhere.singleton.tryRedirectingUrl(URL(string: "http://" + url)!)
            XCTAssert(redirected == nil)
        }

        // test suffix maintained
        let url = HttpsEverywhere.singleton.tryRedirectingUrl(URL(string: "http://www.googleadservices.com/pagead/aclk?sa=L&ai=CD0d/")!)
        XCTAssert(url != nil && url!.absoluteString.hasSuffix("?sa=L&ai=CD0d/"))
    }

  /* 
     Some optional timing tests, might be useful to measure regressions
     during development of HTTPS-E. But otherwise load timing is too erratic to be used as part of an assertion.

     private func doTest(httpseOn on: Bool, group: [String]) {
        WebViewLoadTestUtils.httpseEnabled(on)
        measureBlock({
            WebViewLoadTestUtils.loadSites(self, sites: group)
        })
    }

    func testTimeHttpseOn_A() {
        doTest(httpseOn: true, group: groupA)
    }

    func testTimeHttpseOff_A() {
        doTest(httpseOn: false, group: groupA)
    }

    func testTimeHttpseOn_B() {
        doTest(httpseOn: true, group: groupB)
    }

    func testTimeHttpseOff_B() {
        doTest(httpseOn: false, group: groupB)
    }
 */

}
