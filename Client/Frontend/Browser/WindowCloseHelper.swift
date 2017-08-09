/* This Source Code Form is subject to the terms of the Mozilla Public
* License, v. 2.0. If a copy of the MPL was not distributed with this
* file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit

protocol WindowCloseHelperDelegate: class {
    func windowCloseHelper(_ windowCloseHelper: WindowCloseHelper, didRequestToCloseBrowser browser: Browser)
}

class WindowCloseHelper: BrowserHelper {
    weak var delegate: WindowCloseHelperDelegate?
    fileprivate weak var browser: Browser?

    required init(browser: Browser) {
        self.browser = browser
        if let path = Bundle.main.path(forResource: "WindowCloseHelper", ofType: "js") {
            if let source = try? NSString(contentsOfFile: path, encoding: String.Encoding.utf8.rawValue) as String {
                let userScript = WKUserScript(source: source, injectionTime: WKUserScriptInjectionTime.atDocumentEnd, forMainFrameOnly: true)
                browser.webView!.configuration.userContentController.addUserScript(userScript)
            }
        }
    }

    class func scriptMessageHandlerName() -> String? {
        return "windowCloseHelper"
    }

    func userContentController(_ userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        if let browser = browser {
            DispatchQueue.main.async {
                self.delegate?.windowCloseHelper(self, didRequestToCloseBrowser: browser)
            }
        }
    }
}
