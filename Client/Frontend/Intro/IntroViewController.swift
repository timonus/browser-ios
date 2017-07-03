/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import SnapKit
import Shared

struct IntroViewControllerUX {
    static let Width = 375
    static let Height = 667

    static let CardSlides = ["page1", "page2", "page3", "page4"]
    static let NumberOfCards = CardSlides.count

    static let PagerCenterOffsetFromScrollViewBottom = 20

    static let StartBrowsingButtonTitle = Strings.Start_Browsing
    static let StartBrowsingButtonColor = UIColor(rgb: 0x363B40)
    static let StartBrowsingButtonHeight = 120

    static let CardTextLineHeight = CGFloat(6)

    static let CardTitlePage1 = Strings.Welcome_to_Brave
    static let CardTextPage1 = Strings.Get_ready_to_experience_a_Faster

    static let CardTitlePage2 = Strings.Brave_is_Faster
    static let CardTextPage2 = Strings.Brave_blocks_ads_and_trackers

    static let CardTitlePage3 = Strings.Brave_keeps_you_safe_as_you_browse
    static let CardTextPage3 = Strings.Browsewithusandyourprivacyisprotected

    static let CardTitlePage4 = Strings.Incaseyouhitaspeedbump
    static let CardTextPage4 = Strings.TapTheBraveButtonToTemporarilyDisable

    static let CardTextSyncOffsetFromCenter = 25
    static let Card3ButtonOffsetFromCenter = -10

    static let FadeDuration = 0.25

    static let BackForwardButtonEdgeInset = 20
}

let IntroViewControllerSeenProfileKey = "IntroViewControllerSeen"

protocol IntroViewControllerDelegate: class {
    func introViewControllerDidFinish(_ introViewController: IntroViewController)
    #if !BRAVE
    func introViewControllerDidRequestToLogin(_ introViewController: IntroViewController)
    #endif
}

class IntroViewController: UIViewController, UIScrollViewDelegate {
    weak var delegate: IntroViewControllerDelegate?

    var slides = [UIImage]()
    var cards = [UIImageView]()
    var introViews = [UIView]()
    var titleLabels = [InsetLabel]()
    var textLabels = [InsetLabel]()

    var startBrowsingButton: UIButton!
    var introView: UIView?
    var slideContainer: UIView!
    var pageControl: UIPageControl!
    var backButton: UIButton!
    var forwardButton: UIButton!

    var bgColors = [UIColor]()

    fileprivate var scrollView: IntroOverlayScrollView!

    var slideVerticalScaleFactor: CGFloat = 1.0

    var arrow: UIImageView?

