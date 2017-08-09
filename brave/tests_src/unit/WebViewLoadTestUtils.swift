/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */
import Foundation
import XCTest
@testable import Client
import Shared

//extension XCTestCase {
//    func tester(file : String = #file, _ line : Int = #line) -> KIFUITestActor {
//        return KIFUITestActor(inFile: file, atLine: line, delegate: self)
//    }
//
//    func system(file : String = #file, _ line : Int = #line) -> KIFSystemTestActor {
//        return KIFSystemTestActor(inFile: file, atLine: line, delegate: self)
//    }
//}
//
//extension KIFTestActor {
//    func tester(file : String = #file, _ line : Int = #line) -> KIFUITestActor {
//        return KIFUITestActor(inFile: file, atLine: line, delegate: self)
//    }
//
//    func system(file : String = #file, _ line : Int = #line) -> KIFSystemTestActor {
//        return KIFSystemTestActor(inFile: file, atLine: line, delegate: self)
//    }
//}

class WebViewLoadTestUtils {
    static func urlProtocolEnabled(_ enable:Bool) {
        if enable {
          URLProtocol.registerClass(URLProtocol);
        } else {
          URLProtocol.unregisterClass(URLProtocol);
        }
    }

    static func httpseEnabled(_ enable: Bool) {
        URLProtocol.testShieldState = BraveShieldState()
        URLProtocol.testShieldState?.setState(.HTTPSE, on: enable)
    }

    static func loadSite(_ testCase: XCTestCase, site:String, webview:BraveWebView) ->Bool {
        let url = URL(string: "http://" + site)
        testCase.expectationForNotification(BraveWebViewConstants.kNotificationWebViewLoadCompleteOrFailed, object: nil, handler:nil)
        webview.loadRequest(URLRequest(URL: url!))
        var isOk = true
        testCase.waitForExpectations(timeout: 15) { (error:NSError?) -> Void in
            if let _ = error {
                isOk = false
            }
        } as! XCWaitCompletionHandler as! XCWaitCompletionHandler as! XCWaitCompletionHandler as! XCWaitCompletionHandler as! XCWaitCompletionHandler as! XCWaitCompletionHandler

        webview.stopLoading()
        testCase.expectationForNotification(BraveWebViewConstants.kNotificationWebViewLoadCompleteOrFailed, object: nil, handler:nil)
        webview.loadHTMLString("<html><head></head><body></body></html>", baseURL: nil)
        testCase.waitForExpectations(timeout: 2, handler: nil)

        return isOk
    }


    static func loadSites(_ testCase: XCTestCase, sites:[String]) {
        let w = BraveWebView(frame: CGRect(x: 0,y: 0,width: 200,height: 200), useDesktopUserAgent: false)
        for site in sites {
            print("\(site)")
            self.loadSite(testCase, site: site, webview: w)
        }
    }
}
