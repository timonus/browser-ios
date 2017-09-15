/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Foundation
import Shared
import LocalAuthentication
import SwiftKeychainWrapper
import AudioToolbox

public let KeychainKeyPinLockInfo = "pinLockInfo"

struct PinUX {
    fileprivate static var ButtonSize: CGSize {
        get {
            if UIScreen.main.bounds.width < 375 {
                return CGSize(width: 55, height: 55)
            }
            else {
                return CGSize(width: 80, height: 80)
            }
        }
    }
    fileprivate static let DefaultForegroundColor = UIColor(rgb: 0x4a4a4a)
    fileprivate static let DefaultBackgroundColor = UIColor(rgb: 0x4a4a4a).withAlphaComponent(0.1)
    fileprivate static let SelectedBackgroundColor = BraveUX.BraveOrange
    fileprivate static let DefaultBorderWidth: CGFloat = 0.0
    fileprivate static let SelectedBorderWidth: CGFloat = 0.0
    fileprivate static let DefaultBorderColor = UIColor(rgb: 0x4a4a4a).cgColor
    fileprivate static let IndicatorSize: CGSize = CGSize(width: 14, height: 14)
    fileprivate static let IndicatorSpacing: CGFloat = 17.0
}

protocol PinViewControllerDelegate {
    func pinViewController(_ completed: Bool) -> Void
}

class PinViewController: UIViewController, PinViewControllerDelegate {
    
    var delegate: PinViewControllerDelegate?
    var pinView: PinLockView!
    
    override func loadView() {
        super.loadView()
        
        pinView = PinLockView(message: Strings.PinNew)
        pinView.codeCallback = { code in
            let view = ConfirmPinViewController()
            view.delegate = self
            view.initialPin = code
            self.navigationController?.pushViewController(view, animated: true)
        }
        view.addSubview(pinView)
        
        let pinViewSize = pinView.frame.size
        pinView.snp.makeConstraints { (make) in
            make.size.equalTo(pinViewSize)
            make.center.equalTo(self.view.center).offset(0)
        }
        
        title = Strings.PinSet
        view.backgroundColor = UIColor(rgb: 0xF8F8F8)
    }
    
    func pinViewController(_ completed: Bool) {
        delegate?.pinViewController(completed)
    }
    
}

class ConfirmPinViewController: UIViewController {
    
    var delegate: PinViewControllerDelegate?
    var pinView: PinLockView!
    var initialPin: String = ""
    
    override func loadView() {
        super.loadView()
        
        pinView = PinLockView(message: Strings.PinNewRe)
        pinView.codeCallback = { code in
            if code == self.initialPin {
                let pinLockInfo = AuthenticationKeychainInfo(passcode: code)
                if LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil) {
                    pinLockInfo.useTouchID = true
                }
                KeychainWrapper.setPinLockInfo(pinLockInfo)
                
                self.delegate?.pinViewController(true)
                self.navigationController?.popToRootViewController(animated: true)
            }
            else {
                self.pinView.tryAgain()
            }
        }
        view.addSubview(pinView)
        
        let pinViewSize = pinView.frame.size
        pinView.snp.makeConstraints { (make) in
            make.size.equalTo(pinViewSize)
            make.centerX.equalTo(self.view.center).offset(0)
            make.centerY.equalTo(self.view.center).offset(UIScreen.main.bounds.height < 667 ? 30 : 0)
        }
        
        title = Strings.PinSet
        view.backgroundColor = UIColor(rgb: 0xF8F8F8)
        
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: Strings.Cancel, style: .plain, target: self, action: #selector(SEL_cancel))
    }
    
    func SEL_cancel() {
        navigationController?.popToRootViewController(animated: true)
        delegate?.pinViewController(false)
    }
}

class PinProtectOverlayViewController: UIViewController {
    var blur: UIVisualEffectView!
    var pinView: PinLockView!
    
    var touchCanceled: Bool = false
    var successCallback: ((_ success: Bool) -> Void)?
    
