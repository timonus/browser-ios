import Foundation

import Shared
import Storage
import Deferred

let tagForManagerButton = (UUID() as NSUUID).hash
var noPopupOnSites: [String] = []

let kPrefName3rdPartyPasswordShortcutEnabled = "thirdPartyPasswordShortcutEnabled"

// Although this enum looks a bit bloated it is designed to completely centralize _all_ 3rd party PMs
//  To add or remove a PM this is the _only_ place that requires modifications (except adding image)

// To add new PM,
//  1. Add to enum case
//  2. Add image asset
//  3. Add static dicts/arrays below

enum ThirdPartyPasswordManagerType: Int {
    case showPicker = 0
    case onePassword, lastPass, bitwarden
    
    var prefId: Int { return self.rawValue }
    
    var displayName: String {
        return ThirdPartyPasswordManagerType.PMDisplayTitles[self] ?? ""
    }
    
    var cellLabel: String {
        return self == .showPicker ? "" : self.displayName
    }
    
    var icon: UIImage? {
        return UIImage.templateImage(named: ThirdPartyPasswordManagerType.PMIconTitle[self] ?? "")
    }
    
    func choice() -> (String, String, Int) {
        return (displayName, cellLabel, prefId)
    }
    
    static var choices: [Choice<String>] = {
        return PMTypes.map { type in Choice<String> { type.choice() } }
    }()
    
    // Same as icon, just sets a default as a fallback
    static func icon(_ type: ThirdPartyPasswordManagerType?) -> UIImage? {
        return (type ?? .showPicker).icon
    }
    
    static func passwordManager(_ action: String) -> ThirdPartyPasswordManagerType? {
        if action.contains("onepassword") {
            return .onePassword
        } else if action.contains("lastpass") {
            return .lastPass
        } else if action.contains("bitwarden") {
            return .bitwarden
        }
        return nil
    }
    
    // Must have explicit type
    // ALL PM types from above enum
    static fileprivate let PMTypes = [ ThirdPartyPasswordManagerType.showPicker, .onePassword, .lastPass, .bitwarden ]
    
    // Titles to be displayed for user selection/view
    static fileprivate let PMDisplayTitles: [ThirdPartyPasswordManagerType: String] = [
        .showPicker : "Show picker",
        .onePassword : "1Password",
        .lastPass : "LastPass",
        .bitwarden : "bitwarden"
    ]
    
    // PM image names
    static fileprivate let PMIconTitle: [ThirdPartyPasswordManagerType: String] = [
        .showPicker: "key",
        .onePassword : "passhelper_1pwd",
        .lastPass : "passhelper_lastpass",
        .bitwarden : "passhelper_bitwarden"
    ]
}

extension LoginsHelper {
    func thirdPartyHelper(_ enabled: @escaping (Bool)->Void) {
        BraveApp.is3rdPartyPasswordManagerInstalled(refreshLookup: false).upon {
            result in
            if !result {
                enabled(false)
            }
            enabled(true)
        }
    }

    func passwordManagerButtonSetup(_ callback: @escaping (Bool)->Void) {
        thirdPartyHelper { (enabled) in
            if !enabled {
                return // No 3rd party password manager installed
            }

            postAsyncToMain {
                [weak self] in
                let result = self?.browser?.webView?.stringByEvaluatingJavaScript(from: "document.querySelectorAll(\"input[type='password']\").length !== 0")
                if let ok = result, let me = self, ok == "true" {
                    let show = me.shouldShowPasswordManagerButton()
                    if show && UIDevice.current.userInterfaceIdiom != .pad {
                        me.addPasswordManagerButtonKeyboardAccessory()
                    }
                    callback(show)
                }
                else {
                    callback(false)
                }
            }
        }
    }

    func getKeyboardAccessory() -> UIView? {
        let keyboardWindow: UIWindow = UIApplication.shared.windows[1] as UIWindow
        let accessoryView: UIView = findFormAccessory(keyboardWindow)
        if accessoryView.description.hasPrefix("<UIWebFormAccessory") {
            return accessoryView.viewWithTag(tagForManagerButton)
        }
        return nil
    }

