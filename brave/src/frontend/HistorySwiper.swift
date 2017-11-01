/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */


// Used by Browser as a member var to store sceenshots
class ScreenshotsForHistory {
    let kMaxItems = 4
    var items: [(location: String, lastVisited: Date, image: UIImage)] = []

    func addForLocation(_ location: String, image: UIImage) {
        if items.count == kMaxItems {
            var oldest = 0
            for i in 1..<items.count {
                if items[i].lastVisited.timeIntervalSince(items[oldest].lastVisited) < 0 {
                    oldest = i
                }
            }
            items.remove(at: oldest)
        }

        items.append((location: location, lastVisited: Date(), image: image))
        //        #if DEBUG
        //        for item in items {
        //            print("§ \(item)")
        //        }
        //        #endif
    }

    // updates date visited and return true if item with location exists
    func touchExistingItem(_ location: String) -> Bool {
        for i in 0..<items.count {
            if items[i].location == location {
                let image = items[i].image
                items.remove(at: i)
                addForLocation(location, image: image)
                return true
            }
        }
        return false
    }

    func get(_ location: String) -> UIImage? {
        for i in 0..<items.count {
            if items[i].location == location {
                return items[i].image
            }
        }
        return nil
    }
}

class HistorySwiper : NSObject {

    var topLevelView: UIView!
    var webViewContainer: UIView!

    func setup(_ topLevelView: UIView, webViewContainer: UIView) {
        self.topLevelView = topLevelView
        self.webViewContainer = webViewContainer

        goBackSwipe.delegate = self
        goForwardSwipe.delegate = self
    }

    lazy var goBackSwipe: UIGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(HistorySwiper.screenLeftEdgeSwiped(_:)))
        self.topLevelView.superview!.addGestureRecognizer(pan)
        return pan
    }()

    lazy var goForwardSwipe: UIGestureRecognizer = {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(HistorySwiper.screenRightEdgeSwiped(_:)))
        self.topLevelView.superview!.addGestureRecognizer(pan)
        return pan
    }()

    @objc func updateDetected() {
        restoreWebview()
    }

    func screenWidth() -> CGFloat {
        return topLevelView.frame.width
    }

#if IMAGE_SWIPE_ON
    var imageView: UIImageView?
