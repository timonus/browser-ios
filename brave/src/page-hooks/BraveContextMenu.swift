/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// Using suggestions from: http://www.icab.de/blog/2010/07/11/customize-the-contextual-menu-of-uiwebview/

let kNotificationMainWindowTapAndHold = "kNotificationMainWindowTapAndHold"

class BraveContextMenu {
    fileprivate var tapLocation = CGPoint.zero
    fileprivate var tappedElement: ContextMenuHelper.Elements?

    fileprivate var timer1_cancelDefaultMenu = Timer()
    fileprivate var timer2_showMenuIfStillPressed = Timer()

    static let initialDelayToCancelBuiltinMenu = 0.25 // seconds, must be <0.3 or built-in menu can't be cancelled
    static let totalDelayToShowContextMenu = 0.5 - initialDelayToCancelBuiltinMenu

    fileprivate let fingerMovedTolerance = Float(5.0)

    fileprivate func reset() {
        timer1_cancelDefaultMenu.invalidate()
        timer2_showMenuIfStillPressed.invalidate()
        tappedElement = nil
        tapLocation = CGPoint.zero
    }

    fileprivate func isActive() -> Bool {
        return tapLocation != CGPoint.zero && (timer1_cancelDefaultMenu.isValid || timer2_showMenuIfStillPressed.isValid)
    }

    fileprivate func isBrowserTopmostAndNoPanelsOpen() ->  Bool {
        guard let top = getApp().rootViewController.visibleViewController as? BraveTopViewController else {
            return false
        }

        return top.mainSidePanel.view.isHidden && top.rightSidePanel.view.isHidden
    }

    fileprivate func fingerMovedTooFar(_ touch: UITouch, window: UIView) -> Bool {
        let p1 = touch.location(in: window)
        let p2 = tapLocation
        let distance = hypotf(Float(p1.x) - Float(p2.x), Float(p1.y) - Float(p2.y))
        return distance > fingerMovedTolerance
    }

    func sendEvent(_ event: UIEvent, window: UIWindow) {
        if !isBrowserTopmostAndNoPanelsOpen() {
            reset()
            return
        }

        guard let braveWebView = BraveApp.getCurrentWebView() else { return }

        if let touches = event.touches(for: window), let touch = touches.first, touches.count == 1 {
            braveWebView.lastTappedTime = Date()
            switch touch.phase {
            case .began:  // A finger touched the screen
                reset()
                guard let touchView = event.allTouches?.first?.view, touchView.isDescendant(of: braveWebView) else {
                    return
                }

                tapLocation = touch.location(in: window)
                timer1_cancelDefaultMenu = Timer.scheduledTimer(timeInterval: BraveContextMenu.initialDelayToCancelBuiltinMenu, target: self, selector: #selector(BraveContextMenu.cancelDefaultMenuAndFindTappedItem), userInfo: nil, repeats: false)
            case .moved, .stationary:
                if isActive() && fingerMovedTooFar(touch, window: window) {
                    // my test for this: tap with edge of finger, then roll to opposite edge while holding finger down, is 5-10 px of movement; Should still show context menu, don't want this to trigger a reset()
                    reset()
                }
            case .ended, .cancelled:
                if isActive() {
                    if let url = tappedElement?.link, !fingerMovedTooFar(touch, window: window) {
                        BraveApp.getCurrentWebView()?.loadRequest(URLRequest(url: url as URL))
                    }

                    reset()
                }
            }
        } else {
            reset()
        }
    }

    @objc func showContextMenu() {
        func showContextMenuForElement(_ tappedElement:  ContextMenuHelper.Elements) {
            let info = ["point": NSValue(cgPoint: tapLocation)]
            NotificationCenter.default.post(name: Notification.Name(rawValue: kNotificationMainWindowTapAndHold), object: self, userInfo: info)
            guard let bvc = getApp().browserViewController else { return }
            if bvc.urlBar.inSearchMode {
                return
            }
            bvc.showContextMenu(tappedElement, touchPoint: tapLocation)
            reset()
        }


        if let tappedElement = tappedElement {
            showContextMenuForElement(tappedElement)
        }
    }

    // This is called 2x, once at .25 seconds to ensure the native context menu is cancelled,
    // then again at .5 seconds to show our context menu. (This code was borne of frustration, not ideal flow)
    @objc func cancelDefaultMenuAndFindTappedItem() {
        if !isBrowserTopmostAndNoPanelsOpen() {
            reset()
            return
        }

        guard let webView = BraveApp.getCurrentWebView() else { return }

        let hit: (url: String?, image: String?, urlTarget: String?)?

        if [".jpg", ".png", ".gif"].filter({ webView.URL?.absoluteString.endsWith($0) ?? false }).count > 0 {
            // web view is just showing an image
            hit = (url:nil, image:webView.URL!.absoluteString, urlTarget:nil)
        } else {
            hit = ElementAtPoint().getHit(tapLocation)
        }
        if hit == nil {
            // No link or image found, not for this class to handle
            reset()
            return
        }

        tappedElement = ContextMenuHelper.Elements(link: hit!.url != nil ? URL(string: hit!.url!) : nil, image: hit!.image != nil ? URL(string: hit!.image!) : nil)

        func blockOtherGestures(_ views: [UIView]?) {
            guard let views = views else { return }
            for view in views {
                if let gestures = view.gestureRecognizers as [UIGestureRecognizer]! {
                    for gesture in gestures {
                        if gesture is UILongPressGestureRecognizer {
                            // toggling gets the gesture to ignore this long press
                            gesture.isEnabled = false
                            gesture.isEnabled = true
                        }
                    }
                }
            }
        }
        
        blockOtherGestures(BraveApp.getCurrentWebView()?.scrollView.subviews)

        timer2_showMenuIfStillPressed = Timer.scheduledTimer(timeInterval: BraveContextMenu.totalDelayToShowContextMenu, target: self, selector: #selector(BraveContextMenu.showContextMenu), userInfo: nil, repeats: false)
    }
}