    func hideKeyboardAccessory() {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return
        }
        getKeyboardAccessory()?.removeFromSuperview()
    }
    
    func findFormAccessory(_ vw: UIView) -> UIView {
        if vw.description.hasPrefix("<UIWebFormAccessory") {
            return vw
        }
        for i in (0  ..< vw.subviews.count) {
            let subview = vw.subviews[i] as UIView;
            if subview.subviews.count > 0 {
                let subvw = self.findFormAccessory(subview)
                if subvw.description.hasPrefix("<UIWebFormAccessory") {
                    return subvw
                }
            }
        }
        return UIView()
    }

    func shouldShowPasswordManagerButton() -> Bool {
        if !OnePasswordExtension.shared().isAppExtensionAvailable() {
            return false
        }

        let windows = UIApplication.shared.windows.count
        if windows < 2 {
            return false
        }

        return true
    }

    func addPasswordManagerButtonKeyboardAccessory() {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return
        }

        let keyboardWindow: UIWindow = UIApplication.shared.windows[1] as UIWindow
        let accessoryView: UIView = findFormAccessory(keyboardWindow)
        if !accessoryView.description.hasPrefix("<UIWebFormAccessory") {
            return
        }
        
        if let old = accessoryView.viewWithTag(tagForManagerButton) {
            old.removeFromSuperview()
        }

        let image = ThirdPartyPasswordManagerType.icon(PasswordManagerButtonSetting.currentSetting)

        let managerButton = UIButton(frame: CGRect(x: 0, y: 0, width: 44, height: 44))
        managerButton.tag = tagForManagerButton
        managerButton.tintColor = BraveUX.DefaultBlue
        managerButton.setImage(image, for: UIControlState())
        managerButton.addTarget(self, action: #selector(LoginsHelper.onExecuteTapped), for: .touchUpInside)
        managerButton.sizeToFit()
        accessoryView.addSubview(managerButton)
        
        var managerButtonFrame = managerButton.frame
        managerButtonFrame.origin.x = rint((UIScreen.main.bounds.width - managerButtonFrame.width) / 2.0)
        managerButtonFrame.origin.y = rint((accessoryView.bounds.height - managerButtonFrame.height) / 2.0)
        managerButton.frame = managerButtonFrame
    }

    // recurse through items until the 1pw/lastpass/bitwarden share item is found
    fileprivate func selectShareItem(_ view: UIView, shareItemName: String) -> Bool {
        if shareItemName.characters.count == 0 {
            return false
        }

        for subview in view.subviews {
            if subview.description.contains("UICollectionViewControllerWrapperView") && (subview.subviews.first?.subviews.count)! > 1 {
                let wrapperCell = subview.subviews.first?.subviews[1] as? UICollectionViewCell
                if let collectionView = wrapperCell?.subviews.first?.subviews.first?.subviews.first as? UICollectionView {

                    // As a safe upper bound, just look at 10 items max
                    for i in 0..<10 {
                        let indexPath = IndexPath(item: i, section: 0)
                        let suspectCell = collectionView.cellForItem(at: indexPath)
                        if suspectCell == nil {
                            break;
                        }
                        if suspectCell?.subviews.first?.subviews.last?.description.contains(shareItemName) ?? false {
                            collectionView.delegate?.collectionView?(collectionView, didSelectItemAt:indexPath)
                            return true
                        }
                    }

                    return false
                }
            }
            let found = selectShareItem(subview, shareItemName: shareItemName)
            if found {
                return true
            }
        }
        return false
    }

    // MARK: Tap
    @objc func onExecuteTapped(_ sender: UIButton) {
        self.browser?.webView?.endEditing(true)

        let automaticallyPickPasswordShareItem = PasswordManagerButtonSetting.currentSetting != nil

        if automaticallyPickPasswordShareItem {
            UIActivityViewController.hackyHideSharePicker(on: true)

            UIView.animate(withDuration: 0.2, animations: {
                // dim screen to show user feedback button was tapped
                getApp().braveTopViewController.view.alpha = 0.5
            }) 
        }

        let passwordHelper = OnePasswordExtension.shared()
        passwordHelper.dismissBlock = { action in
            if PasswordManagerButtonSetting.currentSetting != nil {
                return
            }

            // At this point, user has not explicitly selected a currentSetting, let's choose one for them if a PW manager was picked
            if let setting = ThirdPartyPasswordManagerType.passwordManager(action) {
                PasswordManagerButtonSetting.currentSetting = setting
                // TODO: Move to currentSetting setter
                BraveApp.getPrefs()?.setInt(Int32(setting.prefId), forKey: kPrefName3rdPartyPasswordShortcutEnabled)
            }
        }

        passwordHelper.shareDidAppearBlock = {
            if !automaticallyPickPasswordShareItem {
                return
            }

            guard let itemToLookFor = PasswordManagerButtonSetting.currentSetting?.cellLabel else { return }
            let found = self.selectShareItem(getApp().window!, shareItemName: itemToLookFor)

            if !found {
                UIView.animate(withDuration: 0.2, animations: {
                    getApp().braveTopViewController.view.alpha = 1.0
                }) 

                UIActivityViewController.hackyHideSharePicker(on: false)
            }
        }

        passwordHelper.fillItem(intoWebView: browser!.webView!, for: getApp().browserViewController, sender: sender, showOnlyLogins: true) { (success, error) -> Void in
            if automaticallyPickPasswordShareItem {
                UIActivityViewController.hackyHideSharePicker(on: false)

                UIView.animate(withDuration: 0.1, animations: {
                    getApp().braveTopViewController.view.alpha = 1.0
                }) 
            }

            if !success {
                print("Failed to fill into webview: <\(error)>")
            }
        }
    }
}
