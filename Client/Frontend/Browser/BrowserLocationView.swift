/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import Shared
import SnapKit
import XCGLogger

private let log = Logger.browserLogger

protocol BrowserLocationViewDelegate {
    func browserLocationViewDidTapLocation(_ browserLocationView: BrowserLocationView)
    func browserLocationViewDidLongPressLocation(_ browserLocationView: BrowserLocationView)
    func browserLocationViewDidTapReaderMode(_ browserLocationView: BrowserLocationView)
    /// - returns: whether the long-press was handled by the delegate; i.e. return `false` when the conditions for even starting handling long-press were not satisfied
    @discardableResult func browserLocationViewDidLongPressReaderMode(_ browserLocationView: BrowserLocationView) -> Bool
    func browserLocationViewLocationAccessibilityActions(_ browserLocationView: BrowserLocationView) -> [UIAccessibilityCustomAction]?
    func browserLocationViewDidTapReload(_ browserLocationView: BrowserLocationView)
    func browserLocationViewDidTapStop(_ browserLocationView: BrowserLocationView)
}

struct BrowserLocationViewUX {
    static let HostFontColor = UIColor.black
    static let BaseURLFontColor = UIColor.gray
    static let BaseURLPitch = 0.75
    static let HostPitch = 1.0
    static let LocationContentInset = 8

    static let Themes: [String: Theme] = {
        var themes = [String: Theme]()
        
        // TODO: Currently fontColor theme adjustments are being overriden by the textColor.
        // This should be cleaned up.
        
        var theme = Theme()
        theme.URLFontColor = BraveUX.LocationBarTextColor_URLBaseComponent
        theme.hostFontColor = BraveUX.LocationBarTextColor_URLHostComponent
        theme.textColor = BraveUX.LocationBarTextColor
        theme.backgroundColor = BraveUX.LocationBarBackgroundColor
        themes[Theme.NormalMode] = theme
        
        theme = Theme()
        theme.URLFontColor = BraveUX.LocationBarTextColor_URLBaseComponent
        theme.hostFontColor = BraveUX.LocationBarTextColor_URLHostComponent
        theme.textColor = .white
        theme.backgroundColor = BraveUX.LocationBarBackgroundColor_PrivateMode
        themes[Theme.PrivateMode] = theme

        return themes
    }()
}

class BrowserLocationView: UIView {
    var delegate: BrowserLocationViewDelegate?
    var longPressRecognizer: UILongPressGestureRecognizer!
    var tapRecognizer: UITapGestureRecognizer!

    // Variable colors should be overwritten by theme
    dynamic var baseURLFontColor: UIColor = BrowserLocationViewUX.BaseURLFontColor {
        didSet { updateTextWithURL() }
    }

    dynamic var hostFontColor: UIColor = BrowserLocationViewUX.HostFontColor {
        didSet { updateTextWithURL() }
    }
    
    // The color of the URL after it has loaded
    dynamic var fullURLFontColor: UIColor = BraveUX.LocationBarTextColor {
        didSet {
            updateTextWithURL()
            // Reset placeholder text, which will auto-adjust based on this new color
            self.urlTextField.attributedPlaceholder = self.placeholder
        }
    }

