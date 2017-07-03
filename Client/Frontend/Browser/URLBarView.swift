/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import Shared
import SnapKit
import XCGLogger

private let log = Logger.browserLogger

struct URLBarViewUX {
    static let TextFieldContentInset = UIOffsetMake(9, 5)
    static let LocationLeftPadding = 5
    static let LocationHeight = 28
    static let LocationContentOffset: CGFloat = 8
    static let TextFieldCornerRadius: CGFloat = 3
    static let TextFieldBorderWidth: CGFloat = 0
    // offset from edge of tabs button
    static let URLBarCurveOffset: CGFloat = 14
    static let URLBarCurveOffsetLeft: CGFloat = -10
    // buffer so we dont see edges when animation overshoots with spring
    static let URLBarCurveBounceBuffer: CGFloat = 8
    static let ProgressTintColor = UIColor(red:1, green:0.32, blue:0, alpha:1)

    static let TabsButtonRotationOffset: CGFloat = 1.5
    static let TabsButtonHeight: CGFloat = 18.0
    static let ToolbarButtonInsets = UIEdgeInsets(top: 10, left: 10, bottom: 10, right: 10)

    static let Themes: [String: Theme] = {
        var themes = [String: Theme]()
        var theme = Theme()
        theme.tintColor = UIConstants.PrivateModePurple
        theme.textColor = .white
        theme.buttonTintColor = UIConstants.PrivateModeActionButtonTintColor
        theme.backgroundColor = BraveUX.LocationContainerBackgroundColor_PrivateMode
        themes[Theme.PrivateMode] = theme

        theme = Theme()
        theme.tintColor = URLBarViewUX.ProgressTintColor
        theme.textColor = BraveUX.LocationBarTextColor
        theme.buttonTintColor = BraveUX.ActionButtonTintColor
        theme.backgroundColor = BraveUX.LocationContainerBackgroundColor
        themes[Theme.NormalMode] = theme

        return themes
    }()

    static func backgroundColorWithAlpha(_ alpha: CGFloat) -> UIColor {
        return UIConstants.AppBackgroundColor.withAlphaComponent(alpha)
    }
}

protocol URLBarDelegate: class {
    func urlBarDidPressTabs(_ urlBar: URLBarView)
    func urlBarDidPressReaderMode(_ urlBar: URLBarView)
    /// - returns: whether the long-press was handled by the delegate; i.e. return `false` when the conditions for even starting handling long-press were not satisfied
    func urlBarDidLongPressReaderMode(_ urlBar: URLBarView) -> Bool
    func urlBarDidPressStop(_ urlBar: URLBarView)
    func urlBarDidPressReload(_ urlBar: URLBarView)
    func urlBarDidEnterSearchMode(_ urlBar: URLBarView)
    func urlBarDidLeaveSearchMode(_ urlBar: URLBarView)
    func urlBarDidLongPressLocation(_ urlBar: URLBarView)
    func urlBarLocationAccessibilityActions(_ urlBar: URLBarView) -> [UIAccessibilityCustomAction]?
    func urlBarDidPressScrollToTop(_ urlBar: URLBarView)
    func urlBar(_ urlBar: URLBarView, didEnterText text: String)
    func urlBar(_ urlBar: URLBarView, didSubmitText text: String)
    func urlBarDisplayTextForURL(_ url: URL?) -> String?
}

class URLBarView: UIView {

    weak var delegate: URLBarDelegate?
    weak var browserToolbarDelegate: BrowserToolbarDelegate?
    var helper: BrowserToolbarHelper?
    var isTransitioning: Bool = false {
        didSet {
            if isTransitioning {
            }
        }
    }

    fileprivate var currentTheme: String = Theme.NormalMode

    var bottomToolbarIsHidden = false

    var locationTextField: ToolbarTextField?

    /// Overlay mode is the state where the lock/reader icons are hidden, the home panels are shown,
    /// and the Cancel button is visible (allowing the user to leave overlay mode). Overlay mode
    /// is *not* tied to the location text field's editing state; for instance, when selecting
    /// a panel, the first responder will be resigned, yet the overlay mode UI is still active.
    var inSearchMode = false

