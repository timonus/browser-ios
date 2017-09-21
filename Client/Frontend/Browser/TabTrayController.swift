/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import SnapKit
import Storage
import ReadingList
import Shared
import CoreData

struct TabTrayControllerUX {
    static let CornerRadius = BraveUX.TabTrayCellCornerRadius
    static let BackgroundColor = UIConstants.AppBackgroundColor
    static let CellBackgroundColor = UIColor(red:1.0, green:1.0, blue:1.0, alpha:1)
    static let TitleBoxHeight = CGFloat(32.0)
    static let Margin = CGFloat(15)
    static let ToolbarBarTintColor = UIConstants.AppBackgroundColor
    static let ToolbarButtonOffset = CGFloat(10.0)
    static let CloseButtonMargin = CGFloat(4.0)
    static let CloseButtonEdgeInset = CGFloat(6)

    static let NumberOfColumnsThin = 1
    static let NumberOfColumnsWide = 3
    static let CompactNumberOfColumnsThin = 2
}

struct LightTabCellUX {
    static let TabTitleTextColor = UIColor.black
}

struct DarkTabCellUX {
    static let TabTitleTextColor = UIColor.white
}

protocol TabCellDelegate: class {
    func tabCellDidClose(_ cell: TabCell)
}

class TabCell: UICollectionViewCell {

    static let Identifier = "TabCellIdentifier"

    let shadowView = UIView()
    let backgroundHolder = UIView()
    let background = UIImageViewAligned()
    let titleLbl: UILabel
    let favicon: UIImageView = UIImageView()
    let titleWrapperBackground = UIView()
    let closeButton: UIButton

    var titleWrapper: UIView = UIView()
    var animator: SwipeAnimator!

    weak var delegate: TabCellDelegate?

    // Changes depending on whether we're full-screen or not.
    var margin = CGFloat(0)

