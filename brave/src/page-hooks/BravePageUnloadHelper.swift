/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

class BravePageUnloadHelper: NSObject, BrowserHelper {
    fileprivate weak var browser: Browser?

    required init(browser: Browser) {
        super.init()

        self.browser = browser

        let path = Bundle.main.path(forResource: "PageUnload", ofType: "js")!
        let source = try! NSString(contentsOfFile: path, encoding: String.Encoding.utf8.rawValue) as String
        let userScript = WKUserScript(source: source, injectionTime: WKUserScriptInjectionTime.atDocumentEnd, forMainFrameOnly: true)
        browser.webView!.configuration.userContentController.addUserScript(userScript)
    }

    class func scriptMessageHandlerName() -> String? {
        return "pageUnloadMessageHandler"
    }

    func userContentController(_ userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        NotificationCenter.default.post(name: Notification.Name(rawValue: kNotificationPageUnload), object: browser?.webView)
    }
}