    lazy var locationView: BrowserLocationView = {
        let locationView = BrowserLocationView()
        locationView.translatesAutoresizingMaskIntoConstraints = false
        locationView.readerModeState = ReaderModeState.Unavailable
        locationView.delegate = self
        return locationView
    }()

    lazy var locationContainer: UIView = {
        let locationContainer = UIView()
        locationContainer.translatesAutoresizingMaskIntoConstraints = false

        // Enable clipping to apply the rounded edges to subviews.
        locationContainer.clipsToBounds = true

        locationContainer.layer.cornerRadius = URLBarViewUX.TextFieldCornerRadius
        locationContainer.layer.borderWidth = URLBarViewUX.TextFieldBorderWidth

        return locationContainer
    }()

    lazy var tabsButton: TabsButton = {
        let tabsButton = TabsButton()
        tabsButton.titleLabel.text = "0"
        tabsButton.addTarget(self, action: #selector(URLBarView.SELdidClickAddTab), for: UIControlEvents.touchUpInside)
        tabsButton.accessibilityIdentifier = "URLBarView.tabsButton"
        tabsButton.accessibilityLabel = Strings.Show_Tabs
        return tabsButton
    }()

    lazy var cancelButton: UIButton = {
        let cancelButton = InsetButton()
        cancelButton.setTitleColor(UIColor.black, for: .normal)
        let cancelTitle = Strings.Cancel
        cancelButton.setTitle(cancelTitle, for: UIControlState.normal)
        cancelButton.titleLabel?.font = UIConstants.DefaultChromeFont
        cancelButton.addTarget(self, action: #selector(URLBarView.SELdidClickCancel), for: UIControlEvents.touchUpInside)
        cancelButton.titleEdgeInsets = UIEdgeInsetsMake(10, 12, 10, 12)
        cancelButton.setContentHuggingPriority(1000, for: UILayoutConstraintAxis.horizontal)
        cancelButton.setContentCompressionResistancePriority(1000, for: UILayoutConstraintAxis.horizontal)
        cancelButton.alpha = 0
        return cancelButton
    }()

    lazy var scrollToTopButton: UIButton = {
        let button = UIButton()
        button.addTarget(self, action: #selector(URLBarView.SELtappedScrollToTopArea), for: UIControlEvents.touchUpInside)
        return button
    }()

    // TODO: After protocol removal, check what is necessary here
    
    lazy var shareButton: UIButton = { return UIButton() }()
    
    lazy var pwdMgrButton: UIButton = { return UIButton() }()

    lazy var forwardButton: UIButton = { return UIButton() }()

    lazy var backButton: UIButton = { return UIButton() }()
    
    // Required solely for protocol conforming
    lazy var addTabButton = { return UIButton() }()

    var actionButtons: [UIButton] {
        return [self.shareButton, self.forwardButton, self.backButton, self.pwdMgrButton, self.addTabButton]
    }

    // Used to temporarily store the cloned button so we can respond to layout changes during animation
    fileprivate weak var clonedTabsButton: TabsButton?

    fileprivate var rightBarConstraint: Constraint?
    fileprivate let defaultRightOffset: CGFloat = URLBarViewUX.URLBarCurveOffset - URLBarViewUX.URLBarCurveBounceBuffer

    var currentURL: URL? {
        get {
            return locationView.url
        }

        set(newURL) {
            locationView.url = newURL
        }
    }

    func updateTabsBarShowing() {}


    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        commonInit()
    }

    func commonInit() {
        backgroundColor = BraveUX.ToolbarsBackgroundSolidColor
        addSubview(scrollToTopButton)

        addSubview(tabsButton)
        addSubview(cancelButton)

        addSubview(shareButton)
        addSubview(pwdMgrButton)
        addSubview(forwardButton)
        addSubview(backButton)

        locationContainer.addSubview(locationView)
        addSubview(locationContainer)

        helper = BrowserToolbarHelper(toolbar: self)
        setupConstraints()

        // Make sure we hide any views that shouldn't be showing in non-overlay mode.
        updateViewsForSearchModeAndToolbarChanges()
    }

    func setupConstraints() {}

    override func updateConstraints() {
        super.updateConstraints()
    }

    func createLocationTextField() {
        guard locationTextField == nil else { return }

        locationTextField = ToolbarTextField()

        guard let locationTextField = locationTextField else { return }

        locationTextField.translatesAutoresizingMaskIntoConstraints = false
        locationTextField.autocompleteDelegate = self
        locationTextField.keyboardType = UIKeyboardType.webSearch
        locationTextField.keyboardAppearance = .dark
        locationTextField.autocorrectionType = UITextAutocorrectionType.no
        locationTextField.autocapitalizationType = UITextAutocapitalizationType.none
        locationTextField.returnKeyType = UIReturnKeyType.go
        locationTextField.clearButtonMode = UITextFieldViewMode.whileEditing
        locationTextField.font = UIConstants.DefaultChromeFont
        locationTextField.accessibilityIdentifier = "address"
        locationTextField.accessibilityLabel = Strings.Address_and_Search
        locationTextField.attributedPlaceholder = NSAttributedString(string: self.locationView.placeholder.string, attributes: [NSForegroundColorAttributeName: UIColor.gray])

        locationContainer.addSubview(locationTextField)

        locationTextField.snp_makeConstraints { make in
            make.edges.equalTo(self.locationView.urlTextField)
        }

        locationTextField.applyTheme(currentTheme)
    }

    func removeLocationTextField() {
        locationTextField?.removeFromSuperview()
        locationTextField = nil
    }

    // Ideally we'd split this implementation in two, one URLBarView with a toolbar and one without
    // However, switching views dynamically at runtime is a difficult. For now, we just use one view
    // that can show in either mode.
    func hideBottomToolbar(_ isHidden: Bool) {
        bottomToolbarIsHidden = isHidden
        setNeedsUpdateConstraints()
        // when we transition from portrait to landscape, calling this here causes
        // the constraints to be calculated too early and there are constraint errors
        if !bottomToolbarIsHidden {
            updateConstraintsIfNeeded()
        }
        updateViewsForSearchModeAndToolbarChanges()
    }

    func updateAlphaForSubviews(_ alpha: CGFloat) {
        self.tabsButton.alpha = alpha
        self.locationContainer.alpha = alpha
        self.actionButtons.forEach { $0.alpha = alpha }
    }

    func updateTabCount(_ count: Int, animated: Bool = true) {
        URLBarView.updateTabCount(tabsButton, clonedTabsButton: &clonedTabsButton, count: count, animated: animated)
    }

    class func updateTabCount(_ tabsButton: TabsButton, clonedTabsButton: inout TabsButton?, count: Int, animated: Bool = true) {
        let newCount = "\(getApp().tabManager.tabs.displayedTabsForCurrentPrivateMode.count)"
        tabsButton.accessibilityValue = newCount
        tabsButton.titleLabel.text = newCount
    }

    func updateProgressBar(_ progress: Float, dueToTabChange: Bool = false) {
        return // use Brave override only
    }

    func updateReaderModeState(_ state: ReaderModeState) {
        locationView.readerModeState = state
    }

    func setAutocompleteSuggestion(_ suggestion: String?) {
        locationTextField?.setAutocompleteSuggestion(suggestion)
    }

    func enterSearchMode(_ locationText: String?, pasted: Bool) {
        createLocationTextField()

        // Show the overlay mode UI, which includes hiding the locationView and replacing it
        // with the editable locationTextField.
        animateToSearchState(searchMode: true)

        delegate?.urlBarDidEnterSearchMode(self)

        // Bug 1193755 Workaround - Calling becomeFirstResponder before the animation happens
        // won't take the initial frame of the label into consideration, which makes the label
        // look squished at the start of the animation and expand to be correct. As a workaround,
        // we becomeFirstResponder as the next event on UI thread, so the animation starts before we
        // set a first responder.
        if pasted {
            // Clear any existing text, focus the field, then set the actual pasted text.
            // This avoids highlighting all of the text.
            self.locationTextField?.text = ""
            DispatchQueue.main.async {
                self.locationTextField?.becomeFirstResponder()
                self.locationTextField?.text = locationText
            }
        } else {
            // Copy the current URL to the editable text field, then activate it.
            self.locationTextField?.text = locationText

            // something is resigning the first responder immediately after setting it. A short delay for events to process fixes it.
            postAsyncToMain(0.1) {
                self.locationTextField?.becomeFirstResponder()
            }
        }
    }

    func leaveSearchMode(didCancel cancel: Bool = false) {
        locationTextField?.resignFirstResponder()
        animateToSearchState(searchMode: false, didCancel: cancel)
        delegate?.urlBarDidLeaveSearchMode(self)
    }

    func prepareSearchAnimation() {
        // Make sure everything is showing during the transition (we'll hide it afterwards).
        self.bringSubview(toFront: self.locationContainer)
        self.cancelButton.isHidden = false
        self.shareButton.isHidden = !self.bottomToolbarIsHidden
        self.forwardButton.isHidden = !self.bottomToolbarIsHidden
        self.backButton.isHidden = !self.bottomToolbarIsHidden
    }

    func transitionToSearch(_ didCancel: Bool = false) {
        self.cancelButton.alpha = inSearchMode ? 1 : 0
        self.shareButton.alpha = inSearchMode ? 0 : 1
        self.forwardButton.alpha = inSearchMode ? 0 : 1
        self.backButton.alpha = inSearchMode ? 0 : 1

        if inSearchMode {
            self.cancelButton.transform = CGAffineTransform.identity
            let tabsButtonTransform = CGAffineTransform(translationX: self.tabsButton.frame.width + URLBarViewUX.URLBarCurveOffset, y: 0)
            self.tabsButton.transform = tabsButtonTransform
            self.clonedTabsButton?.transform = tabsButtonTransform
            self.rightBarConstraint?.updateOffset(amount: URLBarViewUX.URLBarCurveOffset + URLBarViewUX.URLBarCurveBounceBuffer + tabsButton.frame.width)

            // Make the editable text field span the entire URL bar, covering the lock and reader icons.
            self.locationTextField?.snp_remakeConstraints { make in
                make.leading.equalTo(self.locationContainer).offset(URLBarViewUX.LocationContentOffset)
                make.top.bottom.trailing.equalTo(self.locationContainer)
            }
        } else {
            self.tabsButton.transform = CGAffineTransform.identity
            self.clonedTabsButton?.transform = CGAffineTransform.identity
            self.cancelButton.transform = CGAffineTransform(translationX: self.cancelButton.frame.width, y: 0)
            self.rightBarConstraint?.updateOffset(amount: defaultRightOffset)

            // Shrink the editable text field back to the size of the location view before hiding it.
            self.locationTextField?.snp_remakeConstraints { make in
                make.edges.equalTo(self.locationView.urlTextField)
            }
        }
    }

    func updateViewsForSearchModeAndToolbarChanges() {
        self.cancelButton.isHidden = !inSearchMode
        self.shareButton.isHidden = !self.bottomToolbarIsHidden || inSearchMode
        self.forwardButton.isHidden = !self.bottomToolbarIsHidden || inSearchMode
        self.backButton.isHidden = !self.bottomToolbarIsHidden || inSearchMode
    }

    func animateToSearchState(searchMode search: Bool, didCancel cancel: Bool = false) {
        prepareSearchAnimation()
        layoutIfNeeded()

        inSearchMode = search

        if !search {
            removeLocationTextField()
        }

        UIView.animate(withDuration: 0.3, delay: 0.0, usingSpringWithDamping: 0.85, initialSpringVelocity: 0.0, options: [], animations: { _ in
            self.transitionToSearch(cancel)
            self.setNeedsUpdateConstraints()
            self.layoutIfNeeded()
            }, completion: { _ in
                self.updateViewsForSearchModeAndToolbarChanges()
        })
    }

    func SELdidClickAddTab() {
        delegate?.urlBarDidPressTabs(self)
    }

    func SELdidClickCancel() {
        leaveSearchMode(didCancel: true)
    }

    func SELtappedScrollToTopArea() {
        delegate?.urlBarDidPressScrollToTop(self)
    }
}

extension URLBarView: BrowserToolbarProtocol {
    func updateBackStatus(_ canGoBack: Bool) {
        backButton.isEnabled = canGoBack
    }

    func updateForwardStatus(_ canGoForward: Bool) {
        forwardButton.isEnabled = canGoForward
    }

    func updateBookmarkStatus(_ isBookmarked: Bool) {
        getApp().braveTopViewController.updateBookmarkStatus(isBookmarked)
    }

    func updateReloadStatus(_ isLoading: Bool) {
        locationView.stopReloadButtonIsLoading(isLoading)
    }

    func updatePageStatus(_ isWebPage: Bool) {
        locationView.stopReloadButton.isEnabled = isWebPage
        shareButton.isEnabled = isWebPage
    }

    override var accessibilityElements: [Any]? {
        get {
            if inSearchMode {
                guard let locationTextField = locationTextField else { return nil }
                return [locationTextField, cancelButton]
            } else {
                if bottomToolbarIsHidden {
                    return [backButton, forwardButton, locationView, shareButton, tabsButton]
                } else {
                    return [locationView, tabsButton]
                }
            }
        }
        set {
            super.accessibilityElements = newValue
        }
    }
}

extension URLBarView: BrowserLocationViewDelegate {
    func browserLocationViewDidLongPressReaderMode(_ browserLocationView: BrowserLocationView) -> Bool {
        return delegate?.urlBarDidLongPressReaderMode(self) ?? false
    }

    func browserLocationViewDidTapLocation(_ browserLocationView: BrowserLocationView) {
        let locationText = delegate?.urlBarDisplayTextForURL(locationView.url as! URL)
        enterSearchMode(locationText, pasted: false)
    }

    func browserLocationViewDidLongPressLocation(_ browserLocationView: BrowserLocationView) {
        delegate?.urlBarDidLongPressLocation(self)
    }

    func browserLocationViewDidTapReload(_ browserLocationView: BrowserLocationView) {
        delegate?.urlBarDidPressReload(self)
    }

    func browserLocationViewDidTapStop(_ browserLocationView: BrowserLocationView) {
        delegate?.urlBarDidPressStop(self)
    }

    func browserLocationViewDidTapReaderMode(_ browserLocationView: BrowserLocationView) {
        delegate?.urlBarDidPressReaderMode(self)
    }

    func browserLocationViewLocationAccessibilityActions(_ browserLocationView: BrowserLocationView) -> [UIAccessibilityCustomAction]? {
        return delegate?.urlBarLocationAccessibilityActions(self)
    }
}

extension URLBarView: AutocompleteTextFieldDelegate {
    func autocompleteTextFieldShouldReturn(_ autocompleteTextField: AutocompleteTextField) -> Bool {
        guard let text = locationTextField?.text else { return true }
        delegate?.urlBar(self, didSubmitText: text)
        return true
    }

    func autocompleteTextField(_ autocompleteTextField: AutocompleteTextField, didEnterText text: String) {
        delegate?.urlBar(self, didEnterText: text)
    }

    func autocompleteTextFieldDidBeginEditing(_ autocompleteTextField: AutocompleteTextField) {
        autocompleteTextField.highlightAll()
    }

    func autocompleteTextFieldShouldClear(_ autocompleteTextField: AutocompleteTextField) -> Bool {
        delegate?.urlBar(self, didEnterText: "")
        return true
    }
}

// MARK: UIAppearance
extension URLBarView {

    dynamic var cancelTextColor: UIColor? {
        get { return cancelButton.titleColor(for: .normal) }
        set { return cancelButton.setTitleColor(newValue, for: .normal) }
    }

    dynamic var actionButtonTintColor: UIColor? {
        get { return helper?.buttonTintColor }
        set {
            guard let value = newValue else { return }
            helper?.buttonTintColor = value
        }
    }

}

extension URLBarView: Themeable {

    func applyTheme(_ themeName: String) {
        locationView.applyTheme(themeName)
        locationTextField?.applyTheme(themeName)

        guard let theme = URLBarViewUX.Themes[themeName] else {
            log.error("Unable to apply unknown theme \(themeName)")
            return
        }

        currentTheme = themeName
        cancelTextColor = theme.textColor
        actionButtonTintColor = theme.buttonTintColor
        locationContainer.backgroundColor = theme.backgroundColor

        tabsButton.applyTheme(themeName)
    }
}

/* Code for drawing the urlbar curve */
class CurveView: UIView {}

class ToolbarTextField: AutocompleteTextField {
    static let Themes: [String: Theme] = {
        var themes = [String: Theme]()
        var theme = Theme()
        theme.backgroundColor = BraveUX.LocationBarEditModeBackgroundColor_Private
        theme.textColor = BraveUX.LocationBarEditModeTextColor_Private
        theme.buttonTintColor = UIColor.white
        theme.highlightColor = UIConstants.PrivateModeTextHighlightColor
        themes[Theme.PrivateMode] = theme

        theme = Theme()
        theme.backgroundColor = BraveUX.LocationBarEditModeBackgroundColor
        theme.textColor = BraveUX.LocationBarEditModeTextColor
        theme.highlightColor = AutocompleteTextFieldUX.HighlightColor
        themes[Theme.NormalMode] = theme

        return themes
    }()

    dynamic var clearButtonTintColor: UIColor? {
        didSet {
            // Clear previous tinted image that's cache and ask for a relayout
            tintedClearImage = nil
            setNeedsLayout()
        }
    }

    fileprivate var tintedClearImage: UIImage?

    override init(frame: CGRect) {
        super.init(frame: frame)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()

        // Since we're unable to change the tint color of the clear image, we need to iterate through the
        // subviews, find the clear button, and tint it ourselves. Thanks to Mikael Hellman for the tip:
        // http://stackoverflow.com/questions/27944781/how-to-change-the-tint-color-of-the-clear-button-on-a-uitextfield
        for view in subviews as [UIView] {
            if let button = view as? UIButton {
                if let image = button.image(for: .normal) {
                    if tintedClearImage == nil {
                        tintedClearImage = tintImage(image, color: clearButtonTintColor)
                    }

                    if button.imageView?.image != tintedClearImage {
                        button.setImage(tintedClearImage, for: .normal)
                    }
                }
            }
        }
    }

    fileprivate func tintImage(_ image: UIImage, color: UIColor?) -> UIImage {
        guard let color = color else { return image }

        let size = image.size

        UIGraphicsBeginImageContextWithOptions(size, false, 2)
        let context = UIGraphicsGetCurrentContext()
        image.draw(at: CGPoint.zero, blendMode: CGBlendMode.normal, alpha: 1.0)

        context!.setFillColor(color.cgColor)
        context!.setBlendMode(CGBlendMode.sourceIn)
        context!.setAlpha(1.0)

        let rect = CGRect(
            x: CGPoint.zero.x,
            y: CGPoint.zero.y,
            width: image.size.width,
            height: image.size.height)
        UIGraphicsGetCurrentContext()!.fill(rect)
        let tintedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return tintedImage!
    }
}

extension ToolbarTextField: Themeable {
    func applyTheme(_ themeName: String) {
        guard let theme = ToolbarTextField.Themes[themeName] else {
            log.error("Unable to apply unknown theme \(themeName)")
            return
        }
        
        backgroundColor = theme.backgroundColor
        textColor = theme.textColor
        clearButtonTintColor = theme.buttonTintColor
        highlightColor = theme.highlightColor!
    }
}
