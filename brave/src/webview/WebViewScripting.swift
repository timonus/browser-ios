/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

func hashString (_ obj: AnyObject) -> String {
    return String(UInt(bitPattern: ObjectIdentifier(obj)))
}


class LegacyUserContentController
{
    var scriptHandlersMainFrame = [String:WKScriptMessageHandler]()
    var scriptHandlersSubFrames = [String:WKScriptMessageHandler]()

    var scripts:[WKUserScript] = []
    weak var webView: BraveWebView?

    func addScriptMessageHandler(_ scriptMessageHandler: WKScriptMessageHandler, name: String) {
        scriptHandlersMainFrame[name] = scriptMessageHandler
    }

    func removeScriptMessageHandler(_ name: String) {
        scriptHandlersMainFrame.removeValue(forKey: name)
        scriptHandlersSubFrames.removeValue(forKey: name)
    }

    func addUserScript(_ script:WKUserScript) {
        var mainFrameOnly = true
        if !script.isForMainFrameOnly {
            print("Inject to subframes")
            // Only contextMenu injection to subframes for now,
            // whitelist this explicitly, don't just inject scripts willy-nilly into frames without
            // careful consideration. For instance, there are security implications with password management in frames
            mainFrameOnly = false
        }
        scripts.append(WKUserScript(source: script.source, injectionTime: script.injectionTime, forMainFrameOnly: mainFrameOnly))
    }

    init(_ webView: BraveWebView) {
        self.webView = webView
    }

    static var jsPageHasBlankTargets:String = {
        let path = Bundle.main.path(forResource: "BlankTargetDetector", ofType: "js")!
        let source = try! NSString(contentsOfFile: path, encoding: String.Encoding.utf8.rawValue) as String
        return source
    }()

    func injectIntoMain() {
        guard let webView = webView else { return }

        let result = webView.stringByEvaluatingJavaScript(from: "window.hasOwnProperty('__firefox__')")
        if result == "true" {
            // already injected into this context
            return
        }

        // use tap detection until this returns false/
        // on page start reset enableBlankTargetTapDetection, then set it off when page loaded
        webView.blankTargetLinkDetectionOn = true
        if webView.stringByEvaluatingJavaScript(from: LegacyUserContentController.jsPageHasBlankTargets) != "true" {
            // no _blank
            webView.blankTargetLinkDetectionOn = false
        }
        print("has blank targets \(webView.blankTargetLinkDetectionOn)")

        let js = LegacyJSContext()
        js.windowOpenOverride(webView, context:nil)

        for (name, handler) in scriptHandlersMainFrame {
            js.installHandler(for: webView, handlerName: name, handler:handler)
        }

        for script in scripts {
            webView.stringByEvaluatingJavaScript(from: script.source)
        }
    }

    func injectFingerprintProtection() {
        guard let webView = webView,
              let handler = scriptHandlersMainFrame[FingerprintingProtection.scriptMessageHandlerName()!] else { return }

        let js = LegacyJSContext()
        js.installHandler(for: webView, handlerName: FingerprintingProtection.scriptMessageHandlerName(), handler:handler)
        webView.stringByEvaluatingJavaScript(from: FingerprintingProtection.script)

        let frames = js.findNewFrames(for: webView, withFrameContexts: nil)
        for ctx in frames! {
            js.installHandler(forContext: ctx, handlerName: FingerprintingProtection.scriptMessageHandlerName(), handler:handler, webView:webView)
            js.call(onContext: ctx, script: FingerprintingProtection.script)
        }
    }

    func injectIntoSubFrame() {
        let js = LegacyJSContext()
        let contexts = js.findNewFrames(for: webView, withFrameContexts: webView?.knownFrameContexts)

        for ctx in contexts! {
            js.windowOpenOverride(webView, context:ctx)

            webView?.knownFrameContexts.insert((ctx as AnyObject).hash as! NSObject)

            for (name, handler) in scriptHandlersSubFrames {
                js.installHandler(forContext: ctx, handlerName: name, handler:handler, webView:webView)
            }
            for script in scripts {
                if !script.isForMainFrameOnly {
                    js.call(onContext: ctx, script: script.source)
                }
            }
        }
    }

    static func injectJsIntoAllFrames(_ webView: BraveWebView, script: String) {
        webView.stringByEvaluatingJavaScript(from: script)
        let js = LegacyJSContext()
        let contexts = js.findNewFrames(for: webView, withFrameContexts: nil)
        for ctx in contexts! {
            js.call(onContext: ctx, script: script)
        }
    }
    
    func injectJsIntoPage() {
        injectIntoMain()
        injectIntoSubFrame()
    }
}

class BraveWebViewConfiguration
{
    let userContentController: LegacyUserContentController
    init(webView: BraveWebView) {
        userContentController = LegacyUserContentController(webView)
    }
}
