/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */
import Foundation
import XCTest
@testable import Client
import Shared

// Timings are too erratic to be used as part of an assertion of success,
// therefore this test is not part of regular test suite

var groupA = ["businessinsider.com", "kotaku.com", "cnn.com"]
var groupB = ["imore.com", "nytimes.com"]

class WebViewLoadTest: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Without small wait tests ran separately fail as they are not truly separated atm.
        let expect = expectation(description: "setUp() wait")
        postAsyncToMain(3) { expect.fulfill() }
        waitForExpectations(timeout: 4) { error in }
    }
    
  

    func testOpenUrlUsingBraveSchema() {
        expectation(forNotification: BraveWebViewConstants.kNotificationWebViewLoadCompleteOrFailed, object: nil, handler:nil)
        let site = "google.ca"
        let ok = UIApplication.shared.openURL(
            URL(string: "brave://open-url?url=https%253A%252F%252F" + site)!)
        waitForExpectations(timeout: 10, handler: nil)
        XCTAssert(ok, "open url failed for site: \(site)")
    }

    func testJSPopupBlockedForNonCurrentWebView() {
        let url = URL(string: "http://example.com")

        let webview1 = BraveApp.getCurrentWebView()!
        expectation(forNotification: BraveWebViewConstants.kNotificationWebViewLoadCompleteOrFailed, object: nil, handler:nil)
        webview1.loadRequest(URLRequest(url: url!))

        waitForExpectations(timeout: 5) { error in
            if let _ = error {}
        }

        expectation(forNotification: BraveWebViewConstants.kNotificationWebViewLoadCompleteOrFailed, object: nil, handler:nil)
        getApp().tabManager.addTabAndSelect(URLRequest(url: URL(string: "http://google.ca")!), configuration: WKWebViewConfiguration())
        waitForExpectations(timeout: 5) { error in
            if let _ = error {}
        }
        let webview2 = BraveApp.getCurrentWebView()!
        assert(webview1 !== webview2)

        for i in ["alert(' ')", "prompt(' ')", "confirm(' ')"] {
            expectation(forNotification: "JavaScriptPopupBlockedHiddenWebView", object: nil, handler:nil)
            webview1.stringByEvaluatingJavaScript(from: i)
            waitForExpectations(timeout: 5) { error in
                if let _ = error {}
            }
        }
    }


    func testLocationChangeTimeoutHack() {
        // hackerone issue 175958
        let url = URL(string: "http://example.com")

        let webview = BraveApp.getCurrentWebView()
        expectation(forNotification: BraveWebViewConstants.kNotificationWebViewLoadCompleteOrFailed, object: nil, handler:nil)
        webview!.loadRequest(URLRequest(url: url!))

        waitForExpectations(timeout: 15) { error in
            if let _ = error {
            }
        }

        let expect = expectation(description: "wait")

        postAsyncToMain(1) {
            webview?.stringByEvaluatingJavaScript(
                from: "var timer = 0;" +
                "function f() {location = 'https://facebook.com'};" +
                "timer = setInterval('f()', 10);" +
                "setTimeout(function () { clearInterval(timer) }, 5000);")
        }

        postAsyncToMain(8) {
            //TODO: the url location will flicker as it keeps getting set from facebook to example.com, this is correct,
            // not sure how to assert this behaviour just yet
            expect.fulfill()
        }

        waitForExpectations(timeout: 10) { error in }

        XCTAssert(webview!.URL!.absoluteString.contains("facebook"))
    }

    func testTrackingProtection() {
        let urls = ["scorecardresearch.com",
                    "imrworldwide.com",
                    "google-analytics.com",
                    "googletagservices.com",
                    "googlesyndication.com",
                    "quantserve.com",
                    "teads.tv",
                    "netshelter.net",
                    "viglink.com",
                    "bluekai.com",
                    "bkrtx.com",
                    "tubemogul.com",
                    "sitescout.com",]

        for url in urls {
            let req = NSMutableURLRequest(url: URL(string: "http://" + url)!)
            req.mainDocumentURL = URL(string: "http://www.example.com")
            let b = TrackingProtection.singleton.shouldBlock(req as URLRequest)
            XCTAssert(b, "TrackingProtection failed: \(url)")
        }
    }

    func testAdblock() {
        let urls = ["teads.tv",
                    "netshelter.net",
                    "tubemogul.com",
                    "sitescout.com",
                    "sharethrough.com",]

        for url in urls {
            let req = NSMutableURLRequest(url: URL(string: "http://" + url)!)
            req.mainDocumentURL = URL(string: "http://www.example.com")
            let b = AdBlocker.singleton.shouldBlock(req as URLRequest)
            XCTAssert(b)
        }
    }
}