    override init(frame: CGRect) {
        self.shadowView.layer.cornerRadius = TabTrayControllerUX.CornerRadius
        self.shadowView.layer.masksToBounds = false
        
        self.backgroundHolder.backgroundColor = TabTrayControllerUX.CellBackgroundColor
        self.backgroundHolder.layer.cornerRadius = TabTrayControllerUX.CornerRadius
        self.backgroundHolder.layer.borderWidth = 0
        self.backgroundHolder.layer.masksToBounds = true

        self.background.contentMode = UIViewContentMode.scaleAspectFill
        self.background.isUserInteractionEnabled = false
        self.background.layer.masksToBounds = true
        self.background.alignLeft = true
        self.background.alignTop = true

        self.favicon.layer.cornerRadius = 2.0
        self.favicon.layer.masksToBounds = true

        self.titleLbl = UILabel()
        self.titleLbl.backgroundColor = .clear
        self.titleLbl.textAlignment = NSTextAlignment.left
        self.titleLbl.isUserInteractionEnabled = false
        self.titleLbl.numberOfLines = 1
        self.titleLbl.font = DynamicFontHelper.defaultHelper.DefaultSmallFontBold

        self.closeButton = UIButton()
        self.closeButton.setImage(UIImage(named: "stop"), for: .normal)
        self.closeButton.tintColor = .black
        
        self.titleWrapperBackground.backgroundColor = UIColor.white

        self.titleWrapper.backgroundColor = .clear
        
        self.titleWrapper.addSubview(self.titleWrapperBackground)
        self.titleWrapper.addSubview(self.closeButton)
        self.titleWrapper.addSubview(self.titleLbl)
        self.titleWrapper.addSubview(self.favicon)

        super.init(frame: frame)

        self.closeButton.addTarget(self, action: #selector(TabCell.SELclose), for: UIControlEvents.touchUpInside)
        self.contentView.clipsToBounds = false
        self.clipsToBounds = false
        
        self.animator = SwipeAnimator(animatingView: self.shadowView, container: self)

        shadowView.addSubview(backgroundHolder)
        backgroundHolder.addSubview(self.background)
        backgroundHolder.addSubview(self.titleWrapper)
        contentView.addSubview(shadowView)
        
        setupConstraints()

        self.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: Strings.Close, target: self.animator, selector: #selector(SELclose))
        ]
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    fileprivate func setupConstraints() {
        
        let generalOffset = 4
        
        shadowView.snp.remakeConstraints { make in
            make.edges.equalTo(shadowView.superview!)
        }
        
        backgroundHolder.snp.remakeConstraints { make in
            make.edges.equalTo(backgroundHolder.superview!)
        }

        background.snp.remakeConstraints { make in
            make.edges.equalTo(background.superview!)
        }

        favicon.snp.remakeConstraints { make in
            make.top.left.equalTo(favicon.superview!).offset(generalOffset)
            make.size.equalTo(titleWrapper.snp.height).offset(-generalOffset * 2)
        }

        titleWrapper.snp.remakeConstraints { make in
            make.left.top.equalTo(titleWrapper.superview!)
            make.width.equalTo(titleWrapper.superview!.snp.width)
            make.height.equalTo(TabTrayControllerUX.TitleBoxHeight)
        }
        
        titleWrapperBackground.snp.remakeConstraints { make in
            make.top.left.right.equalTo(titleWrapperBackground.superview!)
            make.height.equalTo(TabTrayControllerUX.TitleBoxHeight + 15)
        }

        titleLbl.snp.remakeConstraints { make in
            make.left.equalTo(favicon.snp.right).offset(generalOffset)
            make.right.equalTo(closeButton.snp.left).offset(generalOffset)
            make.top.bottom.equalTo(titleLbl.superview!)
        }

        closeButton.snp.remakeConstraints { make in
            make.size.equalTo(titleWrapper.snp.height)
            make.centerY.equalTo(titleWrapper)
            make.right.equalTo(closeButton.superview!)
        }
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        
        // Frames do not seem to update until next runloop cycle
        DispatchQueue.main.async {
            let gradientLayer = CAGradientLayer()
            gradientLayer.frame = self.titleWrapperBackground.bounds
            gradientLayer.colors = [UIColor(white: 1.0, alpha: 0.98).cgColor, UIColor(white: 1.0, alpha: 0.9).cgColor, UIColor.clear.cgColor]
            self.titleWrapperBackground.layer.mask = gradientLayer
        }
    }
    
    override func prepareForReuse() {
        // TODO: Move more of this to cellForItem
        // Reset any close animations.
        backgroundHolder.layer.borderColor = UIColor(white: 0.0, alpha: 0.15).cgColor
        backgroundHolder.layer.borderWidth = 1
        shadowView.alpha = 1
        shadowView.transform = CGAffineTransform.identity
        shadowView.layer.shadowOpacity = 0
        background.image = nil
        self.titleLbl.font = DynamicFontHelper.defaultHelper.DefaultSmallFontBold
    }

    override func accessibilityScroll(_ direction: UIAccessibilityScrollDirection) -> Bool {
        animator.close(direction == .right)
        return true
    }

    @objc
    func SELclose() {
        self.animator.SELcloseWithoutGesture()
    }
}

struct PrivateModeStrings {
    static let toggleAccessibilityLabel = Strings.Private_Mode
    static let toggleAccessibilityHint = Strings.Turns_private_mode_on_or_off
    static let toggleAccessibilityValueOn = Strings.On
    static let toggleAccessibilityValueOff = Strings.Off
}

protocol TabTrayDelegate: class {
    func tabTrayDidDismiss(_ tabTray: TabTrayController)
    func tabTrayDidAddBookmark(_ tab: Browser)
    func tabTrayDidAddToReadingList(_ tab: Browser) -> ReadingListClientRecord?
    func tabTrayRequestsPresentationOf(_ viewController: UIViewController)
}

class TabTrayController: UIViewController {
    let tabManager: TabManager
    let profile: Profile
    weak var delegate: TabTrayDelegate?

