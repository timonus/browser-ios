/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared
import XCGLogger
import Storage
import WebImage
import Deferred

private let log = Logger.browserLogger

private let ThumbnailIdentifier = "Thumbnail"

extension CGSize {
    public func widthLargerOrEqualThanHalfIPad() -> Bool {
        let halfIPadSize: CGFloat = 507
        return width >= halfIPadSize
    }
}

struct TopSitesPanelUX {
    fileprivate static let EmptyStateTitleTextColor = UIColor.darkGray
    fileprivate static let EmptyStateTopPaddingInBetweenItems: CGFloat = 15
    fileprivate static let WelcomeScreenPadding: CGFloat = 15
    fileprivate static let WelcomeScreenItemTextColor = UIColor.gray
    fileprivate static let WelcomeScreenItemWidth = 170
}

class TopSitesPanel: UIViewController {
    weak var homePanelDelegate: HomePanelDelegate?
    fileprivate lazy var emptyStateOverlayView: UIView = self.createEmptyStateOverlayView()
    fileprivate var collection: TopSitesCollectionView? = nil
    fileprivate var privateTabMessageContainer: UIView!
    fileprivate var privateTabGraphic: UIImageView!
    fileprivate var privateTabTitleLabel: UILabel!
    fileprivate var privateTabInfoLabel: UILabel!
    fileprivate var privateTabLinkButton: UIButton!
    fileprivate var braveShieldStatsView: BraveShieldStatsView? = nil
    fileprivate lazy var dataSource: TopSitesDataSource = {
        return TopSitesDataSource()
    }()
    fileprivate lazy var layout: TopSitesLayout = { return TopSitesLayout() }()

    fileprivate lazy var maxFrecencyLimit: Int = {
        return max(
            self.calculateApproxThumbnailCountForOrientation(UIInterfaceOrientation.landscapeLeft),
            self.calculateApproxThumbnailCountForOrientation(UIInterfaceOrientation.portrait)
        )
    }()

    var editingThumbnails: Bool = false {
        didSet {
            if editingThumbnails != oldValue {
                dataSource.editingThumbnails = editingThumbnails

                if editingThumbnails {
                    homePanelDelegate?.homePanelWillEnterEditingMode?(self)
                }

                updateAllRemoveButtonStates()
            }
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)

        coordinator.animate(alongsideTransition: { context in
            self.collection?.reloadData()
        }, completion: nil)
    }

