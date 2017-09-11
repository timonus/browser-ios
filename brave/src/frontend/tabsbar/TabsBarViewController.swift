/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */
import UIKit
import SnapKit

enum TabsBarShowPolicy : Int {
    case never
    case always
    case landscapeOnly
}

let kPrefKeyTabsBarShowPolicy = "kPrefKeyTabsBarShowPolicy"
let kPrefKeyTabsBarOnDefaultValue = UIDevice.current.userInterfaceIdiom == .pad ? TabsBarShowPolicy.always : TabsBarShowPolicy.landscapeOnly

let minTabWidth =  UIDevice.current.userInterfaceIdiom == .pad ? CGFloat(180) : CGFloat(160)
let tabHeight = TabsBarHeight

protocol TabBarCellDelegate: class {
    func tabClose(_ tab: Browser?)
}

class TabBarCell: UICollectionViewCell {
    let title = UILabel()
    let close = UIButton()
    let separatorLine = UIView()
    var browser: Browser? {
        didSet {
            if let wv = self.browser?.webView {
                wv.delegatesForPageState.append(BraveWebView.Weak_WebPageStateDelegate(value: self))
            }
        }
    }
    weak var delegate: TabBarCellDelegate?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        backgroundColor = UIColor.clear
        
        close.addTarget(self, action: #selector(closeTab), for: .touchUpInside)
        
        [close, title, separatorLine].forEach { contentView.addSubview($0) }
        
        title.textAlignment = .center
        title.snp.makeConstraints({ (make) in
            make.top.bottom.equalTo(self)
            make.left.equalTo(close.snp.right)
            make.right.equalTo(self).inset(labelInsetFromRight)
        })
        
        close.setImage(UIImage(named: "stop")?.withRenderingMode(.alwaysTemplate), for: .normal)
        close.snp.makeConstraints({ (make) in
            make.top.bottom.equalTo(self)
            make.left.equalTo(self).inset(4)
            make.width.equalTo(24)
        })
        close.tintColor = UIColor.black
        
        separatorLine.backgroundColor = UIColor.black.withAlphaComponent(0.15)
        separatorLine.snp.makeConstraints { (make) in
            make.left.equalTo(self)
            make.width.equalTo(1)
            make.height.equalTo(29)
            make.centerY.equalTo(self.snp.centerY)
        }
        
        isSelected = false
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override var isSelected: Bool {
        didSet(selected) {
            if selected {
                title.font = UIFont.systemFont(ofSize: 12, weight: UIFontWeightSemibold)
                title.textColor = PrivateBrowsing.singleton.isOn ? UIColor.white : UIColor.black
                close.isHidden = false
                backgroundColor = PrivateBrowsing.singleton.isOn ? BraveUX.DarkToolbarsBackgroundSolidColor : BraveUX.ToolbarsBackgroundSolidColor
            }
            else {
                title.font = UIFont.systemFont(ofSize: 12)
                title.textColor = PrivateBrowsing.singleton.isOn ? UIColor(white: 1.0, alpha: 0.4) : UIColor(white: 0.0, alpha: 0.4)
                close.isHidden = true
                close.tintColor = PrivateBrowsing.singleton.isOn ? UIColor.white : UIColor.black
                backgroundColor = UIColor.clear
            }
        }
    }
    
    override func prepareForReuse() {
        title.text = ""
        isSelected = false
    }
    
    func closeTab() {
        delegate?.tabClose(browser)
    }
    
    fileprivate var titleUpdateScheduled = false
    func updateTitle_throttled() {
        if titleUpdateScheduled {
            return
        }
        titleUpdateScheduled = true
        postAsyncToMain(0.2) { [weak self] in
            self?.titleUpdateScheduled = false
            if let t = self?.browser?.webView?.title, !t.isEmpty {
                self?.title.text = t
            }
        }
    }
}

extension TabBarCell: WebPageStateDelegate {
    func webView(_ webView: UIWebView, urlChanged: String) {
        if let t = browser?.url?.baseDomain,  title.text?.isEmpty ?? true {
            title.text = t
        }
        
        updateTitle_throttled()
    }
    
    func webView(_ webView: UIWebView, progressChanged: Float) {
        updateTitle_throttled()
    }
    