#endif

    fileprivate func handleSwipe(_ recognizer: UIPanGestureRecognizer) {
        if getApp().browserViewController.homePanelController != nil {
            return
        }
        if getApp().braveTopViewController.leftPanelShowing() || getApp().braveTopViewController.rightPanelShowing() {
            return
        }

        guard let tab = getApp().browserViewController.tabManager.selectedTab, let webview = tab.webView else { return }
        
        let swipePosition = recognizer.location(in: recognizer.view)
        
        /* Swipe should trigger website navigation in two cases
         - when gesture distance passes half of the screen, doesn't matter how fast the swipe is
         - when gesture is fast enough, swipe position and distance doesn't matter then */
        let halfOfTheScreen = screenWidth() / 2.0
        let swipePassedHalfScreen = recognizer == goBackSwipe ?
            swipePosition.x > halfOfTheScreen : swipePosition.x < halfOfTheScreen
        
        let swipeVelocity = recognizer.velocity(in: recognizer.view).x
        // Forward gesture(right to left) velocity is negative, need to check swipe type
        let fastSwipe = goBackSwipe != nil ?
            swipeVelocity > BraveUX.fastSwipeVelocity : swipeVelocity < -BraveUX.fastSwipeVelocity
        
        let correctSwipe = swipePassedHalfScreen || fastSwipe
        
        if recognizer.state == .ended || recognizer.state == .cancelled || recognizer.state == .failed {
            UIView.animate(withDuration: 0.25, animations: {
                if correctSwipe {
                    let x = recognizer == self.goBackSwipe ? self.screenWidth() : -self.screenWidth()
                    self.webViewContainer.transform = CGAffineTransform(translationX: x, y: self.webViewContainer.transform.ty)
                    self.webViewContainer.alpha = 0
                } else {
                    self.webViewContainer.transform = CGAffineTransform(translationX: 0, y: self.webViewContainer.transform.ty)
                }
                }, completion: { _ in
                    if correctSwipe {
                        if recognizer == self.goBackSwipe {
                           tab.goBack()
                        } else {
                            tab.goForward()
                        }

                        self.webViewContainer.transform = CGAffineTransform(translationX: 0, y: self.webViewContainer.transform.ty)

                        // when content size is updated
                        postAsyncToMain(3.0) {
                            self.restoreWebview()
                        }
                        NotificationCenter.default.removeObserver(self)
                        NotificationCenter.default.addObserver(self, selector: #selector(HistorySwiper.updateDetected), name: NSNotification.Name(rawValue: BraveWebViewConstants.kNotificationPageInteractive), object: webview)
                        NotificationCenter.default.addObserver(self, selector: #selector(HistorySwiper.updateDetected), name: NSNotification.Name(rawValue: BraveWebViewConstants.kNotificationWebViewLoadCompleteOrFailed), object: webview)
                    } else {
#if IMAGE_SWIPE_ON
                        if let v = self.imageView {
                           v.removeFromSuperview()
                           self.imageView = nil
                           getApp().browserViewController.webViewContainerBackdrop.alpha = 0
                        }
#endif
                    }
            })
        } else {
            let tx = recognizer == goBackSwipe ? swipePosition.x : swipePosition.x - screenWidth()
            webViewContainer.transform = CGAffineTransform(translationX: tx, y: self.webViewContainer.transform.ty)
#if IMAGE_SWIPE_ON
            let image = recognizer.edges == .Left ? tab.screenshotForBackHistory() : tab.screenshotForForwardHistory()
            if let image = image, imageView == nil {
                imageView = UIImageView(image: image)

                getApp().browserViewController.webViewContainerBackdrop.addSubview(imageView!)
                getApp().browserViewController.webViewContainerBackdrop.alpha = 1
                imageView!.frame = CGRectMake(0, 0, self.webViewContainer.frame.width, self.webViewContainer.frame.height)
            }
#endif
        }
    }

    func restoreWebview() {
        NotificationCenter.default.removeObserver(self)
        if webViewContainer.alpha < 1 {
            postAsyncToMain(0.4) { // after a render detected, allow ample time for drawing to complete
                UIView.animate(withDuration: 0.2, animations: {
                    self.webViewContainer.alpha = 1.0
                }) 
            }

#if IMAGE_SWIPE_ON
            if let v = self.imageView {
                v.removeFromSuperview()
                self.imageView = nil
                getApp().browserViewController.webViewContainerBackdrop.alpha = 0
            }
#endif
        }
    }

    @objc func screenRightEdgeSwiped(_ recognizer: UIScreenEdgePanGestureRecognizer) {
        handleSwipe(recognizer)
    }

    @objc func screenLeftEdgeSwiped(_ recognizer: UIScreenEdgePanGestureRecognizer) {
        handleSwipe(recognizer)
    }
}

extension HistorySwiper : UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let tab = getApp().browserViewController.tabManager.selectedTab, let webview = tab.webView else { return false}
        if (recognizer == goBackSwipe && !webview.canNavigateBackward()) ||
            (recognizer == goForwardSwipe && !webview.canNavigateForward()) {
            return false
        }

        guard let recognizer = recognizer as? UIPanGestureRecognizer else { return false }
        let v = recognizer.velocity(in: recognizer.view)
        if fabs(v.x) < fabs(v.y) {
            return false
        }

        let tolerance = CGFloat(30.0)
        let p = recognizer.location(in: recognizer.view)
        return recognizer == goBackSwipe ? p.x < tolerance : p.x > screenWidth() - tolerance
    }
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}
