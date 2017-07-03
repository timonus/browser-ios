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
    static let ButtonContainerBorderColor = UIColor.black.withAlphaComponent(0.1)
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

    fileprivate var buttonContainerView: UIView!
    fileprivate var buttonContainerBottomBorderView: UIView!
    fileprivate var controllerContainerView: UIView!
    fileprivate var buttons: [UIButton] = []

    fileprivate var finishEditingButton: UIButton?
    fileprivate var editingPanel: HomePanel?

    override func viewDidLoad() {
        view.backgroundColor = HomePanelViewControllerUX.BackgroundColor

        let blur: UIVisualEffectView? = DeviceInfo.isBlurSupported() ? UIVisualEffectView(effect: UIBlurEffect(style: UIBlurEffectStyle.light)) : nil

        if let blur = blur {
            view.addSubview(blur)
        }

        buttonContainerView = UIView()
        buttonContainerView.backgroundColor = HomePanelViewControllerUX.BackgroundColor
        buttonContainerView.clipsToBounds = true
        buttonContainerView.accessibilityNavigationStyle = .combined
        buttonContainerView.accessibilityLabel = Strings.Panel_Chooser
        view.addSubview(buttonContainerView)

        self.buttonContainerBottomBorderView = UIView()
        buttonContainerView.addSubview(buttonContainerBottomBorderView)
        buttonContainerBottomBorderView.backgroundColor = HomePanelViewControllerUX.ButtonContainerBorderColor

        controllerContainerView = UIView()
        view.addSubview(controllerContainerView)

        blur?.snp_makeConstraints { make in
            make.edges.equalTo(self.view)
        }

        buttonContainerView.snp_makeConstraints { make in
            make.top.left.right.equalTo(self.view)
            make.height.equalTo(HomePanelViewControllerUX.ButtonContainerHeight)
        }

        buttonContainerBottomBorderView.snp_makeConstraints { make in
            make.top.equalTo(self.buttonContainerView.snp_bottom).offset(-1)
            make.left.right.bottom.equalTo(self.buttonContainerView)
        }

        controllerContainerView.snp_makeConstraints { make in
            make.top.equalTo(self.buttonContainerView.snp_bottom)
            make.left.right.bottom.equalTo(self.view)
        }

        self.panels = HomePanels().enabledPanels
        updateButtons()

        // Gesture recognizer to dismiss the keyboard in the URLBarView when the buttonContainerView is tapped
        let dismissKeyboardGestureRecognizer = UITapGestureRecognizer(target: self, action: #selector(HomePanelViewController.SELhandleDismissKeyboardGestureRecognizer(_:)))
        dismissKeyboardGestureRecognizer.cancelsTouchesInView = false
        buttonContainerView.addGestureRecognizer(dismissKeyboardGestureRecognizer)
    }

    func SELhandleDismissKeyboardGestureRecognizer(_ gestureRecognizer: UITapGestureRecognizer) {
        view.window?.rootViewController?.view.endEditing(true)
    }

    var selectedButtonIndex: Int? = nil {
        didSet {
            if oldValue == selectedButtonIndex {
                // Prevent flicker, allocations, and disk access: avoid duplicate view controllers.
                return
            }

            if let index = oldValue {
                if index < buttons.count {
                    let currentButton = buttons[index]
                    currentButton.isSelected = false
                }
            }

            hideCurrentPanel()

            if let index = selectedButtonIndex {
                if index < buttons.count {
                    let newButton = buttons[index]
                    newButton.isSelected = true
                }

                if index < panels.count {
                    let panel = self.panels[index].makeViewController(profile)
                    let accessibilityLabel = self.panels[index].accessibilityLabel
                    if let panelController = panel as? UINavigationController,
                     let rootPanel = panelController.viewControllers.first {
                        setupHomePanel(rootPanel, accessibilityLabel: accessibilityLabel)
                        self.showPanel(panelController)
                    } else {
                        setupHomePanel(panel, accessibilityLabel: accessibilityLabel)
                        self.showPanel(panel)
                    }
                }
            }
        }
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
        panel.view.snp_makeConstraints { make in
            make.top.equalTo(self.buttonContainerView.snp_bottom)
            make.left.right.bottom.equalTo(self.view)
        }
        panel.didMove(toParentViewController: self)
    }

    func SELtappedButton(_ sender: UIButton!) {
        for (index, button) in buttons.enumerated() {
            if (button == sender) {
                selectedButtonIndex = index
                delegate?.homePanelViewController(self, didSelectPanel: index)
                break
            }
        }
    }

    func endEditing(_ sender: UIButton!) {
        toggleEditingMode(false)
        editingPanel?.endEditing?()
        editingPanel = nil
    }

    fileprivate func updateButtons() {
        // Remove any existing buttons if we're rebuilding the toolbar.
        for button in buttons {
            button.removeFromSuperview()
        }
        buttons.removeAll()

        var prev: UIView? = nil
        for panel in panels {
            let button = UIButton()
            buttonContainerView.addSubview(button)
            button.addTarget(self, action: #selector(HomePanelViewController.SELtappedButton(_:)), for: UIControlEvents.touchUpInside)
            if let image = UIImage(named: "panelIcon\(panel.imageName)") {
                button.setImage(image, for: .normal)
            }
            if let image = UIImage(named: "panelIcon\(panel.imageName)Selected") {
                button.setImage(image, for: UIControlState.selected)
            }
            button.accessibilityLabel = panel.accessibilityLabel
            button.accessibilityIdentifier = panel.accessibilityIdentifier
            buttons.append(button)

            button.snp_remakeConstraints { make in
                let left = prev?.snp_right ?? self.view.snp_left
                make.left.equalTo(left)
                make.height.centerY.equalTo(self.buttonContainerView)
                make.width.equalTo(self.buttonContainerView).dividedBy(self.panels.count)
            }

            prev = button
        }
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

        if editing {
            let button = UIButton(type: UIButtonType.system)
            button.setTitle(Strings.Done, for: UIControlState.normal)
            button.addTarget(self, action: #selector(HomePanelViewController.endEditing(_:)), for: UIControlEvents.touchUpInside)
            button.transform = translateDown
            button.titleLabel?.textAlignment = .right
            self.buttonContainerView.addSubview(button)
            button.snp_makeConstraints { make in
                make.right.equalTo(self.buttonContainerView).offset(HomePanelViewControllerUX.EditDoneButtonRightPadding)
                make.centerY.equalTo(self.buttonContainerView)
            }
            self.buttonContainerView.layoutIfNeeded()
            finishEditingButton = button
        }

        UIView.animate(withDuration: 0.4, delay: 0, usingSpringWithDamping: 1, initialSpringVelocity: 0, options: UIViewAnimationOptions.allowUserInteraction, animations: { () -> Void in
            self.buttons.forEach { $0.transform = editing ? translateUp : CGAffineTransform.identity }
            self.finishEditingButton?.transform = editing ? CGAffineTransform.identity : translateDown
        }, completion: { _ in
            if !editing {
                self.finishEditingButton?.removeFromSuperview()
                self.finishEditingButton = nil
            }
        })
    }
}