    var collectionView: UICollectionView!
    lazy var addTabButton: UIButton = {
        let addTabButton = UIButton()
        addTabButton.setImage(UIImage(named: "add")?.withRenderingMode(.alwaysTemplate), for: .normal)
        addTabButton.addTarget(self, action: #selector(TabTrayController.SELdidClickAddTab), for: .touchUpInside)
        addTabButton.accessibilityLabel = Strings.Add_Tab
        addTabButton.accessibilityIdentifier = "TabTrayController.addTabButton"
        return addTabButton
    }()
    
    var collectionViewTransitionSnapshot: UIView?
    
    /// Views to be animationed when preseting the Tab Tray.
    /// There is some bug related to the blurring background the tray controller attempts to handle.
    /// On animating self.view the blur effect will not animate (just pops in at the animation end),
    /// and must be animated manually. Instead of animating the larger view elements, smaller pieces
    /// must be animated in order to achieve a blur-incoming animation
    var viewsToAnimate: [UIView] = []

    fileprivate(set) internal var privateMode: Bool = false {
        didSet {
            if privateMode {
                togglePrivateMode.isSelected = true
                togglePrivateMode.accessibilityValue = PrivateModeStrings.toggleAccessibilityValueOn
                togglePrivateMode.backgroundColor = .white
                
                addTabButton.tintColor = UIColor.white
                
                blurBackdropView.effect = UIBlurEffect(style: .dark)
            } else {
                togglePrivateMode.isSelected = false
                togglePrivateMode.accessibilityValue = PrivateModeStrings.toggleAccessibilityValueOff
                togglePrivateMode.backgroundColor = .clear
                
                addTabButton.tintColor = UIColor.black
                
                blurBackdropView.effect = UIBlurEffect(style: .light)
            }
            tabDataSource.updateData()
            collectionView?.reloadData()
        }
    }

    fileprivate var tabsToDisplay: [Browser] {
        return tabManager.tabs.displayedTabsForCurrentPrivateMode
    }

    lazy var togglePrivateMode: UIButton = {
        let button = UIButton()
        button.setTitle(Strings.Private, for: .normal)
        button.setTitleColor(UIColor.black, for: .normal)
        button.titleLabel!.font = UIFont.systemFont(ofSize: button.titleLabel!.font.pointSize + 1, weight: UIFontWeightMedium)
        button.contentEdgeInsets = UIEdgeInsetsMake(0, 4 /* left */, 0, 4 /* right */)
        button.layer.cornerRadius = 4.0
        button.addTarget(self, action: #selector(TabTrayController.SELdidTogglePrivateMode), for: .touchUpInside)
        button.accessibilityLabel = PrivateModeStrings.toggleAccessibilityLabel
        button.accessibilityHint = PrivateModeStrings.toggleAccessibilityHint
        button.accessibilityIdentifier = "TabTrayController.togglePrivateMode"

        return button
    }()
    
    lazy var doneButton: UIButton = {
        let button = UIButton()
        button.setTitle(Strings.Done, for: .normal)
        button.setTitleColor(UIColor(rgb: 0x666666), for: .normal)
        button.titleLabel!.font = UIFont.systemFont(ofSize: button.titleLabel!.font.pointSize + 1, weight: UIFontWeightRegular)
        button.contentEdgeInsets = UIEdgeInsetsMake(0, 4 /* left */, 0, 4 /* right */)
        button.layer.cornerRadius = 4.0
        button.addTarget(self, action: #selector(TabTrayController.SELdidTapDoneButton), for: .touchUpInside)
        button.accessibilityIdentifier = "TabTrayController.doneButton"
        
        return button
    }()
    
    fileprivate var blurBackdropView = UIVisualEffectView()

    fileprivate lazy var emptyPrivateTabsView: UIView = {
        return self.newEmptyPrivateTabsView()
    }()
    
    fileprivate lazy var tabDataSource: TabManagerDataSource = {
        return TabManagerDataSource(cellDelegate: self)
    }()

    fileprivate lazy var tabLayoutDelegate: TabLayoutDelegate = {
        let delegate = TabLayoutDelegate(profile: self.profile, traitCollection: self.traitCollection)
        delegate.tabSelectionDelegate = self
        return delegate
    }()

    override func dismiss(animated flag: Bool, completion: (() -> Void)?) {

        super.dismiss(animated: flag, completion:completion)

        UIView.animate(withDuration: 0.2, animations: {
             getApp().browserViewController.toolbar?.leavingTabTrayMode()
        }) 

        getApp().browserViewController.updateTabCountUsingTabManager(getApp().tabManager)
    }

    init(tabManager: TabManager, profile: Profile) {
        self.tabManager = tabManager
        self.profile = profile
        super.init(nibName: nil, bundle: nil)

        tabManager.addDelegate(self)
    }

    convenience init(tabManager: TabManager, profile: Profile, tabTrayDelegate: TabTrayDelegate) {
        self.init(tabManager: tabManager, profile: profile)
        self.delegate = tabTrayDelegate
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIApplicationWillResignActive, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIApplicationWillEnterForeground, object: nil)
        NotificationCenter.default.removeObserver(self, name: NotificationDynamicFontChanged, object: nil)
        self.tabManager.removeDelegate(self)
    }

    func SELDynamicFontChanged(_ notification: Notification) {
        guard notification.name == NotificationDynamicFontChanged else { return }

        self.collectionView.reloadData()
    }

    @objc func onTappedBackground(_ gesture: UITapGestureRecognizer) {
        dismiss(animated: true, completion: nil)
    }

    override func viewDidAppear(_ animated: Bool) {
        // TODO: centralize timing
        UIView.animate(withDuration: 0.2, animations: {
            self.viewsToAnimate.forEach { $0.alpha = 1.0 }
        }) 
        
        let tabs = WeakList<Browser>()
        getApp().tabManager.tabs.displayedTabsForCurrentPrivateMode.forEach {
            tabs.insert($0)
        }
        
        guard let selectedTab = tabManager.selectedTab else { return }
        let selectedIndex = tabs.index(of: selectedTab) ?? 0
        self.collectionView.scrollToItem(at: IndexPath(item: selectedIndex, section: 0), at: UICollectionViewScrollPosition.centeredVertically, animated: false)
    }
    
// MARK: View Controller Callbacks
    override func viewDidLoad() {
        super.viewDidLoad()

        view.accessibilityLabel = Strings.Tabs_Tray

        let flowLayout = TabTrayCollectionViewLayout()
        collectionView = UICollectionView(frame: view.frame, collectionViewLayout: flowLayout)

        collectionView.dataSource = tabDataSource
        collectionView.delegate = tabLayoutDelegate

        collectionView.register(TabCell.self, forCellWithReuseIdentifier: TabCell.Identifier)
        collectionView.backgroundColor = UIColor.clear
        
        // Background view created for tapping background closure
        collectionView.backgroundView = UIView()
        collectionView.backgroundView?.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(TabTrayController.onTappedBackground(_:))))
        
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongGesture(gesture:)))
        longPressGesture.minimumPressDuration = 0.2
        collectionView.addGestureRecognizer(longPressGesture)