    override func viewDidLoad() {
        view.backgroundColor = UIColor.white

        bgColors.append(BraveUX.BraveButtonMessageInUrlBarColor)
        bgColors.append(UIColor(colorLiteralRed: 69/255.0, green: 155/255.0, blue: 255/255.0, alpha: 1.0))
        bgColors.append(UIColor(colorLiteralRed: 254/255.0, green: 202/255.0, blue: 102/255.0, alpha: 1.0))
        bgColors.append(BraveUX.BraveButtonMessageInUrlBarColor)
        bgColors.append(BraveUX.BraveButtonMessageInUrlBarColor)

        arrow = UIImageView(image: UIImage(named: "screen_5_arrow"))

        // scale the slides down for iPhone 4S
        if view.frame.height <=  480 {
            slideVerticalScaleFactor = 1.33
        }

        for slideName in IntroViewControllerUX.CardSlides {
            if let image = UIImage(named: slideName) {
                slides.append(image)
            }
        }

        startBrowsingButton = UIButton()
        startBrowsingButton.backgroundColor = IntroViewControllerUX.StartBrowsingButtonColor
        startBrowsingButton.setTitle(IntroViewControllerUX.StartBrowsingButtonTitle, for: UIControlState.normal)
        startBrowsingButton.setTitleColor(UIColor.white, for: .normal)
        startBrowsingButton.addTarget(self, action: #selector(IntroViewController.SELstartBrowsing), for: UIControlEvents.touchUpInside)
        startBrowsingButton.contentHorizontalAlignment = .left
        startBrowsingButton.contentVerticalAlignment = .top
        startBrowsingButton.contentEdgeInsets = UIEdgeInsetsMake(20, 20, 0, 0);

        view.addSubview(startBrowsingButton)
        startBrowsingButton.snp_makeConstraints { (make) -> Void in
            make.left.right.bottom.equalTo(self.view)
            make.height.equalTo(self.view.frame.width <= 320 ? 60 : IntroViewControllerUX.StartBrowsingButtonHeight)
        }

        scrollView = IntroOverlayScrollView()
        scrollView.backgroundColor = UIColor.clear
        scrollView.accessibilityLabel = Strings.IntroTourCarousel
        scrollView.delegate = self
        scrollView.bounces = false
        scrollView.isPagingEnabled = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.contentSize = CGSize(width: scaledWidthOfSlide * CGFloat(IntroViewControllerUX.NumberOfCards), height: scaledHeightOfSlide)
        view.addSubview(scrollView)

        slideContainer = UIView()
        slideContainer.backgroundColor = bgColors[0]
        for i in 0..<IntroViewControllerUX.NumberOfCards {
            var imageView = UIImageView(frame: CGRect(x: CGFloat(i)*scaledWidthOfSlide, y: 0, width: scaledWidthOfSlide, height: scaledHeightOfSlide))
            imageView.image = slides[i]
            slideContainer.addSubview(imageView)
        }

        scrollView.addSubview(slideContainer)
        scrollView.snp_makeConstraints { (make) -> Void in
            make.left.right.top.equalTo(self.view)
            make.bottom.equalTo(startBrowsingButton.snp_top)
        }

        pageControl = UIPageControl()
        pageControl.pageIndicatorTintColor = UIColor.black.withAlphaComponent(0.3)
        pageControl.currentPageIndicatorTintColor = UIColor.black
        pageControl.numberOfPages = IntroViewControllerUX.NumberOfCards
        pageControl.accessibilityIdentifier = "pageControl"
        pageControl.addTarget(self, action: #selector(IntroViewController.changePage), for: UIControlEvents.valueChanged)

        view.addSubview(pageControl)
        pageControl.snp_makeConstraints { (make) -> Void in
            make.left.equalTo(self.scrollView).offset(20.0)
            make.centerY.equalTo(self.startBrowsingButton.snp_top).offset(-IntroViewControllerUX.PagerCenterOffsetFromScrollViewBottom)
        }


        func addCard(_ text: String, title: String) {
            let introView = UIView()
            self.introViews.append(introView)
            self.addLabelsToIntroView(introView, text: text, title: title)
        }

        addCard(IntroViewControllerUX.CardTextPage1, title: IntroViewControllerUX.CardTitlePage1)
        addCard(IntroViewControllerUX.CardTextPage2, title: IntroViewControllerUX.CardTitlePage2)
        addCard(IntroViewControllerUX.CardTextPage3, title: IntroViewControllerUX.CardTitlePage3)
        addCard(IntroViewControllerUX.CardTextPage4, title: IntroViewControllerUX.CardTitlePage4)

        
        // Add all the cards to the view, make them invisible with zero alpha

        for introView in introViews {
            introView.alpha = 0
            self.view.addSubview(introView)
            introView.snp_makeConstraints { (make) -> Void in
                make.top.equalTo(self.slideContainer.snp_bottom)
                make.bottom.equalTo(self.startBrowsingButton.snp_top)
                make.left.right.equalTo(self.view)
            }
        }

        // Make whole screen scrollable by bringing the scrollview to the top
        view.bringSubview(toFront: scrollView)
        view.bringSubview(toFront: pageControl)


        // Activate the first card
        setActiveIntroView(introViews[0], forPage: 0)

        setupDynamicFonts()
    }

    func setupTextOnButton() {
        startBrowsingButton.contentHorizontalAlignment = .left
        startBrowsingButton.contentVerticalAlignment = .top
        startBrowsingButton.contentEdgeInsets = UIEdgeInsetsMake(20, 20, 0, 0);
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(IntroViewController.SELDynamicFontChanged(_:)), name: NotificationDynamicFontChanged, object: nil)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: NotificationDynamicFontChanged, object: nil)

        getApp().profile!.prefs.setInt(1, forKey: IntroViewControllerSeenProfileKey)

        if UIDevice.current.userInterfaceIdiom == .pad {
            (getApp().browserViewController as! BraveBrowserViewController).presentOptInDialog()
        }
    }