    override var supportedInterfaceOrientations : UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.allButUpsideDown
    }

    init() {
        super.init(nibName: nil, bundle: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TopSitesPanel.notificationReceived(_:)), name: NotificationPrivateDataClearedHistory, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TopSitesPanel.notificationReceived(_:)), name: NotificationPrivacyModeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TopSitesPanel.handleRotation), name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let statsHeight: CGFloat = 150.0
        let statsBottomMargin: CGFloat = 25.0
        
        privateTabMessageContainer = UIView()
        privateTabMessageContainer.isUserInteractionEnabled = true
        privateTabMessageContainer.isHidden = !PrivateBrowsing.singleton.isOn
        
        privateTabGraphic = UIImageView(image: UIImage(named: "privateLion"))
        privateTabMessageContainer.addSubview(privateTabGraphic)
        
        privateTabTitleLabel = UILabel()
        privateTabTitleLabel.lineBreakMode = .byWordWrapping
        privateTabTitleLabel.font = UIFont.systemFont(ofSize: 18, weight: UIFontWeightSemibold)
        privateTabTitleLabel.textColor = UIColor(white: 1, alpha: 0.6)
        privateTabTitleLabel.text = Strings.Private_Tab_Title
        privateTabMessageContainer.addSubview(privateTabTitleLabel)
        
        privateTabInfoLabel = UILabel()
        privateTabInfoLabel.lineBreakMode = .byWordWrapping
        privateTabInfoLabel.textAlignment = .center
        privateTabInfoLabel.numberOfLines = 0
        privateTabInfoLabel.font = UIFont.systemFont(ofSize: 14, weight: UIFontWeightMedium)
        privateTabInfoLabel.textColor = UIColor(white: 1, alpha: 1.0)
        privateTabInfoLabel.text = Strings.Private_Tab_Body
        privateTabMessageContainer.addSubview(privateTabInfoLabel)
        
        privateTabLinkButton = UIButton()
        let linkButtonTitle = NSAttributedString(string: Strings.Private_Tab_Link, attributes:
            [NSUnderlineStyleAttributeName: NSUnderlineStyle.styleSingle.rawValue])
        privateTabLinkButton.setAttributedTitle(linkButtonTitle, for: .normal)
        privateTabLinkButton.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: UIFontWeightMedium)
        privateTabLinkButton.titleLabel?.textColor = UIColor(white: 1, alpha: 0.25)
        privateTabLinkButton.titleLabel?.textAlignment = .center
        privateTabLinkButton.addTarget(self, action: #selector(SEL_privateTabInfo), for: .touchUpInside)
        privateTabMessageContainer.addSubview(privateTabLinkButton)
        
        let collection = TopSitesCollectionView(frame: self.view.frame, collectionViewLayout: layout)
        collection.backgroundColor = PrivateBrowsing.singleton.isOn ? BraveUX.BackgroundColorForTopSitesPrivate : BraveUX.BackgroundColorForBookmarksHistoryAndTopSites
        collection.delegate = self
        collection.dataSource = PrivateBrowsing.singleton.isOn ? nil : dataSource
        collection.register(ThumbnailCell.self, forCellWithReuseIdentifier: ThumbnailIdentifier)
        collection.keyboardDismissMode = .onDrag
        collection.accessibilityIdentifier = "Top Sites View"
        // Entire site panel, including the stats view insets
        collection.contentInset = UIEdgeInsetsMake(statsHeight, 0, 0, 0)
        view.addSubview(collection)
        collection.snp_makeConstraints { make in
            make.edges.equalTo(self.view)
        }
        self.collection = collection
        
        let braveShieldStatsView = BraveShieldStatsView(frame: CGRect.zero)
        braveShieldStatsView.isHidden = true
        collection.addSubview(braveShieldStatsView)
        self.braveShieldStatsView = braveShieldStatsView
        
        collection.addSubview(privateTabMessageContainer)
        
        // Could setup as section header but would need to use flow layout,
        // Auto-layout subview within collection doesn't work properly,
        // Quick-and-dirty layout here.
        var statsViewFrame: CGRect = braveShieldStatsView.frame
        statsViewFrame.origin.x = 20
        // Offset the stats view from the inset set above
        statsViewFrame.origin.y = -(statsHeight + statsBottomMargin)
        statsViewFrame.size.width = collection.frame.width - statsViewFrame.minX * 2
        statsViewFrame.size.height = statsHeight
        braveShieldStatsView.frame = statsViewFrame
        braveShieldStatsView.autoresizingMask = [.flexibleWidth]

        self.dataSource.collectionView = self.collection
        self.refreshTopSites(self.maxFrecencyLimit)
        self.updateEmptyPanelState()
        
        privateTabMessageContainer.snp_makeConstraints { (make) in
            make.centerX.equalTo(self.view)
            make.centerY.equalTo(self.view)
            make.leftMargin.equalTo(self.view).offset(40)
            make.rightMargin.equalTo(self.view).offset(-40)
        }
        
        privateTabGraphic.snp_makeConstraints { (make) in
            make.top.equalTo(0)
            make.centerX.equalTo(self.privateTabMessageContainer)
        }
        
        privateTabTitleLabel.snp_makeConstraints { (make) in
            make.top.equalTo(self.privateTabGraphic.snp_bottom).offset(15)
            make.centerX.equalTo(self.privateTabMessageContainer)
        }
        
        privateTabInfoLabel.snp_makeConstraints { (make) in
            make.top.equalTo(self.privateTabTitleLabel.snp_bottom).offset(15)
            make.left.equalTo(0)
            make.right.equalTo(0)
        }
        
        privateTabLinkButton.snp_makeConstraints { (make) in
            make.top.equalTo(self.privateTabInfoLabel.snp_bottom).offset(15)
            make.left.equalTo(0)
            make.right.equalTo(0)
            make.bottom.equalTo(0)
        }
    }
    
    func handleRotation() {
        
        let toInterfaceOrientation = UIApplication.shared.statusBarOrientation
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            return
        }
        
        if toInterfaceOrientation == .landscapeLeft || toInterfaceOrientation == .landscapeRight {
            UIView.animate(withDuration: 0.2, animations: {
                self.privateTabGraphic.alpha = 0
            })
        }
        else {
            UIView.animate(withDuration: 0.2, animations: {
                self.privateTabGraphic.alpha = 1
            })
        }
        
        self.view.setNeedsUpdateConstraints()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: NotificationPrivateDataClearedHistory, object: nil)
        NotificationCenter.default.removeObserver(self, name: NotificationPrivacyModeChanged, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
    }

    func notificationReceived(_ notification: Notification) {
        switch notification.name {
        case NotificationFirefoxAccountChanged, NotificationProfileDidFinishSyncing, NotificationPrivateDataClearedHistory, NotificationDynamicFontChanged:
            refreshTopSites(maxFrecencyLimit)
            break
        case NotificationPrivacyModeChanged:
            // TODO: This entire blockshould be abstracted
            //  to make code in this class DRY (duplicates from elsewhere)
            collection?.backgroundColor = PrivateBrowsing.singleton.isOn ? BraveUX.BackgroundColorForTopSitesPrivate : BraveUX.BackgroundColorForBookmarksHistoryAndTopSites
            privateTabMessageContainer.isHidden = !PrivateBrowsing.singleton.isOn
            braveShieldStatsView?.timeStatView.color = PrivateBrowsing.singleton.isOn ? .white : .black
            collection?.reloadData()
            break
        default:
            // no need to do anything at all
            log.warning("Received unexpected notification \(notification.name)")
            break
        }
    }
    
    func SEL_privateTabInfo() {
        let url = URL(string: "https://github.com/brave/browser-laptop/wiki/What-a-Private-Tab-actually-does")!
        postAsyncToMain(0) {
            let t = getApp().tabManager
            t?.addTabAndSelect(URLRequest(url: url))
        }
    }

    fileprivate func createEmptyStateOverlayView() -> UIView {
        let overlayView = UIView()
        overlayView.backgroundColor = UIColor.white

        let descriptionLabel = UILabel()
        descriptionLabel.text = Strings.TopSitesEmptyStateDescription
        descriptionLabel.textAlignment = NSTextAlignment.center
        descriptionLabel.font = DynamicFontHelper.defaultHelper.DeviceFontLight
        descriptionLabel.textColor = TopSitesPanelUX.WelcomeScreenItemTextColor
        descriptionLabel.numberOfLines = 2
        descriptionLabel.adjustsFontSizeToFitWidth = true
        overlayView.addSubview(descriptionLabel)

        descriptionLabel.snp_makeConstraints { make in
            make.center.equalTo(overlayView)
            make.width.equalTo(TopSitesPanelUX.WelcomeScreenItemWidth)
        }

        return overlayView
    }

    fileprivate func updateEmptyPanelState() {
        if dataSource.count() == 0 && !PrivateBrowsing.singleton.isOn {
            if self.emptyStateOverlayView.superview == nil {
                self.view.addSubview(self.emptyStateOverlayView)
                self.emptyStateOverlayView.snp_makeConstraints { make -> Void in
                    make.edges.equalTo(self.view)
                }
            }
        } else {
            self.emptyStateOverlayView.removeFromSuperview()
            self.braveShieldStatsView?.isHidden = false
        }
    }

    //MARK: Private Helpers
    fileprivate func updateDataSourceWithSites(_ result: [Site], completion: @escaping ()->()) {
        self.dataSource.setHistorySites(result) {
            self.updateEmptyPanelState()
            completion()
        }
    }

    fileprivate func updateAllRemoveButtonStates() {
        collection?.indexPathsForVisibleItems.forEach(updateRemoveButtonStateForIndexPath)
    }

    fileprivate func topSitesQuery() -> Deferred<[Site]> {
        let result = Deferred<[Site]>()

        let context = DataController.shared.workerContext()
        context.perform {
            var sites = [Site]()

            let domains = Domain.topSitesQuery(6, context: context)
            for d in domains {
                let s = Site(url: d.url ?? "", title: "")

                if let url = d.favicon?.url {
                    s.icon = Favicon(url: url, type: IconType.guess)
                }
                sites.append(s)
            }
            
            result.fill(sites)
        }
        return result
    }

    fileprivate func deleteHistoryTileForSite(_ site: Site, atIndexPath indexPath: IndexPath) {
        collection?.isUserInteractionEnabled = false

        guard let url = URL(string: site.url) else { return }
        let context = DataController.shared.workerContext()
        context.perform {
            Domain.blockFromTopSites(url, context: context)
            
            postAsyncToMain {
                self.dataSource.sites = self.dataSource.sites.filter { $0 !== site }

                // Update the UICollectionView.
                self.deleteOrUpdateSites(indexPath) >>> {
                    // Finally, requery to pull in the latest sites.
                    self.topSitesQuery().uponQueue(DispatchQueue.main) { sites in
                        self.updateDataSourceWithSites(sites) {
                            self.collection?.isUserInteractionEnabled = true
                        }
                    }
                }
            }
        }
    }

    fileprivate func updateRemoveButtonStateForIndexPath(_ indexPath: IndexPath) {
        // If we have a cell passed in, use it. If not, then use the indexPath to get it.
        guard let cell = collection?.cellForItem(at: indexPath) as? ThumbnailCell else {
            return
        }

        cell.toggleRemoveButton(editingThumbnails)
    }

    fileprivate func refreshTopSites(_ frecencyLimit: Int) {
            // Don't allow Sync or other notifications to change the data source if we're deleting a thumbnail.
            if !(self.collection?.isUserInteractionEnabled ?? true) {
                return
            }

            self.reloadTopSitesWithLimit(frecencyLimit)
    }

    fileprivate func reloadTopSitesWithLimit(_ limit: Int) -> Success {
        let result = Success()
        topSitesQuery().uponQueue(DispatchQueue.main) { sites in
            self.updateDataSourceWithSites(sites) {
                self.collection?.reloadData()
                result.fill(Maybe(success: ()))
            }
        }
        return result
    }

    fileprivate func deleteOrUpdateSites(_ indexPath: IndexPath) -> Success {
        guard let collection = self.collection else { return succeed() }

        let result = Success()

        collection.performBatchUpdates({
            collection.deleteItems(at: [indexPath as IndexPath])

            // If we have more items in our data source, replace the deleted site with a new one.
            let count = collection.numberOfItems(inSection: 0) - 1
            if count < self.dataSource.count() {
                collection.insertItems(at: [ IndexPath(item: count, section: 0) ])
            }
        }, completion: { _ in
            self.updateAllRemoveButtonStates()
            result.fill(Maybe(success: ()))
        })

        return result
    }

    /**
    Calculates an approximation of the number of tiles we want to display for the given orientation. This
    method uses the screen's size as it's basis for the calculation instead of the collectionView's since the 
    collectionView's bounds is determined until the next layout pass.

    - parameter orientation: Orientation to calculate number of tiles for

    - returns: Rough tile count we will be displaying for the passed in orientation
    */
    fileprivate func calculateApproxThumbnailCountForOrientation(_ orientation: UIInterfaceOrientation) -> Int {
        let size = UIScreen.main.bounds.size
        let portraitSize = CGSize(width: min(size.width, size.height), height: max(size.width, size.height))

        func calculateRowsForSize(_ size: CGSize, columns: Int) -> Int {
            let insets = ThumbnailCellUX.insetsForCollectionViewSize(size,
                traitCollection:  traitCollection)
            let thumbnailWidth = (size.width - insets.left - insets.right) / CGFloat(columns)
            let thumbnailHeight = thumbnailWidth / CGFloat(ThumbnailCellUX.ImageAspectRatio)
            return max(2, Int(size.height / thumbnailHeight))
        }

        let numberOfColumns: Int
        let numberOfRows: Int

        if UIInterfaceOrientationIsLandscape(orientation) {
            numberOfColumns = 5
            numberOfRows = calculateRowsForSize(CGSize(width: portraitSize.height, height: portraitSize.width), columns: numberOfColumns)
        } else {
            numberOfColumns = 4
            numberOfRows = calculateRowsForSize(portraitSize, columns: numberOfColumns)
        }

        return numberOfColumns * numberOfRows
    }
}

