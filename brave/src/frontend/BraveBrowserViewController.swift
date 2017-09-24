/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared
import SnapKit
import SafariServices

class BraveBrowserViewController : BrowserViewController {
    fileprivate lazy var __once: () = {
        if self.profile.prefs.boolForKey(kPrefKeyPrivateBrowsingAlwaysOn) ?? false {
            getApp().browserViewController.switchBrowsingMode(toPrivate: true)
            // Auto-creates new tab
        } else {
            _ = self.tabManager.restoreTabs
        }
    }()
    
    var historySwiper = HistorySwiper()

    override func applyTheme(_ themeName: String) {
        super.applyTheme(themeName)
        
        toolbar?.accessibilityLabel = "bottomToolbar"
        webViewContainerBackdrop.accessibilityLabel = "webViewContainerBackdrop"
        webViewContainer.accessibilityLabel = "webViewContainer"
        statusBarOverlay.accessibilityLabel = "statusBarOverlay"
        urlBar.accessibilityLabel = "BraveUrlBar"

        toolbar?.applyTheme(themeName)
        
        switch(themeName) {
        case Theme.NormalMode:
            footer.layer.shadowColor = UIConstants.BorderColor.cgColor
            header.layer.shadowColor = UIConstants.BorderColor.cgColor
        case Theme.PrivateMode:
            footer.layer.shadowColor = UIConstants.BorderColorDark.cgColor
            header.layer.shadowColor = UIConstants.BorderColorDark.cgColor
        default:
            debugPrint("Unknown Theme \(themeName)")
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        // Initialize Sync without connecting. Sync webview needs to be in a "permanent" location to continue working predictably
        //  If Sync is not in the view "hierarchy" it will behavior extremely unpredictably, often just dying in the middle of a promize chain
        //  Added to keyWindow, since it can then be utilized from any VC (e.g. settings modal)
        Sync.shared.webView.alpha = 0.01
        UIApplication.shared.keyWindow?.insertSubview(Sync.shared.webView, at: 0)
        
        // TODO: Remove
        // Makes webview visible for debug logging
//        Sync.shared.webView.alpha = 1
//        UIApplication.shared.keyWindow?.addSubview(Sync.shared.webView)
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let showingIntroScreen = profile.prefs.intForKey(IntroViewControllerSeenProfileKey) == nil
        if !showingIntroScreen && profile.prefs.intForKey(BraveUX.PrefKeyOptInDialogWasSeen) == nil {
            presentOptInDialog()
        }

        self.updateToolbarStateForTraitCollection(self.traitCollection)
        
        // TODO: Should never call setupConstraints multiple times, this can cause huge headaches. Constraints should mostly be static with adjustments made to those constraints.
        setupConstraints()

        _ = self.__once

        updateTabCountUsingTabManager(tabManager, animated: false)

        footer.accessibilityLabel = "footer"
        footerBackdrop.accessibilityLabel = "footerBackdrop"
    }

    func updateBraveShieldButtonState(_ animated: Bool) {
        guard let s = tabManager.selectedTab?.braveShieldStateSafeAsync.get() else { return }
        let up = s.isNotSet() || !s.isAllOff()
        (urlBar as! BraveURLBarView).setBraveButtonState(up, animated: animated)
    }

    override func selectedTabChanged(_ selected: Browser) {
        historySwiper.setup(self.view, webViewContainer: self.webViewContainer)
        for swipe in [historySwiper.goBackSwipe, historySwiper.goForwardSwipe] {
            selected.webView?.scrollView.panGestureRecognizer.require(toFail: swipe)
            scrollController.panGesture.require(toFail: swipe)
        }

        if let webView = selected.webView {
            webViewContainer.insertSubview(webView, at: 0)
            webView.snp.makeConstraints { make in
                make.top.equalTo(webViewContainerToolbar.snp.bottom)
                make.left.right.bottom.equalTo(self.webViewContainer)
            }

            urlBar.updateProgressBar(Float(webView.estimatedProgress), dueToTabChange: true)
            urlBar.updateReloadStatus(webView.isLoading)
            updateBraveShieldButtonState(false)

            let bravePanel = getApp().braveTopViewController.rightSidePanel
            bravePanel.setShieldBlockedStats(webView.shieldStats)
            bravePanel.updateSitenameAndTogglesState()
        }
        postAsyncToMain(0.1) {
            self.becomeFirstResponder()
        }
    }

    override func SELtappedTopArea() {
     //   scrollController.showToolbars(animated: true)
    }

    var heightConstraint: Constraint?
    override func setupConstraints() {
        super.setupConstraints()

        // TODO: Should be moved to parent class, but requires property moving too
        webViewContainer.snp.remakeConstraints { make in
            make.left.right.equalTo(self.view)
            heightConstraint = make.height.equalTo(self.view.snp.height).constraint
            webViewContainerTopOffset = make.top.equalTo(self.statusBarOverlay.snp.bottom).offset(BraveURLBarView.CurrentHeight).constraint
        }
    }

    override func updateViewConstraints() {
        super.updateViewConstraints()

        // Setup the bottom toolbar
        toolbar?.snp.remakeConstraints { make in
            make.edges.equalTo(self.footerBackground!)
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        webViewContainerTopOffset?.update(offset: BraveURLBarView.CurrentHeight)
        heightConstraint?.update(offset: -BraveApp.statusBarHeight())
    }
    
    override func updateToolbarStateForTraitCollection(_ newCollection: UITraitCollection) {
        super.updateToolbarStateForTraitCollection(newCollection)

        heightConstraint?.update(offset: -BraveApp.statusBarHeight())

        postAsyncToMain(0) {
            self.urlBar.updateTabsBarShowing()
        }
    }

    override func showHomePanelController(_ inline:Bool) {
        super.showHomePanelController(inline)
        postAsyncToMain(0.1) {
            if UIResponder.currentFirstResponder() == nil {
                self.becomeFirstResponder()
            }
        }
    }

    override func hideHomePanelController() {
        super.hideHomePanelController()

        // For bizzaro reasons, this can take a few delayed attempts. The first responder is getting set to nil -I *did* search the codebase for any resigns that could cause this.
        func setSelfAsFirstResponder(_ attempt: Int) {
            if UIResponder.currentFirstResponder() === self {
                return
            }
            if attempt > 5 {
                print("Failed to set BVC as first responder ;(")
                return
            }
            postAsyncToMain(0.1) {
                self.becomeFirstResponder()
                setSelfAsFirstResponder(attempt + 1)
            }
        }

        postAsyncToMain(0.1) {
           setSelfAsFirstResponder(0)
        }
    }

    func newTabForDesktopSite(_ url: URL) {
        let tab = tabManager.addTabForDesktopSite()
        tab.loadRequest(URLRequest(url: url))
    }

    @objc func learnMoreTapped() {
        UIApplication.shared.openURL(BraveUX.BravePrivacyURL as URL)
    }

    func presentOptInDialog() {
        // Off until TOS is properly set
//        let view = BraveTermsViewController()
//        view.delegate = self
//        presentViewController(view, animated: false) {}
    }
}

extension BraveBrowserViewController: BraveTermsViewControllerDelegate {
    func braveTermsAcceptedTermsAndOptIn() {
        profile.prefs.setInt(1, forKey: BraveUX.PrefKeyUserAllowsTelemetry)
        profile.prefs.setInt(1, forKey: BraveUX.PrefKeyOptInDialogWasSeen)
    }
    
    func braveTermsAcceptedTermsAndOptOut() {
        profile.prefs.setInt(0, forKey: BraveUX.PrefKeyUserAllowsTelemetry)
        profile.prefs.setInt(1, forKey: BraveUX.PrefKeyOptInDialogWasSeen)
    }

    func dismissed() {
        let optedIn = self.profile.prefs.intForKey(BraveUX.PrefKeyUserAllowsTelemetry) ?? 1
        if optedIn != 1 {
            return
        }

        func showHiddenSafariViewController(_ controller:SFSafariViewController) {
            controller.view.isUserInteractionEnabled = false
            controller.view.alpha = 0.0
            controller.view.frame = CGRect.zero
            self.addChildViewController(controller)
            self.view.addSubview(controller.view)
            controller.didMove(toParentViewController: self)
        }

        func removeHiddenSafariViewController(_ controller:SFSafariViewController) {
            controller.willMove(toParentViewController: nil)
            controller.view.removeFromSuperview()
            controller.removeFromParentViewController()
        }

        let mixpanelToken = Bundle.main.infoDictionary?["MIXPANEL_TOKEN"] ?? "no-token"
        let callbackData = "{'event':'install','properties':{'product':'brave-ios','token':'\(mixpanelToken)','version':'/\(getApp().appVersion)'}}".addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? "no-data"
        let base64Encoded = callbackData.data(using: String.Encoding.utf8)?.base64EncodedString(options: Data.Base64EncodingOptions(rawValue: 0)) ?? "no-base64"
        let callbackUrl = "https://metric-proxy.brave.com/track?data=" + base64Encoded

        let sf = SFSafariViewController(url: URL(string: callbackUrl)!)
        showHiddenSafariViewController(sf)

        postAsyncToMain(15) {
            removeHiddenSafariViewController(sf)
        }
    }
}

weak var _firstResponder:UIResponder?
extension UIResponder {
    func findFirstResponder() {
        _firstResponder = self
    }

    static func currentFirstResponder() -> UIResponder? {
        if (UIApplication.shared.sendAction(#selector(findFirstResponder), to: nil, from: nil, for: nil)) {
            return _firstResponder
        } else {
            return nil
        }
    }
}