    func SELDynamicFontChanged(_ notification: Notification) {
        guard notification.name == NotificationDynamicFontChanged else { return }
        setupDynamicFonts()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        scrollView.snp_remakeConstraints { (make) -> Void in
            make.left.right.top.equalTo(self.view)
            make.bottom.equalTo(self.startBrowsingButton.snp_top)
        }

        for i in 0..<IntroViewControllerUX.NumberOfCards {
            if let imageView = slideContainer.subviews[i] as? UIImageView {
                imageView.frame = CGRect(x: CGFloat(i)*scaledWidthOfSlide, y: 0, width: scaledWidthOfSlide, height: scaledHeightOfSlide)
                imageView.contentMode = UIViewContentMode.scaleAspectFit
            }
        }
        slideContainer.frame = CGRect(x: 0, y: 0, width: scaledWidthOfSlide * CGFloat(IntroViewControllerUX.NumberOfCards), height: scaledHeightOfSlide)
        scrollView.contentSize = CGSize(width: slideContainer.frame.width, height: slideContainer.frame.height)
    }

    override var prefersStatusBarHidden : Bool {
        return true
    }

    override var shouldAutorotate : Bool {
        return false
    }

    override var supportedInterfaceOrientations : UIInterfaceOrientationMask {
        // This actually does the right thing on iPad where the modally
        // presented version happily rotates with the iPad orientation.
        return UIInterfaceOrientationMask.portrait
    }

    func SELstartBrowsing() {
        delegate?.introViewControllerDidFinish(self)
    }

    func SELback() {
        if introView == introViews[1] {
            setActiveIntroView(introViews[0], forPage: 0)
            scrollView.scrollRectToVisible(scrollView.subviews[0].frame, animated: true)
            pageControl.currentPage = 0
        } else if introView == introViews[2] {
            setActiveIntroView(introViews[1], forPage: 1)
            scrollView.scrollRectToVisible(scrollView.subviews[1].frame, animated: true)
            pageControl.currentPage = 1
        }
    }

    func SELforward() {
        if introView == introViews[0] {
            setActiveIntroView(introViews[1], forPage: 1)
            scrollView.scrollRectToVisible(scrollView.subviews[1].frame, animated: true)
            pageControl.currentPage = 1
        } else if introView == introViews[1] {
            setActiveIntroView(introViews[2], forPage: 2)
            scrollView.scrollRectToVisible(scrollView.subviews[2].frame, animated: true)
            pageControl.currentPage = 2
        }
    }

    func SELlogin() {
        #if !BRAVE
		delegate?.introViewControllerDidRequestToLogin(self)
        #endif
    }

    fileprivate var accessibilityScrollStatus: String {
        return String(format: Strings.IntroductorySlideXofX_template, NumberFormatter.localizedString(from: NSNumber(value: pageControl.currentPage+1), number: .decimal), NumberFormatter.localizedString(from: NSNumber(value: IntroViewControllerUX.NumberOfCards), number: .decimal))
    }

    func changePage() {
        let swipeCoordinate = CGFloat(pageControl.currentPage) * scrollView.frame.size.width
        scrollView.setContentOffset(CGPoint(x: swipeCoordinate, y: 0), animated: true)
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        // Need to add this method so that tapping the pageControl will also change the card texts. 
        // scrollViewDidEndDecelerating waits until the end of the animation to calculate what card it's on.
        scrollViewDidEndDecelerating(scrollView)
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let page = Int(scrollView.contentOffset.x / scrollView.frame.size.width)
        pageControl.currentPage = page
        if page < introViews.count {
            setActiveIntroView(introViews[page], forPage: page)
        }
    }