    var url: URL? {
        didSet {
            let wasHidden = lockImageView.isHidden
            lockImageView.isHidden = url?.scheme != "https"
            if wasHidden != lockImageView.isHidden {
                UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil)
            }
            updateTextWithURL()
            setNeedsUpdateConstraints()
        }
    }

    var readerModeState: ReaderModeState {
        get {
            return readerModeButton.readerModeState
        }
        set (newReaderModeState) {
            if newReaderModeState != self.readerModeButton.readerModeState {
                let wasHidden = readerModeButton.isHidden
                self.readerModeButton.readerModeState = newReaderModeState
                readerModeButton.isHidden = (newReaderModeState == ReaderModeState.Unavailable)
                if wasHidden != readerModeButton.isHidden {
                    UIAccessibilityPostNotification(UIAccessibilityLayoutChangedNotification, nil)
                }
                UIView.animate(withDuration: 0.1, animations: { () -> Void in
                    if newReaderModeState == ReaderModeState.Unavailable {
                        self.readerModeButton.alpha = 0.0
                    } else {
                        self.readerModeButton.alpha = 1.0
                    }
                    self.setNeedsUpdateConstraints()
                    self.layoutIfNeeded()
                })
            }
        }
    }

    /// Returns constant placeholder text with current URL color
    var placeholder: NSAttributedString {
        let placeholderText = Strings.Search_or_enter_address
        return NSAttributedString(string: placeholderText, attributes: [NSForegroundColorAttributeName: self.fullURLFontColor.withAlphaComponent(0.5)])
    }

    lazy var urlTextField: UITextField = {
        let urlTextField = DisplayTextField()

        self.longPressRecognizer.delegate = self
        urlTextField.addGestureRecognizer(self.longPressRecognizer)
        self.tapRecognizer.delegate = self
        urlTextField.addGestureRecognizer(self.tapRecognizer)
        urlTextField.keyboardAppearance = .dark
        urlTextField.attributedPlaceholder = self.placeholder
        urlTextField.accessibilityIdentifier = "url"
        urlTextField.accessibilityActionsSource = self
        urlTextField.font = UIConstants.DefaultChromeFont
        return urlTextField
    }()

    fileprivate lazy var lockImageView: UIImageView = {
        let lockImageView = UIImageView(image: UIImage(named: "lock_verified"))
        lockImageView.isHidden = true
        lockImageView.isAccessibilityElement = true
        lockImageView.contentMode = UIViewContentMode.center
        lockImageView.accessibilityLabel = Strings.Secure_connection
        return lockImageView
    }()

    fileprivate lazy var readerModeButton: ReaderModeButton = {
        let readerModeButton = ReaderModeButton(frame: CGRect.zero)
        readerModeButton.isHidden = true
        readerModeButton.addTarget(self, action: #selector(BrowserLocationView.SELtapReaderModeButton), for: .touchUpInside)
        readerModeButton.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(BrowserLocationView.SELlongPressReaderModeButton(_:))))
        readerModeButton.isAccessibilityElement = true
        readerModeButton.accessibilityLabel = Strings.Reader_View
        readerModeButton.accessibilityCustomActions = [UIAccessibilityCustomAction(name: Strings.Add_to_Reading_List, target: self, selector: #selector(BrowserLocationView.SELreaderModeCustomAction))]
        return readerModeButton
    }()

    let stopReloadButton = UIButton()

    func stopReloadButtonIsLoading(_ isLoading: Bool) {
        stopReloadButton.isSelected = isLoading
        stopReloadButton.accessibilityLabel = isLoading ? Strings.Stop : Strings.Reload
    }

    func didClickStopReload() {
        if stopReloadButton.accessibilityLabel == Strings.Stop {
            delegate?.browserLocationViewDidTapStop(self)
        } else {
            delegate?.browserLocationViewDidTapReload(self)
        }
    }

    // Prefixing with brave to distinguish from progress view that firefox has (which we hide)
    var braveProgressView: UIView = UIView(frame: CGRect(x: 0, y: 0, width: 0, height: CGFloat(URLBarViewUX.LocationHeight)))

    override init(frame: CGRect) {
        super.init(frame: frame)

        stopReloadButton.accessibilityIdentifier = "BrowserToolbar.stopReloadButton"
        
        stopReloadButton.setImage(UIImage.templateImageNamed("reload"), for: .normal)
        stopReloadButton.setImage(UIImage.templateImageNamed("stop"), for: .selected)
        // Setup the state dependent visuals
        stopReloadButtonIsLoading(false)
        
        stopReloadButton.addTarget(self, action: #selector(BrowserLocationView.didClickStopReload), for: UIControlEvents.touchUpInside)

        longPressRecognizer = UILongPressGestureRecognizer(target: self, action: #selector(BrowserLocationView.SELlongPressLocation(_:)))
        tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(BrowserLocationView.SELtapLocation(_:)))

        addSubview(urlTextField)
        addSubview(lockImageView)
        addSubview(readerModeButton)
        addSubview(stopReloadButton)

        braveProgressView.accessibilityLabel = "braveProgressView"
        braveProgressView.backgroundColor = PrivateBrowsing.singleton.isOn ? BraveUX.ProgressBarDarkColor : BraveUX.ProgressBarColor
        braveProgressView.layer.cornerRadius = BraveUX.TextFieldCornerRadius
        braveProgressView.layer.masksToBounds = true
        self.addSubview(braveProgressView)
        self.sendSubview(toBack: braveProgressView)
    }

    override var accessibilityElements: [Any]! {
        get {
            return [lockImageView, urlTextField, readerModeButton].filter { !$0.isHidden }
        }
        set {
            super.accessibilityElements = newValue
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func updateConstraints() {

        lockImageView.snp.makeConstraints { make in
            make.centerY.equalTo(self)
            make.left.equalTo(self).offset(BrowserLocationViewUX.LocationContentInset)
            make.width.equalTo(self.lockImageView.intrinsicContentSize.width)
        }

        readerModeButton.snp.makeConstraints { make in
            make.right.equalTo(stopReloadButton.snp.left).inset(-6)
            make.height.centerY.equalTo(self)
            make.width.equalTo(20)
        }

        stopReloadButton.snp.makeConstraints { make in
            make.right.equalTo(self).inset(BrowserLocationViewUX.LocationContentInset)
            make.height.centerY.equalTo(self)
            make.width.equalTo(20)
        }

        urlTextField.snp.remakeConstraints { make in
            make.top.bottom.equalTo(self)

            if lockImageView.isHidden {
                make.left.equalTo(self).offset(BrowserLocationViewUX.LocationContentInset)
            } else {
                make.left.equalTo(self.lockImageView.snp.right).offset(BrowserLocationViewUX.LocationContentInset)
            }

            if readerModeButton.isHidden {
                make.right.equalTo(self.stopReloadButton.snp.left)
            } else {
                make.right.equalTo(self.readerModeButton.snp.left).inset(-4)
            }
        }

        super.updateConstraints()
    }

    func SELtapReaderModeButton() {
        delegate?.browserLocationViewDidTapReaderMode(self)
    }

    func SELlongPressReaderModeButton(_ recognizer: UILongPressGestureRecognizer) {
        if recognizer.state == UIGestureRecognizerState.began {
            delegate?.browserLocationViewDidLongPressReaderMode(self)
        }
    }

    func SELlongPressLocation(_ recognizer: UITapGestureRecognizer) {
        if recognizer.state == UIGestureRecognizerState.began {
            delegate?.browserLocationViewDidLongPressLocation(self)
        }
    }

    func SELtapLocation(_ recognizer: UITapGestureRecognizer) {
        delegate?.browserLocationViewDidTapLocation(self)
    }

    func SELreaderModeCustomAction() -> Bool {
        return delegate?.browserLocationViewDidLongPressReaderMode(self) ?? false
    }

    fileprivate func updateTextWithURL() {
        if url == nil {
            urlTextField.text = ""
            return
        }

        if let httplessURL = url?.absoluteDisplayString, let baseDomain = url?.baseDomain {
            // Highlight the base domain of the current URL.
            let attributedString = NSMutableAttributedString(string: httplessURL)
            let nsRange = NSMakeRange(0, httplessURL.characters.count)
            attributedString.addAttribute(NSForegroundColorAttributeName, value: baseURLFontColor, range: nsRange)
            attributedString.colorSubstring(baseDomain, withColor: hostFontColor)
            attributedString.addAttribute(UIAccessibilitySpeechAttributePitch, value: NSNumber(value: BrowserLocationViewUX.BaseURLPitch), range: nsRange)
            attributedString.pitchSubstring(baseDomain, withPitch: BrowserLocationViewUX.HostPitch)
            urlTextField.attributedText = attributedString
        } else {
            // If we're unable to highlight the domain, just use the URL as is.
            urlTextField.text = url?.absoluteString
        }
        postAsyncToMain(0.1) {
            self.urlTextField.textColor = self.fullURLFontColor
        }
    }
}

extension BrowserLocationView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // If the longPressRecognizer is active, fail all other recognizers to avoid conflicts.
        return gestureRecognizer == longPressRecognizer
    }
}

extension BrowserLocationView: AccessibilityActionsSource {
    func accessibilityCustomActionsForView(_ view: UIView) -> [UIAccessibilityCustomAction]? {
        if view === urlTextField {
            return delegate?.browserLocationViewLocationAccessibilityActions(self)
        }
        return nil
    }
}

extension BrowserLocationView: Themeable {
    func applyTheme(_ themeName: String) {
        guard let theme = BrowserLocationViewUX.Themes[themeName] else {
            log.error("Unable to apply unknown theme \(themeName)")
            return
        }
        baseURLFontColor = theme.URLFontColor!
        hostFontColor = theme.hostFontColor!
        fullURLFontColor = theme.textColor!
        stopReloadButton.tintColor = theme.textColor!
        backgroundColor = theme.backgroundColor
    }
}

private class ReaderModeButton: UIButton {
    override init(frame: CGRect) {
        super.init(frame: frame)
        tintColor = BraveUX.ActionButtonTintColor
        setImage(UIImage(named: "reader.png")!.withRenderingMode(.alwaysTemplate), for: .normal)
        setImage(UIImage(named: "reader_active.png"), for: UIControlState.selected)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    var _readerModeState: ReaderModeState = ReaderModeState.Unavailable
    
    var readerModeState: ReaderModeState {
        get {
            return _readerModeState;
        }
        set (newReaderModeState) {
            _readerModeState = newReaderModeState
            switch _readerModeState {
            case .Available:
                self.isEnabled = true
                self.isSelected = false
            case .Unavailable:
                self.isEnabled = false
                self.isSelected = false
            case .Active:
                self.isEnabled = true
                self.isSelected = true
            }
        }
    }
}

private class DisplayTextField: UITextField {
    weak var accessibilityActionsSource: AccessibilityActionsSource?

    override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
        get {
            return accessibilityActionsSource?.accessibilityCustomActionsForView(self)
        }
        set {
            super.accessibilityCustomActions = newValue
        }
    }

    fileprivate override var canBecomeFirstResponder : Bool {
        return false
    }
}