    func webView(_ webView: UIWebView, isLoading: Bool) {}
    func webView(_ webView: UIWebView, canGoBack: Bool) {}
    func webView(_ webView: UIWebView, canGoForward: Bool) {}
}

class TabsBarViewController: UIViewController {
    var plusButton = UIButton()

    var leftOverflowIndicator : CAGradientLayer = CAGradientLayer()
    var rightOverflowIndicator : CAGradientLayer = CAGradientLayer()
    
    var collectionLayout: UICollectionViewFlowLayout!
    var collectionView: UICollectionView!

    var isVisible:Bool {
        return self.view.alpha > 0
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor(white: 0.0, alpha: 0.1)
        
        collectionLayout = UICollectionViewFlowLayout()
        collectionLayout.scrollDirection = .horizontal
        collectionLayout.itemSize = CGSize(width: minTabWidth, height: view.frame.height)
        collectionLayout.minimumInteritemSpacing = 0
        collectionLayout.minimumLineSpacing = 0
        
        collectionView = UICollectionView(frame: view.frame, collectionViewLayout: collectionLayout)
        collectionView.backgroundColor = UIColor.clear
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.bounces = false
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.allowsSelection = true
        collectionView.decelerationRate = UIScrollViewDecelerationRateFast
        collectionView.register(TabBarCell.self, forCellWithReuseIdentifier: "TabCell")
        view.addSubview(collectionView)
        
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongGesture(gesture:)))
        collectionView.addGestureRecognizer(longPressGesture)

        if UIDevice.current.userInterfaceIdiom == .pad {
            plusButton.setImage(UIImage(named: "add")!.withRenderingMode(.alwaysTemplate), for: .normal)
            plusButton.imageEdgeInsets = UIEdgeInsetsMake(6, 10, 6, 10)
            plusButton.tintColor = UIColor.black
            plusButton.contentMode = .scaleAspectFit
            plusButton.addTarget(self, action: #selector(addTabPressed), for: .touchUpInside)
            plusButton.backgroundColor = UIColor.init(white: 0.0, alpha: 0.1)
            view.addSubview(plusButton)

            plusButton.snp.makeConstraints { (make) in
                make.right.top.bottom.equalTo(view)
                make.width.equalTo(BraveUX.TabsBarPlusButtonWidth)
            }
            
            collectionView.snp.makeConstraints { (make) in
                make.bottom.top.left.equalTo(view)
                make.right.equalTo(view).inset(BraveUX.TabsBarPlusButtonWidth)
            }
        }
        else {
            collectionView.snp.makeConstraints { (make) in
                make.edges.equalTo(view)
            }
        }

        getApp().tabManager.addDelegate(self)
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
    
    func addTabPressed() {
        getApp().tabManager.addTabAndSelect()
    }

    func tabOverflowWidth(_ tabCount: Int) -> CGFloat {
        let overflow = CGFloat(tabCount) * minTabWidth - collectionView.frame.width
        return overflow > 0 ? overflow : 0
    }

    override func viewDidAppear(_ animated: Bool) {
        if getApp().tabManager.tabCount < 1 {
            return
        }
    }
    
    func overflowIndicators() {
        if tabOverflowWidth(getApp().tabManager.tabCount) < 1 {
            leftOverflowIndicator.opacity = 0
            rightOverflowIndicator.opacity = 0
            return
        }
        
        let offset = Float(collectionView.contentOffset.x)
        let startFade = Float(30)
        if offset < startFade {
            leftOverflowIndicator.opacity = offset / startFade
        } else {
            leftOverflowIndicator.opacity = 1
        }
        
        // all the way scrolled right
        let offsetFromRight = collectionView.contentSize.width - CGFloat(offset) - collectionView.frame.width
        if offsetFromRight < CGFloat(startFade) {
            rightOverflowIndicator.opacity = Float(offsetFromRight) / startFade
        } else {
            rightOverflowIndicator.opacity = 1
        }
    }

    func addLeftRightScrollHint(_ isRightSide: Bool, maskLayer: CAGradientLayer) {
        maskLayer.removeFromSuperlayer()
        let colors = PrivateBrowsing.singleton.isOn ? [BraveUX.DarkToolbarsBackgroundSolidColor.withAlphaComponent(0).cgColor, BraveUX.DarkToolbarsBackgroundSolidColor.cgColor] : [BraveUX.ToolbarsBackgroundSolidColor.withAlphaComponent(0).cgColor, BraveUX.ToolbarsBackgroundSolidColor.cgColor]
        let locations = [0.9, 1.0]
        maskLayer.startPoint = CGPoint(x: isRightSide ? 0 : 1.0, y: 0.5)
        maskLayer.endPoint = CGPoint(x: isRightSide ? 1.0 : 0, y: 0.5)
        maskLayer.opacity = 0
        maskLayer.colors = colors;
        maskLayer.locations = locations as [NSNumber];
        maskLayer.bounds = CGRect(x: 0, y: 0, width: collectionView.frame.width, height: tabHeight)
        maskLayer.anchorPoint = CGPoint.zero;
        // you must add the mask to the root view, not the scrollView, otherwise the masks will move as the user scrolls!
        view.layer.addSublayer(maskLayer)
    }
}

extension TabsBarViewController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        overflowIndicators()
    }
}

