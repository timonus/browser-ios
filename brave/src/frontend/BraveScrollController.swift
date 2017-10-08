/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import SnapKit
import pop

private let ToolbarBaseAnimationDuration: CGFloat = 0.2

class BraveScrollController: NSObject {
    enum ScrollDirection {
        case up
        case down
        case none  // Brave added
    }

    weak var browser: Browser? {
        willSet {
            self.scrollView?.delegate = nil
            self.scrollView?.removeGestureRecognizer(panGesture)
            BraveApp.getCurrentWebView()?.removeGestureRecognizer(tapShowBottomBar)
        }

        didSet {
            BraveApp.getCurrentWebView()?.addGestureRecognizer(tapShowBottomBar)
            self.scrollView?.addGestureRecognizer(panGesture)
            scrollView?.delegate = self
        }
    }

    lazy var tapShowBottomBar: UITapGestureRecognizer = {
        let t = UITapGestureRecognizer(target: self, action: #selector(onTapShowBottomBar))
        t.delegate = self
        return t
    }()

    weak var header: UIView?
    weak var footer: UIView?
    weak var urlBar: URLBarView?
    weak var snackBars: UIView?

    var keyboardIsShowing = false
    var verticalTranslation = CGFloat(0)

    var footerBottomConstraint: Constraint?
    var headerTopConstraint: Constraint?
    var toolbarsShowing: Bool { return headerTopOffset == 0 }

    var edgeSwipingActive = false

    fileprivate var headerTopOffset: CGFloat = 0 {
        didSet {
            headerTopConstraint?.update(offset: headerTopOffset)
            header?.superview?.setNeedsLayout()
        }
    }

    fileprivate var footerBottomOffset: CGFloat = 0 {
        didSet {
            footerBottomConstraint?.update(offset: footerBottomOffset)
            footer?.superview?.setNeedsLayout()
        }
    }

    lazy var panGesture: UIPanGestureRecognizer = {
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(BraveScrollController.handlePan(_:)))
        panGesture.maximumNumberOfTouches = 1
        panGesture.delegate = self
        return panGesture
    }()

    fileprivate var scrollView: UIScrollView? { return browser?.webView?.scrollView }
    fileprivate var contentOffset: CGPoint { return scrollView?.contentOffset ?? CGPoint.zero }
    fileprivate var contentSize: CGSize { return scrollView?.contentSize ?? CGSize.zero }
    fileprivate var scrollViewHeight: CGFloat { return scrollView?.frame.height ?? 0 }
    fileprivate var headerFrame: CGRect { return header?.frame ?? CGRect.zero }
    fileprivate var footerFrame: CGRect { return footer?.frame ?? CGRect.zero }
    fileprivate var snackBarsFrame: CGRect { return snackBars?.frame ?? CGRect.zero }

    struct LastContentOffset {
        static var x = CGFloat(0)
        static var y = CGFloat(0)
    }
    fileprivate var scrollDirection: ScrollDirection = .down

    // Brave added
    // What I am seeing on older devices is when scroll direction is changed quickly, and the toolbar show/hides,
    // the first or second pan gesture after that will report the wrong direction (the gesture handling seems bugging during janky scrolling)
    // This added check is a secondary validator of the scroll direction
    fileprivate var scrollViewWillBeginDragPoint: CGFloat = 0

