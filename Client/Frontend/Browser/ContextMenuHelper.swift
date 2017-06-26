/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import WebKit
import Shared

protocol ContextMenuHelperDelegate: class {
    func contextMenuHelper(_ contextMenuHelper: ContextMenuHelper, didLongPressElements elements: ContextMenuHelper.Elements, gestureRecognizer: UILongPressGestureRecognizer)
}

class ContextMenuHelper: NSObject, BrowserHelper, UIGestureRecognizerDelegate {
    fileprivate weak var browser: Browser?
    weak var delegate: ContextMenuHelperDelegate?
    fileprivate let gestureRecognizer = UILongPressGestureRecognizer()

    struct Elements {
        let link: URL?
        let image: URL?
    }

    /// Clicking an element with VoiceOver fires touchstart, but not touchend, causing the context
    /// menu to appear when it shouldn't (filed as rdar://22256909). As a workaround, disable the custom
    /// context menu for VoiceOver users.
    fileprivate var showCustomContextMenu: Bool {
        return !UIAccessibilityIsVoiceOverRunning()
    }

    required init(browser: Browser) {
        super.init()

        self.browser = browser
    }

    class func scriptMessageHandlerName() -> String? {
        return "contextMenuMessageHandler"
    }

    func userContentController(_ userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        if !showCustomContextMenu {
            return
        }

        guard let data = message.body as? [String: AnyObject] else { return }

        // On sites where <a> elements have child text elements, the text selection delegate can be triggered
        // when we show a context menu. To prevent this, cancel the text selection delegate if we know the
        // user is long-pressing a link.
        if let handled = data["handled"] as? Bool, handled {
          func blockOtherGestures(_ views: [UIView]) {
            for view in views {
              if let gestures = view.gestureRecognizers as [UIGestureRecognizer]! {
                for gesture in gestures {
                  if gesture is UILongPressGestureRecognizer && gesture != gestureRecognizer {
                    // toggling gets the gesture to ignore this long press
                    gesture.isEnabled = false
                    gesture.isEnabled = true
                  }
                }
              }
            }
          }

          blockOtherGestures((browser?.webView?.scrollView.subviews)!)
        }

        var linkURL: URL?
        if let urlString = data["link"] as? String {
            linkURL = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: CharacterSet.URLAllowedCharacterSet())!)
        }

        var imageURL: URL?
        if let urlString = data["image"] as? String {
            imageURL = URL(string: urlString.addingPercentEncoding(withAllowedCharacters: CharacterSet.URLAllowedCharacterSet())!)
        }

        if linkURL != nil || imageURL != nil {
            let elements = Elements(link: linkURL, image: imageURL)
            delegate?.contextMenuHelper(self, didLongPressElements: elements, gestureRecognizer: gestureRecognizer)
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return showCustomContextMenu
    }
}
