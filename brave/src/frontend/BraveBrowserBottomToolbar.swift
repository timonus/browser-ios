/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// This is bottom toolbar

import SnapKit
import Shared

extension UIImage{

    func alpha(_ value:CGFloat)->UIImage
    {
        UIGraphicsBeginImageContextWithOptions(self.size, false, 0.0)

        let ctx = UIGraphicsGetCurrentContext();
        let area = CGRect(x: 0, y: 0, width: self.size.width, height: self.size.height);

        ctx!.scaleBy(x: 1, y: -1);
        ctx!.translateBy(x: 0, y: -area.size.height);
        ctx!.setBlendMode(.multiply);
        ctx!.setAlpha(value);
        ctx!.draw(self.cgImage!, in: area);

        let newImage = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();

        return newImage!;
    }
}

class BraveBrowserBottomToolbar : BrowserToolbar {
    static var tabsCount = 1

    lazy var tabsButton: TabsButton = {
        let tabsButton = TabsButton()
        tabsButton.titleLabel.text = "\(tabsCount)"
        tabsButton.addTarget(self, action: #selector(BraveBrowserBottomToolbar.onClickShowTabs), for: UIControlEvents.touchUpInside)
        tabsButton.accessibilityLabel = Strings.Show_Tabs
        tabsButton.accessibilityIdentifier = "Toolbar.ShowTabs"
        return tabsButton
    }()

    var leftSpacer = UIView()
    var rightSpacer = UIView()

    fileprivate weak var clonedTabsButton: TabsButton?
    var tabsContainer = UIView()

    fileprivate static weak var currentInstance: BraveBrowserBottomToolbar?

    override init(frame: CGRect) {

        super.init(frame: frame)

        BraveBrowserBottomToolbar.currentInstance = self

        tabsContainer.addSubview(tabsButton)
        addSubview(tabsContainer)

        bringSubview(toFront: backButton)
        bringSubview(toFront: forwardButton)

        addSubview(leftSpacer)
        addSubview(rightSpacer)
        rightSpacer.isUserInteractionEnabled = false
        leftSpacer.isUserInteractionEnabled = false

        [backButton, forwardButton, shareButton].forEach {
            if let img = $0.currentImage {
                $0.setImage(img.alpha(BraveUX.BackForwardDisabledButtonAlpha), for: .disabled)
            }
        }
        
//        let longPress = UILongPressGestureRecognizer(target: self,
//                                                     action: #selector(longPressForPrivateTab(gestureRecognizer:)))
//        longPress.minimumPressDuration = 0.2
//        addTabButton.addGestureRecognizer(longPress)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func applyTheme(_ themeName: String) {
        super.applyTheme(themeName)
        tabsButton.applyTheme(themeName)
    }

    class func updateTabCountDuplicatedButton(_ count: Int, animated: Bool) {
        guard let instance = BraveBrowserBottomToolbar.currentInstance else { return }
        tabsCount = count
        URLBarView.updateTabCount(instance.tabsButton,
                                  clonedTabsButton: &instance.clonedTabsButton, count: count, animated: animated)
    }
    
    func longPressForPrivateTab(gestureRecognizer: UILongPressGestureRecognizer) {
        let alertController = UIAlertController(title: nil,
                                                message: nil,
                                                preferredStyle: .actionSheet)
        
        let cancelAction = UIAlertAction(title: Strings.Cancel,
                                         style: .cancel,
                                         handler: nil)
        alertController.addAction(cancelAction)
        
        if !PrivateBrowsing.singleton.isOn {
            let newPrivateTabAction = UIAlertAction(title: Strings.NewPrivateTabTitle,
                                                    style: .default,
                                                    handler: respondToNewPrivateTab(action:))
            alertController.addAction(newPrivateTabAction)
        }
        
        
        
        let newTabAction = UIAlertAction(title: Strings.NewTabTitle,
                                         style: .default,
                                         handler: respondToNewTab(action:))
        alertController.addAction(newTabAction)
        
        getApp().browserViewController.present(alertController, animated: true, completion: nil)
    }

    func setAlphaOnAllExceptTabButton(_ alpha: CGFloat) {
        actionButtons.forEach { $0.alpha = alpha }
    }

    func onClickShowTabs() {
        setAlphaOnAllExceptTabButton(0)
        BraveURLBarView.tabButtonPressed()
    }

    func leavingTabTrayMode() {
        setAlphaOnAllExceptTabButton(1.0)
    }

    override func updateConstraints() {
        super.updateConstraints()

        func common(_ make: ConstraintMaker, bottomInset: Int = 0) {
            make.top.equalTo(self)
            make.bottom.equalTo(self).inset(bottomInset)
            make.width.equalTo(self).dividedBy(5)
        }

        backButton.snp.remakeConstraints { make in
            common(make)
            make.left.equalTo(self)
        }

        forwardButton.snp.remakeConstraints { make in
            common(make)
            make.left.equalTo(backButton.snp.right)
        }

        shareButton.snp.remakeConstraints { make in
            common(make)
            make.centerX.equalTo(self)
        }

        searchButton.snp.remakeConstraints { make in
            common(make)
            make.left.equalTo(shareButton.snp.right)
        }

        tabsContainer.snp.remakeConstraints { make in
            common(make)
            make.right.equalTo(self)
        }

        tabsButton.snp.remakeConstraints { make in
            make.center.equalTo(tabsContainer)
            make.top.equalTo(tabsContainer)
            make.bottom.equalTo(tabsContainer)
            make.width.equalTo(tabsButton.snp.height)
        }
    }

    override func updatePageStatus(_ isWebPage: Bool) {
        super.updatePageStatus(isWebPage)
        
//        let isPrivate = getApp().browserViewController.tabManager.selectedTab?.isPrivate ?? false
//        if isPrivate {
//            postAsyncToMain(0) {
//                // ensure theme is applied after inital styling
//                self.applyTheme(Theme.PrivateMode)
//            }
//        }
    }
}

// MARK: - Long Press Gesture Recognizer Handlers for Adding Tabs
extension BraveBrowserBottomToolbar: BraveBrowserToolbarButtonActions {}