        viewsToAnimate = [blurBackdropView, collectionView, addTabButton, togglePrivateMode, doneButton]
        viewsToAnimate.forEach {
            $0.alpha = 0.0
            view.addSubview($0)
        }

        makeConstraints()
        
        if profile.prefs.boolForKey(kPrefKeyPrivateBrowsingAlwaysOn) ?? false {
            togglePrivateMode.isHidden = true
        }

        view.insertSubview(emptyPrivateTabsView, aboveSubview: collectionView)
        emptyPrivateTabsView.alpha = privateTabsAreEmpty() ? 1 : 0
        emptyPrivateTabsView.snp.makeConstraints { make in
            make.edges.equalTo(self.view)
        }

        // Make sure buttons are all setup before this, to allow
        // privateMode setter to setup final visuals
        let selectedTabIsPrivate = tabManager.selectedTab?.isPrivate ?? false
        privateMode = PrivateBrowsing.singleton.isOn || selectedTabIsPrivate

        NotificationCenter.default.addObserver(self, selector: #selector(TabTrayController.SELappWillResignActiveNotification), name: NSNotification.Name.UIApplicationWillResignActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TabTrayController.SELappDidBecomeActiveNotification), name: NSNotification.Name.UIApplicationDidBecomeActive, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TabTrayController.SELDynamicFontChanged(_:)), name: NotificationDynamicFontChanged, object: nil)
    }
    