    func setBottomInset(_ bottom: CGFloat) {
        scrollView?.contentInset = UIEdgeInsetsMake(0, 0, bottom, 0)
        scrollView?.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, bottom, 0)
    }

    override init() {
        super.init()

        NotificationCenter.default.addObserver(self, selector: #selector(BraveScrollController.pageUnload), name: NSNotification.Name(rawValue: kNotificationPageUnload), object: nil)

        NotificationCenter.default.addObserver(self, selector:#selector(BraveScrollController.keyboardWillAppear(_:)), name: NSNotification.Name.UIKeyboardWillShow, object: nil)
        NotificationCenter.default.addObserver(self, selector:#selector(BraveScrollController.keyboardDidAppear(_:)), name: NSNotification.Name.UIKeyboardDidShow, object: nil)
        NotificationCenter.default.addObserver(self, selector:#selector(BraveScrollController.keyboardWillDisappear(_:)), name: NSNotification.Name.UIKeyboardWillHide, object: nil)
    }

    func keyboardWillAppear(_ notification: Notification){
        keyboardIsShowing = true
    }
    
    func keyboardDidAppear(_ notification: Notification){
        checkHeightOfPageAndAdjustWebViewInsets(keyboardAppeared: true)
    }

    func keyboardWillDisappear(_ notification: Notification){
        keyboardIsShowing = false

        postAsyncToMain(0.2) {
            // Hiding/showing toolbars during kb show affects layout updating, reset the toolbar state
            self.verticalTranslation = 0
            self.header?.layer.transform = CATransform3DIdentity
            self.footer?.layer.transform = CATransform3DIdentity
            if self.headerTopOffset < 0 {
                self.headerTopOffset = -BraveURLBarView.CurrentHeight
                self.footerBottomOffset = UIConstants.ToolbarHeight
            } else {
                self.headerTopOffset = 0
                self.footerBottomOffset = 0
                self.urlBar?.updateAlphaForSubviews(1.0)
            }
        }
    }

    func pageUnload() {
        postAsyncToMain(0.1) {
            self.showToolbars(animated: true)
        }
    }

    // Struct used to prevent inset adjustment based on runtime scenarios
    struct RuntimeInsetChecks {
        // If inset adjustment code is already being executed
        static var isRunningCheck = false
        
        // Whether webview is currently being zoomed
        // Should not update on zooming (e.g. issue #717)
        static var isZoomingCheck = false
    }
    
    // This causes issue #216 if contentInset changed during a load
    func checkHeightOfPageAndAdjustWebViewInsets(keyboardAppeared: Bool = false) {

        if RuntimeInsetChecks.isZoomingCheck {
            return
        }

        if self.browser?.webView?.isLoading ?? false {
            if RuntimeInsetChecks.isRunningCheck {
                return
            }
            RuntimeInsetChecks.isRunningCheck = true
            postAsyncToMain(0.2) {
                RuntimeInsetChecks.isRunningCheck = false
                self.checkHeightOfPageAndAdjustWebViewInsets(keyboardAppeared: keyboardAppeared)
            }
        } else {
            RuntimeInsetChecks.isRunningCheck = false

            if !isScrollHeightIsLargeEnoughForScrolling() && !keyboardIsShowing {
                let h = BraveApp.isIPhonePortrait() ? UIConstants.ToolbarHeight + BraveURLBarView.CurrentHeight : BraveURLBarView.CurrentHeight
                setBottomInset(h)
            }
            else {
                guard let webView = getApp().browserViewController.webViewContainer else { return }
                guard let toolBarFrame = footer?.frame else { return }
                let frame = webView.frame
                let bounds = UIScreen.main.bounds
                
                let toolBarPosition = bounds.height - min(toolBarFrame.minY, bounds.height)
                
                if frame.maxY > bounds.height - toolBarPosition {
                    let inset = frame.maxY - bounds.height + toolBarPosition
                    setBottomInset(inset)
                }
                else {
                    setBottomInset(0)
                }
            }
        }
    }
    
    func removeTranslationAndSetLayout() {
        if verticalTranslation == 0 {
            return
        }
        
        if verticalTranslation < 0 && headerTopOffset == 0 {
            headerTopOffset = -BraveURLBarView.CurrentHeight
            footerBottomOffset = UIConstants.ToolbarHeight
            urlBar?.updateAlphaForSubviews(0)
        } else if verticalTranslation > UIConstants.ToolbarHeight / 2.0 && headerTopOffset != 0 {
            headerTopOffset = 0
            footerBottomOffset = 0
            urlBar?.updateAlphaForSubviews(1.0)
        }
        
        verticalTranslation = 0
        header?.layer.transform = CATransform3DIdentity
        footer?.layer.transform = CATransform3DIdentity
    }

    func showToolbars(animated: Bool, isShowingDueToBottomTap: Bool = false, completion: ((_ finished: Bool) -> Void)? = nil) {
        checkHeightOfPageAndAdjustWebViewInsets()

        if verticalTranslation == 0 && headerTopOffset == 0 {
            completion?(true)
            return
        }

        removeTranslationAndSetLayout()

        let durationRatio = abs(headerTopOffset / headerFrame.height)
        let actualDuration = TimeInterval(ToolbarBaseAnimationDuration * durationRatio)
        self.animateToolbarsWithOffsets(
            animated: animated,
            duration: actualDuration,
            headerOffset: 0,
            footerOffset: 0,
            alpha: 1,
            isShowingDueToBottomTap: isShowingDueToBottomTap,
            completion: completion)
    }

    var entrantGuard = false
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if entrantGuard {
            return
        }
        entrantGuard = true
        defer {
            entrantGuard = false
        }
        
        if (keyPath ?? "") == "contentSize" { // && browser?.webView?.scrollView === object {
            browser?.webView?.contentSizeChangeDetected()
            //Slight delay allows the keyboardDidAppear to be called first and adjust textfield positioning.
            postAsyncToMain(0.2) {
                self.checkHeightOfPageAndAdjustWebViewInsets()
            }
            if !isScrollHeightIsLargeEnoughForScrolling() && !toolbarsShowing {
                showToolbars(animated: true, completion: nil)
            }
        }
    }

    //// bottom tap //////
    func onTapShowBottomBar(_ gesture: UITapGestureRecognizer) {
        if toolbarsShowing || !BraveApp.isIPhonePortrait() {
            return
        }

        guard let height = gesture.view?.frame.height else { return }
        if gesture.location(in: gesture.view).y > height - UIConstants.ToolbarHeight {
            showToolbars(animated: true, isShowingDueToBottomTap: true)
        }
    }
}

private extension BraveScrollController {
    func browserIsLoading() -> Bool {
        return browser?.loading ?? true
    }

    @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
        if browserIsLoading() || edgeSwipingActive {
            return
        }

        guard let containerView = scrollView?.superview else { return }

        let translation = gesture.translation(in: containerView)
        let delta = CGPoint(x: LastContentOffset.x - translation.x, y: LastContentOffset.y - translation.y)

        if abs(delta.x) > abs(delta.y) {
            // horizontal scrolling shouldn't affect toolbars.
            return
        }
        
        if delta.y > 0 || contentOffset.y - scrollViewWillBeginDragPoint >= 1.0 {
            scrollDirection = .down
        } else if delta.y < 0 || scrollViewWillBeginDragPoint - contentOffset.y >= 1.0 {
            scrollDirection = .up
        }
        
        LastContentOffset.x = translation.x
        LastContentOffset.y = translation.y
        
        if gesture.state == .ended || gesture.state == .cancelled {
            LastContentOffset.x = 0
            LastContentOffset.y = 0
        }
        
        // avoid showing for slow scroll (up)
        if scrollDirection == .up && contentOffset.y > 0 {
            return
        }
        
        if isScrollHeightIsLargeEnoughForScrolling() {
            scrollToolbarsWithDelta(delta.y)
        }
    }

    func scrollToolbarsWithDelta(_ delta: CGFloat) {
        if keyboardIsShowing {
            return
        }
        
        if scrollViewHeight >= contentSize.height {
            return
        }

        if (snackBars?.frame.size.height ?? 0) > 0 {
            return
        }

        let updatedOffset = toolbarsShowing ? clamp(verticalTranslation - delta, min: -BraveURLBarView.CurrentHeight, max: 0) :
            clamp(verticalTranslation - delta, min: 0, max: BraveURLBarView.CurrentHeight)

        verticalTranslation = updatedOffset
        
        if let header = header, let animation = POPBasicAnimation(propertyNamed: kPOPLayerTranslationY) {
            header.layer.pop_removeAnimation(forKey: "headerTranslation")
            animation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionLinear)
            animation.toValue = verticalTranslation
            animation.duration = 0.028
            header.layer.pop_add(animation, forKey: "headerTranslation")
        }

        let footerTranslation = verticalTranslation > UIConstants.ToolbarHeight ? -UIConstants.ToolbarHeight : -verticalTranslation
        
        if let footer = footer, let animation = POPBasicAnimation(propertyNamed: kPOPLayerTranslationY) {
            footer.layer.pop_removeAnimation(forKey: "footerTranslation")
            animation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionLinear)
            animation.toValue = footerTranslation
            animation.duration = 0.028
            footer.layer.pop_add(animation, forKey: "footerTranslation")
        }

        let webViewVertTranslation = toolbarsShowing ? verticalTranslation : verticalTranslation - BraveURLBarView.CurrentHeight
        
        if let webView = getApp().browserViewController.webViewContainer, let animation = POPBasicAnimation(propertyNamed: kPOPLayerTranslationY) {
            webView.layer.pop_removeAnimation(forKey: "webViewTranslation")
            animation.timingFunction = CAMediaTimingFunction(name: kCAMediaTimingFunctionLinear)
            animation.toValue = webViewVertTranslation
            animation.duration = 0.028
            webView.layer.pop_add(animation, forKey: "webViewTranslation")
        }

        var alpha = 1 - abs(verticalTranslation / UIConstants.ToolbarHeight)
        if (!toolbarsShowing) {
            alpha = 1 - alpha
        }
        urlBar?.updateAlphaForSubviews(alpha)
        
        if UIDevice.current.userInterfaceIdiom == .phone {
            checkHeightOfPageAndAdjustWebViewInsets()
        }
        
        if (fabs(updatedOffset) > 0 && fabs(updatedOffset) < BraveURLBarView.CurrentHeight) {
            // this stops parallax effect where the scrolling rate is doubled while hiding/showing toolbars
            scrollView?.contentOffset = CGPoint(x: contentOffset.x, y: contentOffset.y - delta)
        }
    }

    func clamp(_ y: CGFloat, min: CGFloat, max: CGFloat) -> CGFloat {
        if y >= max {
            return max
        } else if y <= min {
            return min
        }
        return y
    }

    // Currently only has handling for the show toolbars case.
    func animateToolbarsWithOffsets(animated: Bool, duration: TimeInterval, headerOffset: CGFloat,
                                                     footerOffset: CGFloat, alpha: CGFloat, isShowingDueToBottomTap: Bool, completion: ((_ finished: Bool) -> Void)?) {

        let animation: () -> Void = {
            self.headerTopOffset = headerOffset
            self.footerBottomOffset = footerOffset
            self.urlBar?.updateAlphaForSubviews(alpha)
            self.header?.layoutIfNeeded()
            self.footer?.layoutIfNeeded()

            // TODO this code is only being used to show toolbars, so right now hard-code for that case, obviously if/when hide is added, update the code to support that
            let webView = getApp().browserViewController.webViewContainer
            webView?.layer.transform = CATransform3DIdentity

            if isShowingDueToBottomTap { // scroll up to show page under the bottom toolbar
                self.scrollView?.contentOffset.y += 2 * BraveURLBarView.CurrentHeight
            } else if self.contentOffset.y > BraveURLBarView.CurrentHeight {
                // keep the web view in the same scroll position by scrolling up the toolbar height 
                self.scrollView?.contentOffset.y += BraveURLBarView.CurrentHeight
            }
        }

        // Reset the scroll direction now that it is handled
        scrollDirection = .none

        let completionWrapper: (Bool) -> Void = { finished in
            completion?(finished)
        }

        if animated {
            UIView.animate(withDuration: 0.350, delay:0.0, options: .allowUserInteraction, animations: animation, completion: completionWrapper)
        } else {
            animation()
            completion?(true)
        }
    }

    func isScrollHeightIsLargeEnoughForScrolling() -> Bool {
        return (UIScreen.main.bounds.size.height + 2 * UIConstants.ToolbarHeight) < scrollView?.contentSize.height ?? 0
    }
}