    override func loadView() {
        super.loadView()
        
        blur = UIVisualEffectView(effect: UIBlurEffect(style: .light))
        view.addSubview(blur)
        
        pinView = PinLockView(message: Strings.PinEnterToUnlock)
        pinView.codeCallback = { code in
            if let pinLockInfo = KeychainWrapper.pinLockInfo() {
                if code == pinLockInfo.passcode {
                    self.successCallback?(true)
                    self.pinView.reset()
                }
                else {
                    self.successCallback?(false)
                    self.pinView.tryAgain()
                }
            }
        }
        view.addSubview(pinView)
        
        let pinViewSize = pinView.frame.size
        pinView.snp.makeConstraints { (make) in
            make.size.equalTo(pinViewSize)
            make.centerX.equalTo(self.view.center).offset(0)
            make.centerY.equalTo(self.view.center).offset(UIScreen.main.bounds.height < 667 ? 30 : 0)
        }
        
        blur.snp.makeConstraints { (make) in
            make.edges.equalTo(self.view)
        }
        
        start()
    }
    
    override var supportedInterfaceOrientations : UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.portrait
    }
    
    override var shouldAutorotate : Bool {
        return false
    }
    
    override var preferredInterfaceOrientationForPresentation : UIInterfaceOrientation {
        return UIInterfaceOrientation.portrait
    }
    
    func start() {
        getApp().browserViewController.view.endEditing(true)
        pinView.isHidden = true
        touchCanceled = false
    }
    
    func auth() {
        if touchCanceled {
            return
        }
        
        var authError: NSError? = nil
        let authenticationContext = LAContext()
        if authenticationContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &authError) {
            authenticationContext.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: Strings.PinFingerprintUnlock,
                reply: { [unowned self] (success, error) -> Void in
                    if success {
                        self.successCallback?(true)
                    }
                    else {
                        self.touchCanceled = true
                        postAsyncToMain {
                            self.pinView.isHidden = false
                        }
                    }
                })
        }
        else {
            self.touchCanceled = true
            postAsyncToMain {
                self.pinView.isHidden = false
            }
        }
    }
}

class PinLockView: UIView {
    var buttons: [PinButton] = []
    
    var codeCallback: ((_ code: String) -> Void)?
    
    var messageLabel: UILabel!
    var pinIndicatorView: PinIndicatorView!
    var deleteButton: UIButton!
    
    var pin: String = ""
    
