/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit

protocol ReadabilityBrowserHelperDelegate {
    func readabilityBrowserHelper(_ readabilityBrowserHelper: ReadabilityBrowserHelper, didFinishWithReadabilityResult result: ReadabilityResult)
}

class ReadabilityBrowserHelper: BrowserHelper {
    var delegate: ReadabilityBrowserHelperDelegate?

    init?(browser: Browser) {
        if let readabilityPath = Bundle.main.path(forResource: "Readability", ofType: "js"),
           let readabilitySource = try? NSMutableString(contentsOfFile: readabilityPath, encoding: String.Encoding.utf8.rawValue),
           let readabilityBrowserHelperPath = Bundle.main.path(forResource: "ReadabilityBrowserHelper", ofType: "js"),
           let readabilityBrowserHelperSource = try? NSMutableString(contentsOfFile: readabilityBrowserHelperPath, encoding: String.Encoding.utf8.rawValue) {
            readabilityBrowserHelperSource.replaceOccurrences(of: "%READABILITYJS%", with: readabilitySource as String, options: NSString.CompareOptions.literal, range: NSMakeRange(0, readabilityBrowserHelperSource.length))
            let userScript = WKUserScript(source: readabilityBrowserHelperSource as String, injectionTime: WKUserScriptInjectionTime.atDocumentEnd, forMainFrameOnly: true)
            browser.webView!.configuration.userContentController.addUserScript(userScript)
        }
    }

    class func scriptMessageHandlerName() -> String? {
        return "readabilityMessageHandler"
    }

    func userContentController(_ userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        if let readabilityResult = ReadabilityResult(object: message.body as AnyObject) {
            delegate?.readabilityBrowserHelper(self, didFinishWithReadabilityResult: readabilityResult)
        }
   }
}