extension TopSitesPanel: HomePanel {
    func endEditing() {
        (view.window as! BraveMainWindow).removeTouchFilter(self)
        editingThumbnails = false
        collection?.reloadData()
    }
}

extension TopSitesPanel: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if editingThumbnails {
            return
        }

        if let site = dataSource[indexPath.item] {
            // We're gonna call Top Sites bookmarks for now.
            let urlString = "\(URL(string: site.url)?.scheme ?? "")://\(URL(string: site.url)?.host ?? "")"
            homePanelDelegate?.homePanel(self, didSelectURL: URL(string: urlString) ?? site.tileURL)
        }
    }

    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        if let thumbnailCell = cell as? ThumbnailCell {
            thumbnailCell.delegate = self
            if editingThumbnails && indexPath.item < dataSource.count() && thumbnailCell.removeButton.isHidden {
                thumbnailCell.removeButton.isHidden = false
            }
        }
    }
}

extension TopSitesPanel: ThumbnailCellDelegate {
    func didRemoveThumbnail(_ thumbnailCell: ThumbnailCell) {
        guard let indexPath = collection?.indexPath(for: thumbnailCell),
              let site = dataSource[indexPath.item] else { return }

        self.deleteHistoryTileForSite(site, atIndexPath: indexPath)
    }