    fileprivate func setActiveIntroView(_ newIntroView: UIView, forPage page: Int) {

        if introView != newIntroView {
            UIView.animate(withDuration: IntroViewControllerUX.FadeDuration, animations: { () -> Void in
                self.introView?.alpha = 0
                self.introView = newIntroView
                newIntroView.alpha = 1.0
            }, completion: { _ in
            })
        }

        if page < bgColors.count {
            slideContainer.backgroundColor = bgColors[page]
        }
    }

    fileprivate var scaledWidthOfSlide: CGFloat {
        return view.frame.width
    }

    fileprivate var scaledHeightOfSlide: CGFloat {
        return (view.frame.width / slides[0].size.width) * slides[0].size.height / slideVerticalScaleFactor
    }

    fileprivate func attributedStringForLabel(_ text: String) -> NSMutableAttributedString {
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.lineSpacing = IntroViewControllerUX.CardTextLineHeight
        paragraphStyle.alignment = .center

        let string = NSMutableAttributedString(string: text)
        string.addAttribute(NSParagraphStyleAttributeName, value: paragraphStyle, range: NSMakeRange(0, string.length))
        return string
    }

    fileprivate func addLabelsToIntroView(_ introView: UIView, text: String, title: String = "") {
        let label = InsetLabel()

        label.numberOfLines = 0
        label.attributedText = attributedStringForLabel(text)
        label.textAlignment = .left
        textLabels.append(label)

        addViewsToIntroView(introView, label: label, title: title)
    }

    fileprivate func addViewsToIntroView(_ introView: UIView, label: UIView, title: String = "") {
        introView.addSubview(label)
        label.snp_makeConstraints { (make) -> Void in
            make.centerY.equalTo(introView)
            make.left.equalTo(introView).offset(20)
            make.width.equalTo(self.view.frame.width <= 320 ? 260 : 300) // TODO Talk to UX about small screen sizes
        }

        if !title.isEmpty {
            let titleLabel = InsetLabel()
            if (title == IntroViewControllerUX.CardTitlePage1) {
                titleLabel.textColor = BraveUX.BraveButtonMessageInUrlBarColor
            }

            titleLabel.numberOfLines = 0
            titleLabel.textAlignment = NSTextAlignment.left
            titleLabel.lineBreakMode = .byWordWrapping
            titleLabel.text = title
            titleLabels.append(titleLabel)
            introView.addSubview(titleLabel)
            titleLabel.snp_makeConstraints { (make) -> Void in
                make.top.equalTo(introView)
                make.bottom.equalTo(label.snp_top)
                make.left.equalTo(titleLabel.superview!).offset(20)
                make.width.equalTo(self.view.frame.width <= 320 ? 260 : 300) // TODO Talk to UX about small screen sizes
            }
        }

    }

    fileprivate func setupDynamicFonts() {
        let biggerIt = self.view.frame.width <= 320 ? CGFloat(0) : CGFloat(3)
        startBrowsingButton.titleLabel?.font = UIFont.systemFont(ofSize: DynamicFontHelper.defaultHelper.IntroBigFontSize)


        for titleLabel in titleLabels {
            titleLabel.font = UIFont.systemFont(ofSize: DynamicFontHelper.defaultHelper.IntroBigFontSize + biggerIt, weight: UIFontWeightBold)
        }

        for label in textLabels {
            label.font = UIFont.systemFont(ofSize: DynamicFontHelper.defaultHelper.IntroStandardFontSize + biggerIt)
        }
    }
}

fileprivate class IntroOverlayScrollView: UIScrollView {
    weak var signinButton: UIButton?

    fileprivate override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        if let signinFrame = signinButton?.frame {
            let convertedFrame = convert(signinFrame, from: signinButton?.superview)
            if convertedFrame.contains(point) {
                return false
            }
        }

        return CGRect(origin: self.frame.origin, size: CGSize(width: self.contentSize.width, height: self.frame.size.height)).contains(point)
    }
}

extension UIColor {
    var components:(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat) {
        var r:CGFloat = 0
        var g:CGFloat = 0
        var b:CGFloat = 0
        var a:CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r,g,b,a)
    }
}
