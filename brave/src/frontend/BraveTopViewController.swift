/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared
import Storage
import SnapKit

let kNotificationLeftSlideOutClicked = "kNotificationLeftSlideOutClicked"
let kNotificationBraveButtonClicked = "kNotificationBraveButtonClicked"


class BraveTopViewController : UIViewController {
    var browserViewController:BraveBrowserViewController
    var mainSidePanel:MainSidePanelViewController
    var rightSidePanel:BraveRightSidePanelViewController
    var clickDetectionView = UIButton()
    var leftConstraint: Constraint? = nil
    var rightConstraint: Constraint? = nil
    var leftSidePanelButtonAndUnderlay: ButtonWithUnderlayView?
    init(browserViewController:BraveBrowserViewController) {
        self.browserViewController = browserViewController
        mainSidePanel = MainSidePanelViewController()
        rightSidePanel = BraveRightSidePanelViewController()
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError()
    }

    fileprivate func addVC(_ vc: UIViewController) {
        addChildViewController(vc)
        view.addSubview(vc.view)
        vc.didMove(toParentViewController: self)
    }

    override func viewDidLoad() {
        view.accessibilityLabel = "HighestView"
        view.backgroundColor = BraveUX.TopLevelBackgroundColor

        browserViewController.view.accessibilityLabel = "BrowserViewController"

        addVC(browserViewController)
        addVC(mainSidePanel)
        addVC(rightSidePanel)


        mainSidePanel.view.snp.makeConstraints {
            make in
            make.bottom.left.top.equalTo(view)
            make.width.equalTo(0)
        }

        rightSidePanel.view.snp.makeConstraints {
            make in
            make.bottom.right.top.equalTo(view)
            make.width.equalTo(0)
        }

        clickDetectionView.backgroundColor = UIColor(white: 80/255, alpha: 0.3)

        setupBrowserConstraints()

        NotificationCenter.default.addObserver(self, selector: #selector(onClickLeftSlideOut), name: NSNotification.Name(rawValue: kNotificationLeftSlideOutClicked), object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(onClickBraveButton), name: NSNotification.Name(rawValue: kNotificationBraveButtonClicked), object: nil)

        clickDetectionView.addTarget(self, action: #selector(BraveTopViewController.dismissAllSidePanels), for: UIControlEvents.touchUpInside)

        mainSidePanel.browserViewController = browserViewController
    }

    @objc func dismissAllSidePanels() {
        if leftPanelShowing() {
            mainSidePanel.willHide()
            togglePanel(mainSidePanel)
            leftSidePanelButtonAndUnderlay?.isSelected = false
            leftSidePanelButtonAndUnderlay?.underlay.isHidden = true
        }

        if rightPanelShowing() {
            togglePanel(rightSidePanel)
        }
    }

    fileprivate func setupBrowserConstraints() {
        browserViewController.view.snp.makeConstraints {
            make in
            make.bottom.equalTo(view)
            make.top.equalTo(topLayoutGuide.snp.top)
            let _rightConstraint = make.right.equalTo(view).constraint
            let _leftConstraint = make.left.equalTo(view).constraint

            if UIDevice.current.userInterfaceIdiom == .phone {
                rightConstraint = _rightConstraint
                leftConstraint = _leftConstraint
            }
        }

        if UIDevice.current.userInterfaceIdiom != .phone {
            browserViewController.header.snp.makeConstraints { make in
                if rightConstraint == nil {
                    leftConstraint = make.left.equalTo(view).constraint
                    rightConstraint = make.right.equalTo(view).constraint
                }
            }
        }
    }

    override var preferredStatusBarStyle : UIStatusBarStyle {
        return PrivateBrowsing.singleton.isOn ? .lightContent : .default
    }

    func leftPanelShowing() -> Bool {
        return mainSidePanel.view.frame.width == CGFloat(BraveUX.WidthOfSlideOut)
    }

    func rightPanelShowing() -> Bool {
        return rightSidePanel.view.frame.width == CGFloat(BraveUX.WidthOfSlideOut)
    }

    override var prefersStatusBarHidden : Bool {
        if UIDevice.current.userInterfaceIdiom != .phone {
            return super.prefersStatusBarHidden
        }

        if BraveApp.isIPhoneLandscape() {
            return true
        }

        return leftPanelShowing() || rightPanelShowing()
    }

    func onClickLeftSlideOut(_ notification: Notification) {
        leftSidePanelButtonAndUnderlay = notification.object as? ButtonWithUnderlayView
        if !rightSidePanel.view.isHidden {
            togglePanel(rightSidePanel)
        }
        togglePanel(mainSidePanel)

        // Dismiss keyboard if it is showing.
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to:nil, from:nil, for:nil)
    }

    func onClickBraveButton(_ notification: Notification) {
        if !mainSidePanel.view.isHidden {
            togglePanel(mainSidePanel)
        }
        
        browserViewController.tabManager.selectedTab?.webView?.checkScriptBlockedAndBroadcastStats()
        togglePanel(rightSidePanel)
    }

    func togglePanel(_ panel: SidePanelBaseViewController) {
        let willShow = panel.view.isHidden
        if panel === mainSidePanel {
            leftSidePanelButtonAndUnderlay?.isSelected = willShow
            leftSidePanelButtonAndUnderlay?.hideUnderlay(!willShow)
        } else if panel.view.isHidden && !panel.canShow {
            return
        }

        if clickDetectionView.superview != nil {
            clickDetectionView.isUserInteractionEnabled = false
            UIView.animate(withDuration: 0.2, animations: {
                self.clickDetectionView.alpha = 0
                }, completion: { _ in
                    self.clickDetectionView.removeFromSuperview()
            } )
        }

        if willShow {
            clickDetectionView.alpha = 0
            clickDetectionView.isUserInteractionEnabled = true

            view.addSubview(clickDetectionView)
            clickDetectionView.snp.remakeConstraints {
                make in
                make.top.bottom.equalTo(browserViewController.view)
                make.right.equalTo(rightSidePanel.view.snp.left)
                make.left.equalTo(mainSidePanel.view.snp.right)
            }
            clickDetectionView.layoutIfNeeded()
            view.layoutSubviews()

            UIView.animate(withDuration: 0.25, animations: {
                self.clickDetectionView.alpha = 1
            }) 
        }

        if willShow {
            // this will set the profile and trigger DB query, be careful
            panel.setHomePanelDelegate(self)
        }
        panel.showPanel(willShow, parentSideConstraints: [leftConstraint, rightConstraint])
    }

    func updateBookmarkStatus(_ isBookmarked: Bool) {
//        let currentURL = browserViewController.urlBar.currentURL
        let currentTab = browserViewController.tabManager.selectedTab
        let currentURL = currentTab?.displayURL
        mainSidePanel.updateBookmarkStatus(isBookmarked, url: currentURL)
    }
}

extension BraveTopViewController : HomePanelDelegate {
    func homePanelDidRequestToSignIn(_ homePanel: HomePanel) {}
    func homePanelDidRequestToCreateAccount(_ homePanel: HomePanel) {}
    func homePanel(_ homePanel: HomePanel, didSelectURL url: URL) {
        browserViewController.urlBar.leaveSearchMode()
        browserViewController.tabManager.selectedTab?.loadRequest(URLRequest(url: url))
        togglePanel(mainSidePanel)
    }
}