    func didLongPressThumbnail(_ thumbnailCell: ThumbnailCell) {
        editingThumbnails = true
        (view.window as! BraveMainWindow).addTouchFilter(self)
    }
}

fileprivate class TopSitesCollectionView: UICollectionView {
    fileprivate override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Hide the keyboard if this view is touched.
        window?.rootViewController?.view.endEditing(true)
        super.touchesBegan(touches, with: event)
    }
}

class TopSitesLayout: UICollectionViewLayout {

    var thumbnailCount: Int {
        assertIsMainThread("layout.thumbnailCount interacts with UIKit components - cannot call from background thread.")
        return thumbnailRows * thumbnailCols
    }

    fileprivate var thumbnailRows: Int {
        assert(Thread.isMainThread, "Interacts with UIKit components - not thread-safe.")
        return 2 // max(2, Int((self.collectionView?.frame.height ?? self.thumbnailHeight) / self.thumbnailHeight))
    }

    fileprivate var thumbnailCols: Int {
        assert(Thread.isMainThread, "Interacts with UIKit components - not thread-safe.")

        let size = collectionView?.bounds.size ?? CGSize.zero
        let traitCollection = collectionView!.traitCollection
        var cols = 0
        if traitCollection.horizontalSizeClass == .compact {
            // Landscape iPhone
            if traitCollection.verticalSizeClass == .compact {
                cols = 5
            }
            // Split screen iPad width
            else if size.widthLargerOrEqualThanHalfIPad() ?? false {
                cols = 4
            }
            // iPhone portrait
            else {
                cols = 3
            }
        } else {
            // Portrait iPad
            if size.height > size.width {
                cols = 4;
            }
            // Landscape iPad
            else {
                cols = 5;
            }
        }
        return cols + 1
    }