    func handleLongGesture(gesture: UILongPressGestureRecognizer) {
        switch(gesture.state) {
        case UIGestureRecognizerState.began:
            guard let selectedIndexPath = self.collectionView.indexPathForItem(at: gesture.location(in: self.collectionView)) else {
                break
            }
            collectionView.beginInteractiveMovementForItem(at: selectedIndexPath)
        case UIGestureRecognizerState.changed:
            collectionView.updateInteractiveMovementTargetPosition(gesture.location(in: gesture.view!))
        case UIGestureRecognizerState.ended:
            collectionView.endInteractiveMovement()
        default:
            collectionView.cancelInteractiveMovement()
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        // Update the trait collection we reference in our layout delegate
        tabLayoutDelegate.traitCollection = traitCollection
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        // Used to update the glow effect on the selected tab
        //  and update screenshot framing/positioning
        // Must be scheduled on next runloop
        DispatchQueue.main.async { 
            self.collectionView.reloadData()
        }
        
        coordinator.animate(alongsideTransition: { _ in
            self.collectionView.collectionViewLayout.invalidateLayout()
        }, completion: nil)
    }

    fileprivate func makeConstraints() {
        
        doneButton.snp.makeConstraints { make in
            make.right.equalTo(self.view).offset(-30)
            make.centerY.equalTo(self.addTabButton.snp.centerY)
        }
        
        togglePrivateMode.snp.makeConstraints { make in
            make.left.equalTo(30)
            make.centerY.equalTo(self.addTabButton.snp.centerY)
        }

        addTabButton.snp.makeConstraints { make in
            make.bottom.equalTo(self.view)
            make.centerX.equalTo(self.view)
            make.size.equalTo(UIConstants.ToolbarHeight)
        }

        collectionView.snp.makeConstraints { make in
            make.bottom.equalTo(addTabButton.snp.top)
            make.top.equalTo(20)
            make.left.right.equalTo(self.view)
        }
        
        blurBackdropView.snp.makeConstraints { (make) in
            make.edges.equalTo(view)
        }
    }
    
    // View we display when there are no private tabs created
    fileprivate func newEmptyPrivateTabsView() -> UIView {
        let emptyView = UIView()
        emptyView.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        return emptyView
    }

// MARK: Selectors
    
    func SELdidTapDoneButton() {
        self.dismiss(animated: true, completion: nil)
    }

    func SELdidClickAddTab() {
        openNewTab()
    }
    
    func SELdidTogglePrivateMode() {
        let fromView: UIView
        if privateTabsAreEmpty() {
            fromView = emptyPrivateTabsView
        } else {
            let snapshot = collectionView.snapshotView(afterScreenUpdates: false)
            snapshot!.frame = collectionView.frame
            view.insertSubview(snapshot!, aboveSubview: collectionView)
            fromView = snapshot!
        }

        privateMode = !privateMode
        if privateMode {
            telemetry("Entering Private Mode", props: nil)
            PrivateBrowsing.singleton.enter()
        } else {
            telemetry("Leaving Private Mode", props: nil)
            view.isUserInteractionEnabled = false
            let activityView = UIActivityIndicatorView(activityIndicatorStyle: .whiteLarge)
            activityView.center = view.center
            activityView.startAnimating()
            self.view.addSubview(activityView)

            PrivateBrowsing.singleton.exit().uponQueue(DispatchQueue.main) {
                self.view.isUserInteractionEnabled = true
                activityView.stopAnimating()
            }
        }
        tabDataSource.updateData()

        collectionView.layoutSubviews()

        let scaleDownTransform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        let toView = privateTabsAreEmpty() ? emptyPrivateTabsView : collectionView
        toView.transform = scaleDownTransform
        toView.alpha = 0

        UIView.animate(withDuration: 0.4, delay: 0, options: [], animations: { () -> Void in
            fromView.alpha = 0
            toView.transform = CGAffineTransform.identity
            toView.alpha = 1
        }) { finished in
            if fromView != self.emptyPrivateTabsView {
                fromView.removeFromSuperview()
            }
            
            if self.privateMode {
                self.openNewTab()
            }
        }
    }

    fileprivate func privateTabsAreEmpty() -> Bool {
        return privateMode && tabManager.tabs.privateTabs.count == 0
    }
    
    func changePrivacyMode(_ isPrivate: Bool) {
        if isPrivate != privateMode {
            guard let _ = collectionView else {
                privateMode = isPrivate
                return
            }
            SELdidTogglePrivateMode()
        }
    }
    
    fileprivate func openNewTab(_ request: URLRequest? = nil) {
        if privateMode {
            emptyPrivateTabsView.isHidden = true
        }
        
        // We're only doing one update here, but using a batch update lets us delay selecting the tab
        // until after its insert animation finishes.
        self.collectionView.performBatchUpdates({ _ in
            // TODO: This logic seems kind of finicky
            var tab: Browser?
            let id = TabMO.freshTab().syncUUID
            tab = self.tabManager.addTab(request, id: id)
            tab?.tabID = id
            
            if let tab = tab {
                self.tabManager.selectTab(tab)
            }
        }, completion: { finished in
            if finished {
                self.dismiss(animated: true, completion: nil)
            }
        })
    }
}

// MARK: - App Notifications
extension TabTrayController {
    func SELappWillResignActiveNotification() {
        if privateMode {
            collectionView.alpha = 0
        }
    }

