/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import SnapKit
import UIKit
import Storage        // For VisitType.

private struct HomePanelViewControllerUX {
    // Height of the top panel switcher button toolbar.
    static let ButtonContainerHeight: CGFloat = 0
    static let ButtonContainerBorderColor = BraveUX.Red
    static let BackgroundColor = UIConstants.PanelBackgroundColor
    static let EditDoneButtonRightPadding: CGFloat = -12
}

protocol HomePanelViewControllerDelegate: class {
    func homePanelViewController(_ homePanelViewController: HomePanelViewController, didSelectURL url: URL)
    func homePanelViewController(_ HomePanelViewController: HomePanelViewController, didSelectPanel panel: Int)
}

@objc
protocol HomePanel: class {
    weak var homePanelDelegate: HomePanelDelegate? { get set }
    @objc optional func endEditing()
}

struct HomePanelUX {
    static let EmptyTabContentOffset = -180
}

@objc
protocol HomePanelDelegate: class {
    func homePanel(_ homePanel: HomePanel, didSelectURL url: URL)
    @objc optional func homePanel(_ homePanel: HomePanel, didSelectURLString url: String, visitType: VisitType)
    @objc optional func homePanelWillEnterEditingMode(_ homePanel: HomePanel)
}

class HomePanelViewController: UIViewController, UITextFieldDelegate, HomePanelDelegate {
    var profile: Profile!
    var notificationToken: NSObjectProtocol!
    var panels: [HomePanelDescriptor]!
    var url: URL?
    weak var delegate: HomePanelViewControllerDelegate?

    fileprivate var controllerContainerView: UIView!

    fileprivate var finishEditingButton: UIButton?
    fileprivate var editingPanel: HomePanel?

    override func viewDidLoad() {
        view.backgroundColor = HomePanelViewControllerUX.BackgroundColor

        controllerContainerView = UIView()
        view.addSubview(controllerContainerView)

        controllerContainerView.snp.makeConstraints { make in
            make.top.equalTo(0)
            make.left.right.bottom.equalTo(self.view)
        }
        
        let topLine = UIView()
        let bottomLine = UIView()
        
        topLine.backgroundColor = PrivateBrowsing.singleton.isOn ? UIConstants.BorderColorDark : UIConstants.BorderColor
        bottomLine.backgroundColor = topLine.backgroundColor
        
        view.addSubview(topLine)
        view.addSubview(bottomLine)
        
        topLine.snp.makeConstraints { (make) in
            make.top.left.right.equalTo(0)
            make.height.equalTo(0.5)
        }
        
        bottomLine.snp.makeConstraints { (make) in
            make.bottom.left.right.equalTo(0)
            make.height.equalTo(0.5)
        }

        self.panels = HomePanels().enabledPanels
        
        let panel = self.panels[0].makeViewController(profile)
        let accessibilityLabel = self.panels[0].accessibilityLabel
        if let panelController = panel as? UINavigationController,
            let rootPanel = panelController.viewControllers.first {
            setupHomePanel(rootPanel, accessibilityLabel: accessibilityLabel)
            self.showPanel(panelController)
        } else {
            setupHomePanel(panel, accessibilityLabel: accessibilityLabel)
            self.showPanel(panel)
        }

        // Gesture recognizer to dismiss the keyboard in the URLBarView when the buttonContainerView is tapped
        let dismissKeyboardGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(HomePanelViewController.SELhandleDismissKeyboardGestureRecognizer(_:)))
        dismissKeyboardGestureRecognizer.cancelsTouchesInView = false
        controllerContainerView.addGestureRecognizer(dismissKeyboardGestureRecognizer)
    }

    func SELhandleDismissKeyboardGestureRecognizer(_ gestureRecognizer: UITapGestureRecognizer) {
        view.window?.rootViewController?.view.endEditing(true)
    }

    func setupHomePanel(_ panel: UIViewController, accessibilityLabel: String) {
        (panel as? HomePanel)?.homePanelDelegate = self
        panel.view.accessibilityNavigationStyle = .combined
        panel.view.accessibilityLabel = accessibilityLabel
    }

    fileprivate func hideCurrentPanel() {
        if let panel = childViewControllers.first {
            panel.willMove(toParentViewController: nil)
            panel.view.removeFromSuperview()
            panel.removeFromParentViewController()
        }
    }

    fileprivate func showPanel(_ panel: UIViewController) {
        addChildViewController(panel)
        controllerContainerView.addSubview(panel.view)
        panel.view.snp.makeConstraints { make in
            make.top.equalTo(0)
            make.left.right.bottom.equalTo(self.view)
        }
        panel.didMove(toParentViewController: self)
    }

    func endEditing(_ sender: UIButton!) {
        toggleEditingMode(false)
        editingPanel?.endEditing?()
        editingPanel = nil
    }

    func homePanel(_ homePanel: HomePanel, didSelectURLString url: String) {
        // If we can't get a real URL out of what should be a URL, we let the user's
        // default search engine give it a shot.
        // Typically we'll be in this state if the user has tapped a bookmarked search template
        // (e.g., "http://foo.com/bar/?query=%s"), and this will get them the same behavior as if
        // they'd copied and pasted into the URL bar.
        // See BrowserViewController.urlBar:didSubmitText:.
        guard let url = URIFixup.getURL(url) ??
                        profile.searchEngines.defaultEngine.searchURLForQuery(url) else {
            Logger.browserLogger.warning("Invalid URL, and couldn't generate a search URL for it.")
            return
        }

        return self.homePanel(homePanel, didSelectURL: url)
    }

    func homePanel(_ homePanel: HomePanel, didSelectURL url: URL) {
        delegate?.homePanelViewController(self, didSelectURL: url)
    }

    func homePanelWillEnterEditingMode(_ homePanel: HomePanel) {
        editingPanel = homePanel
        toggleEditingMode(true)
    }

    func toggleEditingMode(_ editing: Bool) {
        let translateDown = CGAffineTransform(translationX: 0, y: UIConstants.ToolbarHeight)
        let translateUp = CGAffineTransform(translationX: 0, y: -UIConstants.ToolbarHeight)

        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: UIViewAnimationOptions.allowUserInteraction, animations: { () -> Void in
            self.finishEditingButton?.transform = editing ? CGAffineTransform.identity : translateDown
        }, completion: { _ in
            if !editing {
                self.finishEditingButton?.removeFromSuperview()
                self.finishEditingButton = nil
            }
        })
    }
}
