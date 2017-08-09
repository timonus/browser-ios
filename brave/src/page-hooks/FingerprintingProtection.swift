/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

class FingerprintingProtection: NSObject, BrowserHelper {
    fileprivate weak var browser: Browser?

    static var script: String = {
        let path = Bundle.main.path(forResource: "FingerprintingProtection", ofType: "js")!
        return try! NSString(contentsOfFile: path, encoding: String.Encoding.utf8.rawValue) as String
    }()

    required init(browser: Browser) {
        super.init()

        self.browser = browser

        let userScript = WKUserScript(source: FingerprintingProtection.script, injectionTime: WKUserScriptInjectionTime.atDocumentStart, forMainFrameOnly: true)
        browser.webView?.configuration.userContentController.addUserScript(userScript)
    }

    class func scriptMessageHandlerName() -> String? {
        return "fingerprinting"
    }

    func userContentController(_ userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        browser?.webView?.shieldStatUpdate(.fpIncrement)
        print("fingerprint \(message.body)")
    }
}