    func SELappDidBecomeActiveNotification() {
        // Re-show any components that might have been hidden because they were being displayed
        // as part of a private mode tab
        UIView.animate(withDuration: 0.2, delay: 0, options: UIViewAnimationOptions(), animations: {
            self.collectionView.alpha = 1
        },
        completion: nil)
    }
}

extension TabTrayController: TabSelectionDelegate {
    func didSelectTabAtIndex(_ index: Int) {
        let tab = tabsToDisplay[index]
        tabManager.selectTab(tab)
        self.dismiss(animated: true, completion: nil)
    }
}

extension TabTrayController: PresentingModalViewControllerDelegate {
    func dismissPresentedModalViewController(_ modalViewController: UIViewController, animated: Bool) {
        dismiss(animated: animated, completion: { self.collectionView.reloadData() })
    }
}

extension TabTrayController: TabManagerDelegate {
    func tabManager(_ tabManager: TabManager, didSelectedTabChange selected: Browser?) {
    }

    func tabManager(_ tabManager: TabManager, didCreateWebView tab: Browser, url: URL?, at: Int?) {
    }

    func tabManager(_ tabManager: TabManager, didAddTab tab: Browser) {
        // Get the index of the added tab from it's set (private or normal)
        guard let index = tabsToDisplay.index(of: tab) else { return }

        tabDataSource.updateData()

        self.collectionView?.performBatchUpdates({ _ in
            self.collectionView.insertItems(at: [IndexPath(item: index, section: 0)])
        }, completion: { finished in
            if finished {
                tabManager.selectTab(tab)
                // don't pop the tab tray view controller if it is not in the foreground
                if self.presentedViewController == nil {
                    self.dismiss(animated: true, completion: nil)
                }
            }
        })
    }

    func tabManager(_ tabManager: TabManager, didRemoveTab tab: Browser) {
        var removedIndex = -1
        for i in 0..<tabDataSource.tabList.count() {
            let tabRef = tabDataSource.tabList.at(i)
            if tabRef == nil || getApp().tabManager.tabs.displayedTabsForCurrentPrivateMode.index(of: tabRef!) == nil {
                removedIndex = i
                break
            }
        }

        tabDataSource.updateData()
        if (removedIndex < 0) {
            return
        }

        self.collectionView.deleteItems(at: [IndexPath(item: removedIndex, section: 0)])
        
        if privateTabsAreEmpty() {
            emptyPrivateTabsView.alpha = 1
        }
    }

    func tabManagerDidAddTabs(_ tabManager: TabManager) {
    }