    fileprivate var width: CGFloat {
        assertIsMainThread("layout.width interacts with UIKit components - cannot call from background thread.")
        return self.collectionView?.frame.width ?? 0
    }

    // The width and height of the thumbnail here are the width and height of the tile itself, not the image inside the tile.
    fileprivate var thumbnailWidth: CGFloat {
        assertIsMainThread("layout.thumbnailWidth interacts with UIKit components - cannot call from background thread.")

        let size = collectionView?.bounds.size ?? CGSize.zero
        let insets = ThumbnailCellUX.insetsForCollectionViewSize(size,
            traitCollection:  collectionView!.traitCollection)

        return floor(width - insets.left - insets.right) / CGFloat(thumbnailCols)
    }
    // The tile's height is determined the aspect ratio of the thumbnails width. We also take into account
    // some padding between the title and the image.
    fileprivate var thumbnailHeight: CGFloat {
        assertIsMainThread("layout.thumbnailHeight interacts with UIKit components - cannot call from background thread.")

        return floor(thumbnailWidth / (CGFloat(ThumbnailCellUX.ImageAspectRatio) - 0.1))
    }

    // Used to calculate the height of the list.
    fileprivate var count: Int {
        if let dataSource = self.collectionView?.dataSource as? TopSitesDataSource {
            return dataSource.collectionView(self.collectionView!, numberOfItemsInSection: 0)
        }
        return 0
    }