    convenience init(message: String) {
        self.init()
        
        messageLabel = UILabel()
        messageLabel.text = message
        messageLabel.font = UIFont.systemFont(ofSize: 16, weight: UIFontWeightMedium)
        messageLabel.textColor = PinUX.DefaultForegroundColor
        messageLabel.sizeToFit()
        addSubview(messageLabel)
        
        pinIndicatorView = PinIndicatorView(size: 4)
        pinIndicatorView.sizeToFit()
        pinIndicatorView.index(0)
        addSubview(pinIndicatorView)
        
        for i in 1...10 {
            let button = PinButton()
            button.tag = i
            button.titleLabel.text = i == 10 ? "0" : "\(i)"
            button.addTarget(self, action: #selector(SEL_pinButton(_:)), for: .touchUpInside)
            addSubview(button)
            buttons.append(button)
        }
        
        deleteButton = UIButton()
        deleteButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: UIFontWeightMedium)
        deleteButton.setTitle(Strings.Delete, for: .normal)
        deleteButton.setTitleColor(PinUX.DefaultForegroundColor, for: .normal)
        deleteButton.setTitleColor(UIColor.black, for: .highlighted)
        deleteButton.addTarget(self, action: #selector(SEL_delete(_:)), for: .touchUpInside)
        deleteButton.sizeToFit()
        addSubview(deleteButton)
        
        layoutSubviews()
        sizeToFit()
    }
    
    override func layoutSubviews() {
        let spaceX: CGFloat = (350 - PinUX.ButtonSize.width * 3) / 4
        let spaceY: CGFloat = spaceX
        let w: CGFloat = PinUX.ButtonSize.width
        let h: CGFloat = PinUX.ButtonSize.height
        let frameWidth = spaceX * 2 + w * 3
        
        var messageLabelFrame = messageLabel.frame
        messageLabelFrame.origin.x = (frameWidth - messageLabelFrame.width) / 2
        messageLabelFrame.origin.y = 0
        messageLabel.frame = messageLabelFrame
        
        var indicatorViewFrame = pinIndicatorView.frame
        indicatorViewFrame.origin.x = (frameWidth - indicatorViewFrame.width) / 2
        indicatorViewFrame.origin.y = messageLabelFrame.maxY + 18
        pinIndicatorView.frame = indicatorViewFrame
        
        var x: CGFloat = 0
        var y: CGFloat = indicatorViewFrame.maxY + spaceY
        
        for i in 0..<buttons.count {
            if i == buttons.count - 1 {
                // Center last.
                x = (frameWidth - w) / 2
            }
            
            let button = buttons[i]
            var buttonFrame = button.frame
            buttonFrame.origin.x = rint(x)
            buttonFrame.origin.y = rint(y)
            buttonFrame.size.width = w
            buttonFrame.size.height = h
            button.frame = buttonFrame
            
            x = x + w + spaceX
            if x > frameWidth {
                x = 0
                y = y + h + spaceY
            }
        }
        
        let button0 = viewWithTag(10)
        let button9 = viewWithTag(9)
        var deleteButtonFrame = deleteButton.frame
        deleteButtonFrame.center = CGPoint(x: rint((button9?.frame ?? CGRect.zero).midX), y: rint((button0?.frame ?? CGRect.zero).midY))
        deleteButton.frame = deleteButtonFrame
    }
    
    override func sizeToFit() {
        let button0 = buttons[buttons.count - 1]
        let button9 = buttons[buttons.count - 2]
        
        let w = button9.frame.maxX
        let h = button0.frame.maxY
        var f = bounds
        f.size.width = w
        f.size.height = h
        frame = f
        bounds = CGRect(x: 0, y: 0, width: w, height: h)
    }
    
    func SEL_pinButton(_ sender: UIButton) {
        if pin.characters.count < 4 {
            let value = sender.tag == 10 ? 0 : sender.tag
            pin = pin + "\(value)"
            debugPrint(pin)
        }
        
        pinIndicatorView.index(pin.characters.count)
        
        if pin.characters.count == 4 && codeCallback != nil {
            codeCallback!(pin)
        }
    }
    
    func SEL_delete(_ sender: UIButton) {
        if pin.characters.count > 0 {
            pin = pin.substring(to: pin.characters.index(pin.endIndex, offsetBy: -1))
            pinIndicatorView.index(pin.characters.count)
            debugPrint(pin)
        }
    }
    
    func reset() {
        pinIndicatorView.index(0)
        pin = ""
    }
    
    func tryAgain() {
        AudioServicesPlayAlertSound(SystemSoundID(kSystemSoundID_Vibrate))
        
        let animation = CABasicAnimation(keyPath: "position")
        animation.duration = 0.06
        animation.repeatCount = 3
        animation.autoreverses = true
        animation.fromValue = NSValue(cgPoint: CGPoint(x: pinIndicatorView.frame.midX - 10, y: pinIndicatorView.frame.midY))
        animation.toValue = NSValue(cgPoint: CGPoint(x: pinIndicatorView.frame.midX + 10, y: pinIndicatorView.frame.midY))
        pinIndicatorView.layer.add(animation, forKey: "position")
        
        self.perform(#selector(reset), with: self, afterDelay: 0.4)
    }
}

class PinIndicatorView: UIView {
    var indicators: [UIView] = []
    
    var defaultColor: UIColor!
    
    convenience init(size: Int) {
        self.init()
        
        defaultColor = PinUX.DefaultForegroundColor
        
        for i in 0..<size {
            let view = UIView()
            view.tag = i
            view.layer.cornerRadius = PinUX.IndicatorSize.width / 2
            view.layer.masksToBounds = true
            view.layer.borderWidth = 1
            view.layer.borderColor = defaultColor.cgColor
            view.backgroundColor = PinUX.DefaultBackgroundColor
            addSubview(view)
            indicators.append(view)
        }
        
        setNeedsDisplay()
        layoutIfNeeded()
    }
    
    override func layoutSubviews() {
        let spaceX: CGFloat = PinUX.IndicatorSpacing
        var x: CGFloat = 0
        for i in 0..<indicators.count {
            let view = indicators[i]
            var viewFrame = view.frame
            viewFrame.origin.x = x
            viewFrame.origin.y = 0
            viewFrame.size.width = PinUX.IndicatorSize.width
            viewFrame.size.height = PinUX.IndicatorSize.height
            view.frame = viewFrame
            
            x = x + PinUX.IndicatorSize.width + spaceX
        }
    }
    
    override func sizeToFit() {
        let view = indicators[indicators.count - 1]
        var f = frame
        f.size.width = view.frame.maxX
        f.size.height = view.frame.maxY
        frame = f
    }
    
    func index(_ index: Int) -> Void {
        if index > indicators.count {
            return
        }
        
        // Fill
        for i in 0..<index {
            let view = indicators[i]
            view.backgroundColor = PinUX.SelectedBackgroundColor
            view.layer.borderColor = PinUX.SelectedBackgroundColor.cgColor
        }
        
        // Clear additional
        if index < indicators.count {
            for i in index..<indicators.count {
                let view = indicators[i]
                view.layer.borderWidth = PinUX.DefaultBorderWidth
                view.layer.borderColor = PinUX.DefaultBorderColor
                view.backgroundColor = PinUX.DefaultBackgroundColor
            }
        }
        
        // Outline next
        if index < indicators.count  {
            let view = indicators[index]
            view.layer.borderWidth = 2
        }
    }
}

class PinButton: UIControl {
    var titleLabel: UILabel!
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        layer.masksToBounds = true
        layer.borderWidth = PinUX.DefaultBorderWidth
        layer.borderColor = PinUX.DefaultBorderColor
        backgroundColor = PinUX.DefaultBackgroundColor
        
        titleLabel = UILabel(frame: frame)
        titleLabel.isUserInteractionEnabled = false
        titleLabel.textAlignment = .center
        titleLabel.font = UIFont.systemFont(ofSize: 30, weight: UIFontWeightMedium)
        titleLabel.textColor = PinUX.DefaultForegroundColor
        titleLabel.backgroundColor = UIColor.clear
        addSubview(titleLabel)
        setNeedsDisplay()
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)!
    }
    