    func tabManagerDidRestoreTabs(_ tabManager: TabManager) {
    }
}

extension TabTrayController: UIScrollViewAccessibilityDelegate {
    func accessibilityScrollStatus(for scrollView: UIScrollView) -> String? {
        var visibleCells = collectionView.visibleCells as! [TabCell]
        var bounds = collectionView.bounds
        bounds = bounds.offsetBy(dx: collectionView.contentInset.left, dy: collectionView.contentInset.top)
        bounds.size.width -= collectionView.contentInset.left + collectionView.contentInset.right
        bounds.size.height -= collectionView.contentInset.top + collectionView.contentInset.bottom
        // visible cells do sometimes return also not visible cells when attempting to go past the last cell with VoiceOver right-flick gesture; so make sure we have only visible cells (yeah...)
        visibleCells = visibleCells.filter { !$0.frame.intersection(bounds).isEmpty }

        let cells = visibleCells.map { self.collectionView.indexPath(for: $0)! }
        let indexPaths = cells.sorted { (a: IndexPath, b: IndexPath) -> Bool in
            return a.section < b.section || (a.section == b.section && a.row < b.row)
        }

        if indexPaths.count == 0 {
            return Strings.No_tabs
        }

        let firstTab = indexPaths.first!.row + 1
        let lastTab = indexPaths.last!.row + 1
        let tabCount = collectionView.numberOfItems(inSection: 0)

        if (firstTab == lastTab) {
            let format = Strings.Tab_xofx_template
            return String(format: format, NSNumber(value: firstTab), NSNumber(value: tabCount))
        } else {
            let format = Strings.Tabs_xtoxofx_template
            return String(format: format, NSNumber(value: firstTab), NSNumber(value: lastTab), NSNumber(value: tabCount))
        }
    }
}

fileprivate func removeTabUtil(_ tabManager: TabManager, tab: Browser) {
    let isAlwaysPrivate = getApp().profile?.prefs.boolForKey(kPrefKeyPrivateBrowsingAlwaysOn) ?? false
    let createIfNone =  true
    tabManager.removeTab(tab, createTabIfNoneLeft: createIfNone)
}

extension TabTrayController: SwipeAnimatorDelegate {
    func swipeAnimator(_ animator: SwipeAnimator, viewWillExitContainerBounds: UIView) {
        let tabCell = animator.container as! TabCell
        if let indexPath = collectionView.indexPath(for: tabCell) {
            let tab = tabsToDisplay[indexPath.item]
            removeTabUtil(tabManager, tab: tab)
            UIAccessibilityPostNotification(UIAccessibilityAnnouncementNotification, Strings.Closing_tab)
        }
    }
}

extension TabTrayController: TabCellDelegate {
    func tabCellDidClose(_ cell: TabCell) {
        let indexPath = collectionView.indexPath(for: cell)!
        let tab = tabsToDisplay[indexPath.item]
        removeTabUtil(tabManager, tab: tab)
    }
}

extension TabTrayController: SettingsDelegate {
    func settingsOpenURLInNewTab(_ url: URL) {
        let request = URLRequest(url: url)
        openNewTab(request)
    }
}

fileprivate class TabManagerDataSource: NSObject, UICollectionViewDataSource {
    unowned var cellDelegate: TabCellDelegate & SwipeAnimatorDelegate

    fileprivate var tabList = WeakList<Browser>()

    init(cellDelegate: TabCellDelegate & SwipeAnimatorDelegate) {
        self.cellDelegate = cellDelegate
        super.init()

        getApp().tabManager.tabs.displayedTabsForCurrentPrivateMode.forEach {
            tabList.insert($0)
        }
    }

    func updateData() {
        tabList = WeakList<Browser>()
        getApp().tabManager.tabs.displayedTabsForCurrentPrivateMode.forEach {
            tabList.insert($0)
        }
    }

    @objc func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let tabCell = collectionView.dequeueReusableCell(withReuseIdentifier: TabCell.Identifier, for: indexPath) as! TabCell
        tabCell.animator.delegate = cellDelegate
        tabCell.delegate = cellDelegate

        guard let tab = tabList.at(indexPath.item) else {
            assert(false)
            return tabCell
        }
        tabCell.titleLbl.text = tab.displayTitle

        if !tab.displayTitle.isEmpty {
            tabCell.accessibilityLabel = tab.displayTitle
        } else {
            tabCell.accessibilityLabel = AboutUtils.getAboutComponent(tab.url)
        }

        tabCell.isAccessibilityElement = true
        tabCell.accessibilityHint = Strings.Swipe_right_or_left_with_three_fingers_to_close_the_tab

        if let favIcon = tab.displayFavicon {
            tabCell.favicon.sd_setImage(with: URL(string: favIcon.url)!)
            tabCell.favicon.backgroundColor = BraveUX.TabTrayCellBackgroundColor
        } else {
            tabCell.favicon.image = nil
        }
        
        tab.screenshot(callback: { (image) in
            tabCell.background.image = image
        })

        // TODO: Move most view logic here instead of `init` or `prepareForReuse`
        // If the current tab add heightlighting
        if getApp().tabManager.selectedTab == tab {
            tabCell.backgroundHolder.layer.borderColor = BraveUX.DefaultBlue.withAlphaComponent(0.75).cgColor
            tabCell.backgroundHolder.layer.borderWidth = 1
            tabCell.shadowView.layer.shadowRadius = 5
            tabCell.shadowView.layer.shadowColor = BraveUX.DefaultBlue.cgColor
            tabCell.shadowView.layer.shadowOpacity = 1.0
            tabCell.shadowView.layer.shadowOffset = CGSize(width: 0, height: 0)
            tabCell.shadowView.layer.shadowPath = UIBezierPath(roundedRect: tabCell.bounds, cornerRadius: tabCell.backgroundHolder.layer.cornerRadius).cgPath
            tabCell.background.alpha = 1.0
        } else {
            tabCell.backgroundHolder.layer.borderWidth = 0
            tabCell.shadowView.layer.shadowRadius = 2
            tabCell.shadowView.layer.shadowColor = UIColor(white: 0.0, alpha: 0.15).cgColor
            tabCell.shadowView.layer.shadowOpacity = 1.0
            tabCell.shadowView.layer.shadowOffset = CGSize(width: 0, height: 0)
            tabCell.shadowView.layer.shadowPath = UIBezierPath(roundedRect: tabCell.bounds, cornerRadius: tabCell.backgroundHolder.layer.cornerRadius).cgPath
            tabCell.background.alpha = 0.7
        }
        
        return tabCell
    }

