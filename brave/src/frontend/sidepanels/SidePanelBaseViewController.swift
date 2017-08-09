/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Storage
import SnapKit

class SidePanelBaseViewController : UIViewController {

    var browserViewController:BrowserViewController?

    // Wrap everything in a UIScrollView the view animation will not try to shrink the view
    // add subviews to containerView not self.view
    let containerView = UIView()

    var canShow: Bool { return true }

    // Set false for a right side panel
    var isLeftSidePanel = true
    
    let shadow = UIImageView()

    var parentSideConstraints: [Constraint?]?

    override func loadView() {
        self.view = UIScrollView(frame: UIScreen.main.bounds)
    }

    func viewAsScrollView() -> UIScrollView {
        return self.view as! UIScrollView
    }

    func setupContainerViewSize() {
        containerView.frame = CGRect(x: 0, y: 0, width: CGFloat(BraveUX.WidthOfSlideOut), height: self.view.frame.height)
        viewAsScrollView().contentSize = CGSize(width: containerView.frame.width, height: containerView.frame.height)
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        coordinator.animate(alongsideTransition: {
            _ in
            self.setupContainerViewSize()
            }, completion: nil)

        super.viewWillTransition(to: size, with: coordinator)
    }

    override func viewDidLoad() {
        viewAsScrollView().isScrollEnabled = false

        view.addSubview(containerView)
        setupContainerViewSize()
        containerView.backgroundColor = BraveUX.BackgroundColorForSideToolbars

        view.isHidden = true
    }

    /// This should just be called one time to initially setup the UI elements for the side panels
    func setupUIElements() {
        shadow.image = UIImage(named: "panel_shadow")
        shadow.contentMode = .scaleToFill
        shadow.alpha = 0.5

        if !isLeftSidePanel {
            shadow.transform = CGAffineTransform(scaleX: -1, y: 1)
        }

        if BraveUX.PanelShadowWidth > 0 {
            view.addSubview(shadow)

            shadow.snp.makeConstraints { make in
                if isLeftSidePanel {
                    make.right.top.equalTo(containerView)
                } else {
                    make.left.equalTo(view)
                    make.top.equalTo(view.superview!)
                }
                make.width.equalTo(BraveUX.PanelShadowWidth)

                let b = UIScreen.main.bounds
                make.height.equalTo(max(b.width, b.height))
            }
        }
    }

    func setupConstraints() {
        if shadow.image == nil { // arbitrary item check to see if func needs calling
            setupUIElements()
        }
    }

    func spaceForStatusBar() -> Double {
        let spacer = BraveApp.isIPhoneLandscape() ? 0.0 : 20.0
        return spacer
    }

    func verticalBottomPositionMainToolbar() -> Double {
        return Double(UIConstants.ToolbarHeight) + spaceForStatusBar()
    }

    func showPanel(_ showing: Bool, parentSideConstraints: [Constraint?]? = nil) {
        if (parentSideConstraints != nil) {
            self.parentSideConstraints = parentSideConstraints
        }

        if (showing) {
            view.isHidden = false
            setupConstraints()
        }
        view.layoutIfNeeded()

        let width = showing ? BraveUX.WidthOfSlideOut : 0
        let animation = {
            guard let superview = self.view.superview else { return }
            self.view.snp.remakeConstraints {
                make in
                if self.isLeftSidePanel {
                    make.bottom.left.top.equalTo(superview)
                } else {
                    make.bottom.right.top.equalTo(superview)
                }
                make.width.equalTo(width)
            }

            if let constraints = self.parentSideConstraints {
                if UIDevice.current.userInterfaceIdiom == .pad {
                    if let c = constraints.first, c != nil && self.isLeftSidePanel {
                        c!.update(offset: width)
                    } else if let c = constraints.last, c != nil && !self.isLeftSidePanel {
                        c!.update(offset: -width)
                    }
                } else {
                    for c in constraints where c != nil {
                        c!.update(offset: self.isLeftSidePanel ? width : -width)
                    }
                }
            }
            
            superview.layoutIfNeeded()
            guard let topVC = getApp().rootViewController.visibleViewController else { return }
            topVC.setNeedsStatusBarAppearanceUpdate()
        }

        var percentComplete = Double(view.frame.width) / Double(BraveUX.WidthOfSlideOut)
        if showing {
            percentComplete = 1.0 - percentComplete
        }
        let duration = 0.2 * percentComplete
        UIView.animate(withDuration: duration, animations: animation)
        if (!showing) { // for reasons unknown, wheh put in a animation completion block, this is called immediately
            postAsyncToMain(duration) { self.view.isHidden = true }
        }
    }

    func setHomePanelDelegate(_ delegate: HomePanelDelegate?) {}

}



