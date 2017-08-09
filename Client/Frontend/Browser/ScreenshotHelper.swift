/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared

/**
 * Handles screenshots for a given browser, including pages with non-webview content.
 */
class ScreenshotHelper {
    fileprivate weak var controller: BrowserViewController?

    init(controller: BrowserViewController) {
        self.controller = controller
    }

    func takeScreenshot(_ tab: Browser) {
        var screenshot: UIImage?

        if let url = tab.url {
            if AboutUtils.isAboutHomeURL(url) {
                if let homePanel = controller?.homePanelController {
                    screenshot = homePanel.view.screenshot()
                    tab.setScreenshot(screenshot)
                }
            } else if let wv = tab.webView {
                let offset = CGPoint(x: 0, y: -wv.scrollView.contentInset.top)
                // If webview is hidden, need to add it for screenshot.
                let showForScreenshot = wv.superview == nil && getApp().tabManager.selectedTab != tab
                if showForScreenshot {
                    getApp().rootViewController.view.insertSubview(wv, at: 0)
                    wv.frame = wv.convert(getApp().tabManager.selectedTab?.webView?.frame ?? CGRect.zero, to: nil)
                    postAsyncToMain(0.1) { [weak tab] in
                        screenshot = tab?.webView?.screenshot(offset: offset)
                        tab?.setScreenshot(screenshot)

                        // Due to delay, consider: tab having become selected, and tab is deleted
                        // A deleted tab will have already called removeFromSuperview (calling 2x is ok)
                        // Just ensure not to call that if the tab is now selected.
                        if getApp().tabManager.selectedTab != tab {
                            tab?.webView?.removeFromSuperview()
                        }
                    }
                } else {
                    screenshot = tab.webView?.screenshot(offset: offset)
                    tab.setScreenshot(screenshot)
                }
            }
        }
    }

    /// Takes a screenshot after a small delay.
    /// Trying to take a screenshot immediately after didFinishNavigation results in a screenshot
    /// of the previous page, presumably due to an iOS bug. Adding a brief delay fixes this.
    func takeDelayedScreenshot(_ tab: Browser) {
        if tab.pendingScreenshot {
            return
        }
        tab.pendingScreenshot = true
        postAsyncToMain(2) { [weak self, weak tab = tab] in
            if let tab = tab {
                tab.pendingScreenshot = false
                self?.takeScreenshot(tab)
            }
        }
    }
}