    @objc func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return tabList.count()
    }
    
    @objc func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    @objc func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        guard let tab = tabList.at(sourceIndexPath.row) else { return }
        
        // Find original from/to index... we need to target the full list not partial.
        guard let tabManager = getApp().tabManager else { return }
        guard let from = tabManager.tabs.tabs.index(where: {$0 === tab}) else { return }
        
        let toTab = tabList.at(destinationIndexPath.row)
        guard let to = tabManager.tabs.tabs.index(where: {$0 === toTab}) else { return }
        
        tabManager.move(tab: tab, from: from, to: to)
        
        updateData()
        NotificationCenter.default.post(name: kRearangeTabNotification, object: nil)
    }
}

@objc protocol TabSelectionDelegate: class {
    func didSelectTabAtIndex(_ index :Int)
}

fileprivate class TabLayoutDelegate: NSObject, UICollectionViewDelegateFlowLayout {
    weak var tabSelectionDelegate: TabSelectionDelegate?

    fileprivate var traitCollection: UITraitCollection
    fileprivate var profile: Profile
    fileprivate var numberOfColumns: Int {
        let compactLayout = profile.prefs.boolForKey("CompactTabLayout") ?? true

        // iPhone 4-6+ portrait
        if traitCollection.horizontalSizeClass == .compact && traitCollection.verticalSizeClass == .regular {
            return compactLayout ? TabTrayControllerUX.CompactNumberOfColumnsThin : TabTrayControllerUX.NumberOfColumnsThin
        } else {
            return TabTrayControllerUX.NumberOfColumnsWide
        }
    }

    init(profile: Profile, traitCollection: UITraitCollection) {
        self.profile = profile
        self.traitCollection = traitCollection
        super.init()
    }

    fileprivate func cellHeightForCurrentDevice() -> CGFloat {
        let compactLayout = profile.prefs.boolForKey("CompactTabLayout") ?? true
        let shortHeight = TabTrayControllerUX.TitleBoxHeight * (compactLayout ? 7 : 6)

        if self.traitCollection.verticalSizeClass == UIUserInterfaceSizeClass.compact {
            return shortHeight
        } else if self.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClass.compact {
            return rint(UIScreen.main.bounds.height / 3)
        } else {
            return TabTrayControllerUX.TitleBoxHeight * 8
        }
    }

    @objc func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumInteritemSpacingForSectionAt section: Int) -> CGFloat {
        return TabTrayControllerUX.Margin
    }

    @objc func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        let cellWidth = floor((collectionView.bounds.width - TabTrayControllerUX.Margin * CGFloat(numberOfColumns + 1)) / CGFloat(numberOfColumns))
        return CGSize(width: cellWidth, height: self.cellHeightForCurrentDevice())
    }

    @objc func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, insetForSectionAt section: Int) -> UIEdgeInsets {
        return UIEdgeInsetsMake(TabTrayControllerUX.Margin, TabTrayControllerUX.Margin, TabTrayControllerUX.Margin, TabTrayControllerUX.Margin)
    }

    @objc func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        return TabTrayControllerUX.Margin
    }

    @objc func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        tabSelectionDelegate?.didSelectTabAtIndex(indexPath.row)
    }
}

// There seems to be a bug with UIKit where when the UICollectionView changes its contentSize
// from > frame.size to <= frame.size: the contentSet animation doesn't properly happen and 'jumps' to the
// final state.
// This workaround forces the contentSize to always be larger than the frame size so the animation happens more
// smoothly. This also makes the tabs be able to 'bounce' when there are not enough to fill the screen, which I
// think is fine, but if needed we can disable user scrolling in this case.
fileprivate class TabTrayCollectionViewLayout: UICollectionViewFlowLayout {
    fileprivate override var collectionViewContentSize : CGSize {
        var calculatedSize = super.collectionViewContentSize
        let collectionViewHeight = collectionView?.bounds.size.height ?? 0
        if calculatedSize.height < collectionViewHeight && collectionViewHeight > 0 {
            calculatedSize.height = collectionViewHeight + 1
        }
        return calculatedSize
    }
}

struct EmptyPrivateTabsViewUX {
    static let TitleColor = UIColor.white
    static let TitleFont = UIFont.systemFont(ofSize: 22, weight: UIFontWeightMedium)
    static let DescriptionColor = UIColor.white
    static let DescriptionFont = UIFont.systemFont(ofSize: 17)
    static let LearnMoreFont = UIFont.systemFont(ofSize: 15, weight: UIFontWeightMedium)
    static let TextMargin: CGFloat = 18
    static let LearnMoreMargin: CGFloat = 30
    static let MaxDescriptionWidth: CGFloat = 250
}
