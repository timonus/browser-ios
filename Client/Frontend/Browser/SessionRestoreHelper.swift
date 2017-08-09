/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit

protocol SessionRestoreHelperDelegate: class {
    func sessionRestoreHelper(_ helper: SessionRestoreHelper, didRestoreSessionForBrowser browser: Browser)
}

class SessionRestoreHelper: BrowserHelper {
    weak var delegate: SessionRestoreHelperDelegate?
    fileprivate weak var browser: Browser?

    required init(browser: Browser) {
        self.browser = browser
    }

    class func scriptMessageHandlerName() -> String? {
        return "sessionRestoreHelper"
    }

    func userContentController(_ userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        if let browser = browser, let params = message.body as? [String: AnyObject] {
            if params["name"] as! String == "didRestoreSession" {
                DispatchQueue.main.async {
                    self.delegate?.sessionRestoreHelper(self, didRestoreSessionForBrowser: browser)
                }
            }
        }
    }
}