    override var isHighlighted: Bool {
        didSet {
            if (isHighlighted) {
                backgroundColor = PinUX.SelectedBackgroundColor
                titleLabel.textColor = UIColor.white
                layer.borderColor = PinUX.SelectedBackgroundColor.cgColor
            }
            else {
                backgroundColor = PinUX.DefaultBackgroundColor
                titleLabel.textColor = PinUX.DefaultForegroundColor
                layer.borderColor = PinUX.DefaultBorderColor
            }
        }
    }
    
    override func layoutSubviews() {
        titleLabel.frame = bounds
        layer.cornerRadius = frame.height / 2.0
    }
    
    override func sizeToFit() {
        super.sizeToFit()
        
        var frame: CGRect = self.frame
        frame.size.width = PinUX.ButtonSize.width
        frame.size.height = PinUX.ButtonSize.height
        self.frame = frame
    }
}

extension KeychainWrapper {
    class func pinLockInfo() -> AuthenticationKeychainInfo? {
        NSKeyedUnarchiver.setClass(AuthenticationKeychainInfo.self, forClassName: "AuthenticationKeychainInfo")
        return KeychainWrapper.standard.object(forKey: KeychainKeyPinLockInfo) as? AuthenticationKeychainInfo
    }
    
    class func setPinLockInfo(_ info: AuthenticationKeychainInfo?) {
        NSKeyedArchiver.setClassName("AuthenticationKeychainInfo", for: AuthenticationKeychainInfo.self)
        if let info = info {
            KeychainWrapper.standard.set(info, forKey: KeychainKeyPinLockInfo)
        } else {
            KeychainWrapper.standard.removeObject(forKey: KeychainKeyPinLockInfo)
        }
    }
}
