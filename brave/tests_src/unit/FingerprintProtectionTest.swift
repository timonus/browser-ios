/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import XCTest
@testable import Client
import Shared
import KIF

/*

 UITestUtils.loadSite(app, "panopticlick.eff.org")
 app.staticTexts["TEST ME"].tap()
 app.staticTexts["Show full results for fingerprinting"].tap()
 app.staticTexts["cb11ce1da2381e5f8a8add3145bd0da5"].tap()
 app.buttons["Brave Panel"].tap()
 */

class FingerprintProtectionTest: XCTestCase {
    static func enabled(_ enable: Bool) {
        URLProtocol.testShieldState = BraveShieldState()
        URLProtocol.testShieldState?.setState(.FpProtection, on: enable)
    }

    func testFingerprintProtection() {
        FingerprintProtectionTest.enabled(true)

        let url = URL(string: "https://panopticlick.eff.org/results")
        let webview = BraveApp.getCurrentWebView()
        webview!.loadRequest(URLRequest(url: url!))


        expectation(forNotification: BraveWebViewConstants.kNotificationWebViewLoadCompleteOrFailed, object: nil, handler:nil)

        waitForExpectations(timeout: 15) { error in
            if let _ = error {
            }
        }

        var expect = expectation(description: "wait")
        postAsyncToMain(8) { expect.fulfill()}
        waitForExpectations(timeout: 10) { error in }

        webview!.stringByEvaluatingJavaScript(from: "document.getElementById('showFingerprintLink2').click();")
        expect = expectation(description: "wait")
        postAsyncToMain(3) { expect.fulfill() }
        waitForExpectations(timeout: 5) { error in }


        let innerHtml = webview!.stringByEvaluatingJavaScript(from: "document.body.innerHTML")
        XCTAssert(innerHtml != nil)
        XCTAssert(innerHtml!.contains("891f3debe00dbd3d1f0457a70d2f5213"))

        let match = webview!.stringByEvaluatingJavaScript(from: "/webgl fingerprint.*(\\n.+)*undetermined/gim.exec(document.body.innerHTML)[0]")

        XCTAssert(match != nil && match!.characters.count > 50 && (match!.characters.count) < 300)
    }
}