    fileprivate var topSectionHeight: CGFloat {
        let maxRows = ceil(Float(count) / Float(thumbnailCols))
        let rows = min(Int(maxRows), thumbnailRows)
        let size = collectionView?.bounds.size ?? CGSize.zero
        let insets = ThumbnailCellUX.insetsForCollectionViewSize(size,
            traitCollection:  collectionView!.traitCollection)
        return thumbnailHeight * CGFloat(rows) + insets.top + insets.bottom
    }

    fileprivate func getIndexAtPosition(_ y: CGFloat) -> Int {
        if y < topSectionHeight {
            let row = Int(y / thumbnailHeight)
            return min(count - 1, max(0, row * thumbnailCols))
        }
        return min(count - 1, max(0, Int((y - topSectionHeight) / UIConstants.DefaultRowHeight + CGFloat(thumbnailCount))))
    }

    override var collectionViewContentSize : CGSize {
        if count <= thumbnailCount {
            return CGSize(width: width, height: topSectionHeight)
        }

        let bottomSectionHeight = CGFloat(count - thumbnailCount) * UIConstants.DefaultRowHeight
        return CGSize(width: width, height: topSectionHeight + bottomSectionHeight)
    }

    fileprivate var layoutAttributes:[UICollectionViewLayoutAttributes]?

    override func prepare() {
        var layoutAttributes = [UICollectionViewLayoutAttributes]()
        for section in 0..<(self.collectionView?.numberOfSections ?? 0) {
            for item in 0..<(self.collectionView?.numberOfItems(inSection: section) ?? 0) {
                let indexPath = IndexPath(item: item, section: section)
                guard let attrs = self.layoutAttributesForItem(at: indexPath) else { continue }
                layoutAttributes.append(attrs)
            }
        }
        self.layoutAttributes = layoutAttributes
    }

    override func layoutAttributesForElements(in rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var attrs = [UICollectionViewLayoutAttributes]()
        if let layoutAttributes = self.layoutAttributes {
            for attr in layoutAttributes {
                if rect.intersects(attr.frame) {
                    attrs.append(attr)
                }
            }
        }

        return attrs
    }

    override func layoutAttributesForItem(at indexPath: IndexPath) -> UICollectionViewLayoutAttributes? {
        let attr = UICollectionViewLayoutAttributes(forCellWith: indexPath)

        // Set the top thumbnail frames.
        let row = floor(Double(indexPath.item / thumbnailCols))
        let col = indexPath.item % thumbnailCols
        let size = collectionView?.bounds.size ?? CGSize.zero
        let insets = ThumbnailCellUX.insetsForCollectionViewSize(size,
            traitCollection:  collectionView!.traitCollection)
        let x = insets.left + thumbnailWidth * CGFloat(col)
        let y = insets.top + CGFloat(row) * thumbnailHeight
        attr.frame = CGRect(x: ceil(x), y: ceil(y), width: thumbnailWidth, height: thumbnailHeight)

        return attr
    }
}