extension TabsBarViewController: UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 1
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return getApp().tabManager.tabCount
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell: TabBarCell = collectionView.dequeueReusableCell(withReuseIdentifier: "TabCell", for: indexPath) as! TabBarCell
        let tab = getApp().tabManager.tabs.tabs[indexPath.row]
        cell.delegate = self
        cell.browser = tab
        cell.title.text = tab.lastTitle ?? TabMO.getByID(tab.tabID)?.title ?? ""
        cell.isSelected = (indexPath.row == getApp().tabManager.currentIndex)
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let tab = getApp().tabManager.tabs.tabs[indexPath.row]
        let cell = collectionView.cellForItem(at: indexPath)
        cell?.isSelected = true
        getApp().tabManager.selectTab(tab)
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if getApp().tabManager.tabCount == 1 {
            return CGSize(width: view.frame.width, height: view.frame.height)
        }
        
        return CGSize(width: minTabWidth, height: view.frame.height)
    }
    
    func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
        return true
    }
    
    func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
        let tab = getApp().tabManager.tabs.tabs[sourceIndexPath.row]
        getApp().tabManager.move(tab: tab, from: sourceIndexPath.row, to: destinationIndexPath.row)
    }
}

extension TabsBarViewController: TabBarCellDelegate {
    func tabClose(_ tab: Browser?) {
        guard let tab = tab else { return }
        guard let tabManager = getApp().tabManager else { return }
        
        tabManager.removeTab(tab, createTabIfNoneLeft: true)
        
        let previousOrNext = max(0, (tabManager.currentIndex ?? 0))
        tabManager.selectTab(tabManager.tabs.tabs[previousOrNext])
        
        collectionView.selectItem(at: IndexPath(row: tabManager.currentIndex ?? 0, section: 0), animated: true, scrollPosition: .left)
    }
}

extension TabsBarViewController: TabManagerDelegate {
    func tabManagerDidEnterPrivateBrowsingMode(_ tabManager: TabManager) {
        assert(Thread.current.isMainThread)
        collectionView.reloadData()
    }

    func tabManagerDidExitPrivateBrowsingMode(_ tabManager: TabManager) {
        assert(Thread.current.isMainThread)
        collectionView.reloadData()
    }

    func tabManager(_ tabManager: TabManager, didSelectedTabChange selected: Browser?) {
        assert(Thread.current.isMainThread)
        collectionView.reloadData()
        collectionView.selectItem(at: IndexPath(row: tabManager.currentIndex ?? 0, section: 0), animated: true, scrollPosition: .left)
    }

    func tabManager(_ tabManager: TabManager, didCreateWebView tab: Browser, url: URL?, at: Int?) {
        collectionView.reloadData()
        getApp().browserViewController.urlBar.updateTabsBarShowing()
    }

    func tabManager(_ tabManager: TabManager, didAddTab tab: Browser) {
        collectionView.reloadData()
        getApp().browserViewController.urlBar.updateTabsBarShowing()
    }

    func tabManager(_ tabManager: TabManager, didRemoveTab tab: Browser) {
        assert(Thread.current.isMainThread)
        collectionView.reloadData()
        getApp().browserViewController.urlBar.updateTabsBarShowing()
    }

    func tabManagerDidRestoreTabs(_ tabManager: TabManager) {
        assert(Thread.current.isMainThread)
        
        collectionView.reloadData()
        getApp().browserViewController.urlBar.updateTabsBarShowing()
    }

    func tabManagerDidAddTabs(_ tabManager: TabManager) {}
}
