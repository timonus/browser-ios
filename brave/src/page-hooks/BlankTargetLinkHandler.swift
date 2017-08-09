/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/*
 BraveWebView will, on new load, assume that blank link tap detection is required.
 On load finished, it runs a check to see if any links are _blank targets, and if not, disables this tap detection.
 */

class BlankTargetLinkHandler {
    fileprivate var tapLocation = CGPoint.zero

    func isBrowserTopmost() -> Bool {
        return getApp().rootViewController.visibleViewController as? BraveTopViewController != nil
    }

    func sendEvent(_ event: UIEvent, window: UIWindow) {
        guard let touchView = event.allTouches?.first?.view, let braveWebView = BraveApp.getCurrentWebView(), touchView.isDescendant(of: braveWebView) else {
            return
        }
        
        if !isBrowserTopmost() {
            return
        }

        if let touches = event.touches(for: window), let touch = touches.first, touches.count == 1 {
            guard let webView = BraveApp.getCurrentWebView(), let webViewSuperview = webView.superview  else { return }
            if !webView.blankTargetLinkDetectionOn {
                return
            }

            let globalRect = webViewSuperview.convert(webView.frame, to: nil)
            if !globalRect.contains(touch.location(in: window)) {
                return
            }

            if touch.phase != .began && tapLocation == CGPoint.zero {
                webView.blankTargetUrl = nil
                return
            }

            switch touch.phase {
            case .began:
                tapLocation = touch.location(in: window)
                if let element = ElementAtPoint().getHit(tapLocation), let url = element.url,
                    let t = element.urlTarget, t == "_blank" {
                    webView.blankTargetUrl = url
                } else {
                    tapLocation = CGPoint.zero
                }

            case .moved:
                tapLocation = CGPoint.zero
                webView.blankTargetUrl = nil
            case .ended, .cancelled:
                tapLocation = CGPoint.zero
            case .stationary:
                break
            }
        }
    }
}
