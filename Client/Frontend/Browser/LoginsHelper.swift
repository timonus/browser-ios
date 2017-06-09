/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import Storage
import XCGLogger
import WebKit
import Deferred
import SwiftyJSON

private let log = Logger.browserLogger

class LoginsHelper: BrowserHelper {
    fileprivate let profile: Profile
    weak var browser: Browser?
    var snackBar: SnackBar?

    // Exposed for mocking purposes
    var logins: BrowserLogins {
        return profile.logins
    }

    required init(browser: Browser, profile: Profile) {
        self.browser = browser
        self.profile = profile

        if let path = Bundle.main.path(forResource: "LoginsHelper", ofType: "js"), let source = try? NSString(contentsOfFile: path, encoding: String.Encoding.utf8.rawValue) as String {
            let userScript = WKUserScript(source: source, injectionTime: WKUserScriptInjectionTime.atDocumentEnd, forMainFrameOnly: true)
            browser.webView!.configuration.userContentController.addUserScript(userScript)
        }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    static func scriptMessageHandlerName() -> String? {
        return "loginsManagerMessageHandler"
    }

    func userContentController(_ userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        guard var res = message.body as? [String: AnyObject] else { return }
        guard let type = res["type"] as? String else { return }

        // We don't use the WKWebView's URL since the page can spoof the URL by using document.location
        // right before requesting login data. See bug 1194567 for more context.
        if let url = message.frameInfo.request.url {
            // Since responses go to the main frame, make sure we only listen for main frame requests
            // to avoid XSS attacks.
            if message.frameInfo.isMainFrame && type == "request" {
                res["username"] = "" as AnyObject
                res["password"] = "" as AnyObject
                if let login = Login.fromScript(url, script: res),
                   let requestId = res["requestId"] as? String {
                    requestLogins(login, requestId: requestId)
                }
            } else if type == "submit" {
                if self.profile.prefs.boolForKey("saveLogins") ?? true {
                    if let login = Login.fromScript(url, script: res) {
                        setCredentials(login)
                    }
                }
            }
        }
    }

    class func replace(_ base: String, keys: [String], replacements: [String]) -> NSMutableAttributedString {
        var ranges = [NSRange]()
        var string = base
        for (index, key) in keys.enumerated() {
            let replace = replacements[index]
            let range = string.range(of: key,
                options: NSString.CompareOptions.literal,
                range: nil,
                locale: nil)!
            string.replaceSubrange(range, with: replace)
            let nsRange = NSMakeRange(string.characters.distance(from: string.startIndex, to: range.lowerBound),
                replace.characters.count)
            ranges.append(nsRange)
        }

        var attributes = [String: AnyObject]()
        attributes[NSFontAttributeName] = UIFont.systemFont(ofSize: 13, weight: UIFontWeightRegular)
        attributes[NSForegroundColorAttributeName] = UIColor.darkGray
        let attr = NSMutableAttributedString(string: string, attributes: attributes)
        let font: UIFont = UIFont.systemFont(ofSize: 13, weight: UIFontWeightMedium)
        for (_, range) in ranges.enumerated() {
            attr.addAttribute(NSFontAttributeName, value: font, range: range)
        }
        return attr
    }

    func getLoginsForProtectionSpace(_ protectionSpace: URLProtectionSpace) -> Deferred<Maybe<Cursor<LoginData>>> {
        return profile.logins.getLoginsForProtectionSpace(protectionSpace)
    }

    func updateLoginByGUID(_ guid: GUID, new: LoginData, significant: Bool) -> Success {
        return profile.logins.updateLoginByGUID(guid, new: new, significant: significant)
    }

    func removeLoginsWithGUIDs(_ guids: [GUID]) -> Success {
        return profile.logins.removeLoginsWithGUIDs(guids)
    }

    func setCredentials(_ login: LoginData) {
        if login.password.isEmpty {
            log.debug("Empty password")
            return
        }

        succeed().upon() { _ in // move off main
            self.profile.logins
                   .getLoginsForProtectionSpace(login.protectionSpace, withUsername: login.username)
                   .uponQueue(DispatchQueue.main) { res in
                if let data = res.successValue {
                    log.debug("Found \(data.count) logins.")
                    for saved in data {
                        if let saved = saved {
                            if saved.password == login.password {
                                self.profile.logins.addUseOfLoginByGUID(saved.guid)
                                return
                            }

                            self.promptUpdateFromLogin(login: saved, toLogin: login)
                            return
                        }
                    }
                }

                self.promptSave(login)
            }
        }
    }

    fileprivate func promptSave(_ login: LoginData) {
        guard login.isValid.isSuccess else {
            return
        }

        let promptMessage: NSAttributedString
        if let username = login.username {
            let promptStringFormat = Strings.Save_login_for_template
            promptMessage = NSAttributedString(string: String(format: promptStringFormat, username, login.hostname))
        } else {
            let promptStringFormat = Strings.Save_password_for_template
            promptMessage = NSAttributedString(string: String(format: promptStringFormat, login.hostname))
        }

        if snackBar != nil {
            browser?.removeSnackbar(snackBar!)
        }

        snackBar = TimerSnackBar(attrText: promptMessage,
            img: UIImage(named: "key"),
            buttons: [
                SnackButton(title: Strings.DontSave, accessibilityIdentifier: "", callback: { (bar: SnackBar) -> Void in
                    self.browser?.removeSnackbar(bar)
                    self.snackBar = nil
                    return
                }),

                SnackButton(title: Strings.SaveLogin, accessibilityIdentifier: "", callback: { (bar: SnackBar) -> Void in
                    self.browser?.removeSnackbar(bar)
                    self.snackBar = nil
                    succeed().upon { _ in // move off main thread
                        self.profile.logins.addLogin(login)
                    }
                })
            ])
        browser?.addSnackbar(snackBar!)
    }

    fileprivate func promptUpdateFromLogin(login old: LoginData, toLogin new: LoginData) {
        guard new.isValid.isSuccess else {
            return
        }

        let guid = old.guid

        let formatted: String
        if let username = new.username {
            let promptStringFormat = Strings.Update_login_for_template
            formatted = String(format: promptStringFormat, username, new.hostname)
        } else {
            let promptStringFormat = Strings.Update_password_for_template
            formatted = String(format: promptStringFormat, new.hostname)
        }
        let promptMessage = NSAttributedString(string: formatted)

        if snackBar != nil {
            browser?.removeSnackbar(snackBar!)
        }

        snackBar = TimerSnackBar(attrText: promptMessage,
            img: UIImage(named: "key"),
            buttons: [
                SnackButton(title: Strings.DontSave, accessibilityIdentifier: "", callback: { (bar: SnackBar) -> Void in
                    self.browser?.removeSnackbar(bar)
                    self.snackBar = nil
                    return
                }),

                SnackButton(title: Strings.Update, accessibilityIdentifier: "", callback: { (bar: SnackBar) -> Void in
                    self.browser?.removeSnackbar(bar)
                    self.snackBar = nil
                    self.profile.logins.updateLoginByGUID(guid, new: new,
                                                          significant: new.isSignificantlyDifferentFrom(old))
                })
            ])
        browser?.addSnackbar(snackBar!)
    }

    fileprivate func requestLogins(_ login: LoginData, requestId: String) {
        succeed().upon() { _ in // move off main thread
            getApp().profile?.logins.getLoginsForProtectionSpace(login.protectionSpace).uponQueue(DispatchQueue.main) { res in
                var jsonObj = [String: AnyObject]()
                if let cursor = res.successValue {
                    log.debug("Found \(cursor.count) logins.")
                    jsonObj["requestId"] = requestId
                    jsonObj["name"] = "RemoteLogins:loginsFound"
                    jsonObj["logins"] = cursor.map { $0!.toDict() }
                }

                let json = JSON(jsonObj)
                let src = "window.__firefox__.logins.inject(\(json.toString()))"
                self.browser?.webView?.evaluateJavaScript(src, completionHandler: nil)
            }
        }
    }
}