fileprivate class TopSitesDataSource: NSObject, UICollectionViewDataSource {
    var editingThumbnails: Bool = false
    var suggestedSites = [SuggestedSite]()
    var sites = [Site]()
    fileprivate var sitesInvalidated = true

    weak var collectionView: UICollectionView?
    fileprivate let BackgroundFadeInDuration: TimeInterval = 0.3

    @objc func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        // If there aren't enough data items to fill the grid, look for items in suggested sites.
        if let layout = collectionView.collectionViewLayout as? TopSitesLayout {
            return min(count(), layout.thumbnailCount)
        }

        return 0
    }

    fileprivate func setDefaultThumbnailBackgroundForCell(_ cell: ThumbnailCell) {
        cell.imageView.image = UIImage(named: "defaultTopSiteIcon")!
        cell.imageView.contentMode = UIViewContentMode.center
    }
    
    fileprivate func setColorBackground(_ image: UIImage, withURL url: URL, forCell cell: ThumbnailCell) {
        // TODO:
        // Currently just calculate the background image color everytime.
        // This will be refactored when the switch to coredata happens (then the image color can be stored)
        
        let rgba = UnsafeMutablePointer<CUnsignedChar>.allocate(capacity: 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        let context: CGContext = CGContext(data: rgba, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: colorSpace, bitmapInfo: info.rawValue)!

        guard let newImage = image.cgImage else { return }
        context.draw(newImage, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        
        let red = CGFloat(rgba[0]) / 255.0
        let green = CGFloat(rgba[1]) / 255.0
        let blue = CGFloat(rgba[2]) / 255.0
        let colorFill: UIColor = UIColor(red: red, green: green, blue: blue, alpha: 1.0)
        
        cell.imageView.backgroundColor = colorFill
    }

    fileprivate func downloadFaviconsAndUpdateForSite(_ site: Site) {
        guard let siteURL = site.url.asURL else { return }

        FaviconFetcher.getForURL(siteURL).uponQueue(DispatchQueue.main) { result in
            guard let favicons = result.successValue, favicons.count > 0,
                  let url = favicons.first?.url.asURL,
                    let indexOfSite = self.sites.index(where: { $0 == site }) else {
                return
            }

            let indexPathToUpdate = IndexPath(item: indexOfSite, section: 0)
            guard let cell = self.collectionView?.cellForItem(at: indexPathToUpdate) as? ThumbnailCell else { return }
            cell.imageView.sd_setImage(with: url) { (img, err, type, url) -> Void in
                guard let img = img else {
                    self.setDefaultThumbnailBackgroundForCell(cell)
                    return
                }
                cell.image = img
                self.setColorBackground(img, withURL: url!, forCell: cell)
            }
        }
    }

    fileprivate func configureCell(_ cell: ThumbnailCell, forSite site: Site, isEditing editing: Bool) {

        // We always want to show the domain URL, not the title.
        //
        // Eventually we can do something more sophisticated — e.g., if the site only consists of one
        // history item, show it, and otherwise use the longest common sub-URL (and take its title
        // if you visited that exact URL), etc. etc. — but not yet.
        //
        // The obvious solution here and in collectionView:didSelectItemAtIndexPath: is for the cursor
        // to return domain sites, not history sites -- that is, with the right icon, title, and URL --
        // and for this code to just use what it gets.
        //
        // Instead we'll painstakingly re-extract those things here.

        let domainURL = extractDomainURL(site.url)
        cell.textLabel.text = domainURL
        cell.accessibilityLabel = cell.textLabel.text
        cell.removeButton.isHidden = !editing

        guard let icon = site.icon else {
            setDefaultThumbnailBackgroundForCell(cell)
            downloadFaviconsAndUpdateForSite(site)
            return
        }

        // We've looked before recently and didn't find a favicon
        switch icon.type {
        case .noneFound where Date().timeIntervalSince(icon.date) < FaviconFetcher.ExpirationTime:
            self.setDefaultThumbnailBackgroundForCell(cell)
        default:
            cell.imageView.sd_setImage(with: icon.url.asURL, completed: { (img, err, type, url) -> Void in
                if let img = img {
                    cell.image = img
                    self.setColorBackground(img, withURL: url!, forCell: cell)
                } else {
                    self.setDefaultThumbnailBackgroundForCell(cell)
                    self.downloadFaviconsAndUpdateForSite(site)
                }
            })
        }
    }

    fileprivate func configureCell(_ cell: ThumbnailCell, forSuggestedSite site: SuggestedSite) {
        cell.textLabel.text = site.title.isEmpty ? URL(string: site.url)?.normalizedHostAndPath : site.title.lowercased()
        cell.imageView.backgroundColor = site.backgroundColor
        cell.imageView.contentMode = .scaleAspectFit
        cell.imageView.layer.minificationFilter = kCAFilterTrilinear
        cell.showBorder(!PrivateBrowsing.singleton.isOn)

        cell.accessibilityLabel = cell.textLabel.text
        
        guard let icon = site.wordmark.url.asURL,
            let host = icon.host else {
                self.setDefaultThumbnailBackgroundForCell(cell)
                return
        }

        if icon.scheme == "asset" {
            if let image = UIImage(named: host) {
                // TODO: Should no longer be needed
                
                // Brave hack. The images are too close to the top edge
                UIGraphicsBeginImageContextWithOptions(image.size, false, 0)
                image.draw(in: CGRect(origin: CGPoint(x: 3, y: 6), size: CGSize(width: image.size.width - 6, height: image.size.height - 6)))
                let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                cell.imageView.image = scaledImage
            }

        } else {
            cell.imageView.sd_setImage(with: icon, completed: { img, err, type, key in
                if img == nil {
                    self.setDefaultThumbnailBackgroundForCell(cell)
                }
            })
        }
    }

    fileprivate func setHistorySites(_ historySites: [Site], completion: @escaping ()->()) {
        self.sites = []

        // We requery every time we do a deletion. If the query contains a top site that's
        // bubbled up that wasn't there previously (e.g., a page just finished loading
        // in the background), it will change the index of any following site currently
        // displayed. This, in turn, would cause sites to shuffle around, and we would
        // possibly have duplicates if a site that's already visible has been reindexed
        // to a newly added position, post-deletion.
        //
        // The fix? Go through our existing set of sites on an update and append new sites
        // to the end. This preserves the ordering of existing sites, meaning the last
        // index, post-deletion, will always be a new site. Of course, this is temporary;
        // whenever the panel is reloaded, our transient, ordered state will be lost. But
        // that's OK: top sites change frequently anyway.
        var historySites: [Site] = historySites
        self.sites = self.sites.filter { site in
            if let index = historySites.index(where: { extractDomainURL($0.url) == extractDomainURL(site.url) }) {
                historySites.remove(at: index)
                return true
            }

            return site is SuggestedSite
        }

        self.sites += historySites
        mergeBuiltInSuggestedSites { completion() }
    }

    fileprivate func mergeBuiltInSuggestedSites(_ completion: @escaping ()->()) {
        suggestedSites = SuggestedSites.asArray()
        var blocked = [Domain]()

        let context = DataController.shared.workerContext()
        context.perform {
            blocked = Domain.blockedTopSites(context)
            postAsyncToMain {
                for domain in blocked {
                    self.suggestedSites = self.suggestedSites.filter { self.extractDomainURL($0.url) != self.extractDomainURL(domain.url!) }
                }

                self.sites = self.sites.map { site in
                    let domainURL = self.extractDomainURL(site.url)
                    if let index = (self.suggestedSites.index { self.extractDomainURL($0.url) == domainURL }) {
                        let suggestedSite = self.suggestedSites[index]
                        self.suggestedSites.remove(at: index)
                        return suggestedSite
                    }
                    return site
                }
                
                self.sites += self.suggestedSites as [Site]
                completion()
            }
        }
    }

    subscript(index: Int) -> Site? {
        if count() == 0 {
            return nil
        }

        return self.sites[index] as Site?
    }

    fileprivate func count() -> Int {
        return PrivateBrowsing.singleton.isOn ? 0 : sites.count
    }

    fileprivate func extractDomainURL(_ url: String) -> String {
        return URL(string: url)?.normalizedHost ?? url
    }

    @objc func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        
        // Cells for the top site thumbnails.
        let site = self[indexPath.item]!
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: ThumbnailIdentifier, for: indexPath) as! ThumbnailCell
        
        // TODO: Can be refactored, currently used primarily for title differences
        if let site = site as? SuggestedSite {
            configureCell(cell, forSuggestedSite: site)
        } else {
            configureCell(cell, forSite: site, isEditing: editingThumbnails)
        }

        cell.updateLayoutForCollectionViewSize(collectionView.bounds.size, traitCollection: collectionView.traitCollection, forSuggestedSite: false)
        return cell
    }
}

extension TopSitesPanel : WindowTouchFilter {
    func filterTouch(_ touch: UITouch) -> Bool {
        if (touch.view as? UIButton) == nil && touch.phase == .began {
            self.endEditing()
        }
        return false
    }
}