extension BraveScrollController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        return true
    }
}

func blockOtherGestures(_ isBlocked: Bool, views: [UIView]) {
    for view in views {
        if let gestures = view.gestureRecognizers as [UIGestureRecognizer]! {
            for gesture in gestures {
                gesture.isEnabled = !isBlocked
            }
        }
    }
}

var moveToolbarsWithScroll = false

extension BraveScrollController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard let webView = browser?.webView else { return }
        if webViewIsZoomed(webView) {
            return;
        }
        
        if moveToolbarsWithScroll {
            let delta = scrollView.contentOffset.y - scrollViewWillBeginDragPoint
            scrollToolbarsWithDelta(delta)
        }
    }
    
    func scrollViewWillEndDragging(_ scrollView: UIScrollView, withVelocity velocity: CGPoint, targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        // Ignore system bounce beyond content bounds.
        // Requires enough velocity that we may present/hide the entire header.
        let top = scrollView.contentOffset.y < 0
        let bottom = scrollView.contentSize.height - scrollView.contentOffset.y - scrollView.frame.height < 0
        moveToolbarsWithScroll = (!top && !bottom && abs(velocity.y) > 0.1)
        scrollViewWillBeginDragPoint = scrollView.contentOffset.y
    }

    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        // freeze
        RuntimeInsetChecks.isZoomingCheck = true
    }
    
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        // unfreeze
        RuntimeInsetChecks.isZoomingCheck = false
    }
    
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        moveToolbarsWithScroll = false
        scrollViewWillBeginDragPoint = scrollView.contentOffset.y
    }
    
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        moveToolbarsWithScroll = false
    }
    
    func scrollViewShouldScrollToTop(_ scrollView: UIScrollView) -> Bool {
        return true
    }
}
