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
    private static let WelcomeScreenPadding: CGFloat = 15
    private static let WelcomeScreenItemTextColor = UIColor.grayColor()
    private static let WelcomeScreenItemWidth = 170
}

class TopSitesPanel: UIViewController {
    weak var homePanelDelegate: HomePanelDelegate?
    private var collection: TopSitesCollectionView? = nil
    private var privateTabMessageContainer: UIView!
    private var privateTabGraphic: UIImageView!
    private var privateTabTitleLabel: UILabel!
    private var privateTabInfoLabel: UILabel!
    private var privateTabLinkButton: UIButton!
    private var braveShieldStatsView: BraveShieldStatsView? = nil
    private lazy var dataSource: TopSitesDataSource = {
        return TopSitesDataSource()
    }()
    private lazy var layout: TopSitesLayout = { return TopSitesLayout() }()

    private lazy var maxFrecencyLimit: Int = {
        return max(
            self.calculateApproxThumbnailCountForOrientation(UIInterfaceOrientation.LandscapeLeft),
            self.calculateApproxThumbnailCountForOrientation(UIInterfaceOrientation.Portrait)
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

    override func viewWillTransitionToSize(size: CGSize, withTransitionCoordinator coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransitionToSize(size, withTransitionCoordinator: coordinator)

        coordinator.animateAlongsideTransition({ context in
            self.collection?.reloadData()
        }, completion: nil)
    }

    override func supportedInterfaceOrientations() -> UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.AllButUpsideDown
    }

    init() {
        super.init(nibName: nil, bundle: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(TopSitesPanel.notificationReceived(_:)), name: NotificationPrivateDataClearedHistory, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(TopSitesPanel.notificationReceived(_:)), name: NotificationPrivacyModeChanged, object: nil)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(TopSitesPanel.handleRotation), name: UIDeviceOrientationDidChangeNotification, object: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let statsHeight: CGFloat = 150.0
        let statsBottomMargin: CGFloat = 25.0
        
        privateTabMessageContainer = UIView()
        privateTabMessageContainer.userInteractionEnabled = true
        privateTabMessageContainer.hidden = !PrivateBrowsing.singleton.isOn
        
        privateTabGraphic = UIImageView(image: UIImage(named: "privateLion"))
        privateTabMessageContainer.addSubview(privateTabGraphic)
        
        privateTabTitleLabel = UILabel()
        privateTabTitleLabel.lineBreakMode = .ByWordWrapping
        privateTabTitleLabel.font = UIFont.systemFontOfSize(18, weight: UIFontWeightSemibold)
        privateTabTitleLabel.textColor = UIColor(white: 1, alpha: 0.6)
        privateTabTitleLabel.text = Strings.Private_Tab_Title
        privateTabMessageContainer.addSubview(privateTabTitleLabel)
        
        privateTabInfoLabel = UILabel()
        privateTabInfoLabel.lineBreakMode = .ByWordWrapping
        privateTabInfoLabel.textAlignment = .Center
        privateTabInfoLabel.numberOfLines = 0
        privateTabInfoLabel.font = UIFont.systemFontOfSize(14, weight: UIFontWeightMedium)
        privateTabInfoLabel.textColor = UIColor(white: 1, alpha: 1.0)
        privateTabInfoLabel.text = Strings.Private_Tab_Body
        privateTabMessageContainer.addSubview(privateTabInfoLabel)
        
        privateTabLinkButton = UIButton()
        let linkButtonTitle = NSAttributedString(string: Strings.Private_Tab_Link, attributes:
            [NSUnderlineStyleAttributeName: NSUnderlineStyle.StyleSingle.rawValue])
        privateTabLinkButton.setAttributedTitle(linkButtonTitle, forState: .Normal)
        privateTabLinkButton.titleLabel?.font = UIFont.systemFontOfSize(16, weight: UIFontWeightMedium)
        privateTabLinkButton.titleLabel?.textColor = UIColor(white: 1, alpha: 0.25)
        privateTabLinkButton.titleLabel?.textAlignment = .Center
        privateTabLinkButton.addTarget(self, action: #selector(SEL_privateTabInfo), forControlEvents: .TouchUpInside)
        privateTabMessageContainer.addSubview(privateTabLinkButton)
        
        let collection = TopSitesCollectionView(frame: self.view.frame, collectionViewLayout: layout)
        collection.backgroundColor = PrivateBrowsing.singleton.isOn ? BraveUX.BackgroundColorForTopSitesPrivate : BraveUX.BackgroundColorForBookmarksHistoryAndTopSites
        collection.delegate = self
        collection.dataSource = PrivateBrowsing.singleton.isOn ? nil : dataSource
        collection.registerClass(ThumbnailCell.self, forCellWithReuseIdentifier: ThumbnailIdentifier)
        collection.keyboardDismissMode = .OnDrag
        collection.accessibilityIdentifier = "Top Sites View"
        // Entire site panel, including the stats view insets
        collection.contentInset = UIEdgeInsetsMake(statsHeight, 0, 0, 0)
        view.addSubview(collection)
        collection.snp_makeConstraints { make in
            make.edges.equalTo(self.view)
        }
        self.collection = collection
        
        let braveShieldStatsView = BraveShieldStatsView(frame: CGRectZero)
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
        statsViewFrame.size.width = CGRectGetWidth(collection.frame) - CGRectGetMinX(statsViewFrame) * 2
        statsViewFrame.size.height = statsHeight
        braveShieldStatsView.frame = statsViewFrame
        braveShieldStatsView.autoresizingMask = [.FlexibleWidth]

        self.dataSource.collectionView = self.collection
        self.refreshTopSites(self.maxFrecencyLimit)
        
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
        
        let toInterfaceOrientation = UIApplication.sharedApplication().statusBarOrientation
        
        if UIDevice.currentDevice().userInterfaceIdiom == .Pad {
            return
        }
        
        if toInterfaceOrientation == .LandscapeLeft || toInterfaceOrientation == .LandscapeRight {
            UIView.animateWithDuration(0.2, animations: {
                self.privateTabGraphic.alpha = 0
            })
        }
        else {
            UIView.animateWithDuration(0.2, animations: {
                self.privateTabGraphic.alpha = 1
            })
        }
        
        self.view.setNeedsUpdateConstraints()
    }
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self, name: NotificationPrivateDataClearedHistory, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: NotificationPrivacyModeChanged, object: nil)
        NSNotificationCenter.defaultCenter().removeObserver(self, name: UIDeviceOrientationDidChangeNotification, object: nil)
    }

    func notificationReceived(notification: NSNotification) {
        switch notification.name {
        case NotificationFirefoxAccountChanged, NotificationProfileDidFinishSyncing, NotificationPrivateDataClearedHistory, NotificationDynamicFontChanged:
            refreshTopSites(maxFrecencyLimit)
            break
        case NotificationPrivacyModeChanged:
            // TODO: This entire blockshould be abstracted
            //  to make code in this class DRY (duplicates from elsewhere)
            collection?.backgroundColor = PrivateBrowsing.singleton.isOn ? BraveUX.BackgroundColorForTopSitesPrivate : BraveUX.BackgroundColorForBookmarksHistoryAndTopSites
            privateTabMessageContainer.hidden = !PrivateBrowsing.singleton.isOn
            braveShieldStatsView?.timeStatView.color = PrivateBrowsing.singleton.isOn ? .whiteColor() : .blackColor()
            collection?.reloadData()
            break
        default:
            // no need to do anything at all
            log.warning("Received unexpected notification \(notification.name)")
            break
        }
    }
    
    func SEL_privateTabInfo() {
        let url = NSURL(string: "https://github.com/brave/browser-laptop/wiki/What-a-Private-Tab-actually-does")!
        postAsyncToMain(0) {
            let t = getApp().tabManager
            t.addTabAndSelect(NSURLRequest(URL: url))
        }
    }

    //MARK: Private Helpers
    private func updateDataSourceWithSites(result: [Site], completion: ()->()) {
        self.dataSource.setHistorySites(result) {
            completion()
        }
    }

    private func updateAllRemoveButtonStates() {
        collection?.indexPathsForVisibleItems().forEach(updateRemoveButtonStateForIndexPath)
    }

    private func topSitesQuery() -> Deferred<[Site]> {
        let result = Deferred<[Site]>()

        let context = DataController.shared.workerContext()
        context.performBlock {
            var sites = [Site]()

            let domains = Domain.topSitesQuery(limit: 6, context: context)
            for d in domains {
                let s = Site(url: d.url ?? "", title: "")

                if let url = d.favicon?.url {
                    s.icon = Favicon(url: url, type: IconType.Guess)
                }
                sites.append(s)
            }
            
            result.fill(sites)
        }
        return result
    }

    private func deleteHistoryTileForSite(site: Site, atIndexPath indexPath: NSIndexPath) {
        collection?.userInteractionEnabled = false

        guard let url = NSURL(string: site.url) else { return }
        let context = DataController.shared.workerContext()
        context.performBlock {
            Domain.blockFromTopSites(url, context: context)
            
            postAsyncToMain {
                self.dataSource.sites = self.dataSource.sites.filter { $0 !== site }

                // Update the UICollectionView.
                self.deleteOrUpdateSites(indexPath) >>> {
                    // Finally, requery to pull in the latest sites.
                    self.topSitesQuery().uponQueue(dispatch_get_main_queue()) { sites in
                        self.updateDataSourceWithSites(sites) {
                            self.collection?.userInteractionEnabled = true
                        }
                    }
                }
            }
        }
    }

    private func updateRemoveButtonStateForIndexPath(indexPath: NSIndexPath) {
        // If we have a cell passed in, use it. If not, then use the indexPath to get it.
        guard let cell = collection?.cellForItemAtIndexPath(indexPath) as? ThumbnailCell else {
            return
        }

        cell.toggleRemoveButton(editingThumbnails)
    }

    private func refreshTopSites(frecencyLimit: Int) {
            // Don't allow Sync or other notifications to change the data source if we're deleting a thumbnail.
            if !(self.collection?.userInteractionEnabled ?? true) {
                return
            }

            self.reloadTopSitesWithLimit(frecencyLimit)
    }

    private func reloadTopSitesWithLimit(limit: Int) -> Success {
        let result = Success()
        topSitesQuery().uponQueue(dispatch_get_main_queue()) { sites in
            self.updateDataSourceWithSites(sites) {
                self.collection?.reloadData()
                result.fill(Maybe(success: ()))
            }
        }
        return result
    }

    private func deleteOrUpdateSites(indexPath: NSIndexPath) -> Success {
        guard let collection = self.collection else { return succeed() }

        let result = Success()

        collection.performBatchUpdates({
            collection.deleteItemsAtIndexPaths([indexPath])

            // If we have more items in our data source, replace the deleted site with a new one.
            let count = collection.numberOfItemsInSection(0) - 1
            if count < self.dataSource.count() {
                collection.insertItemsAtIndexPaths([ NSIndexPath(forItem: count, inSection: 0) ])
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
    private func calculateApproxThumbnailCountForOrientation(orientation: UIInterfaceOrientation) -> Int {
        let size = UIScreen.mainScreen().bounds.size
        let portraitSize = CGSize(width: min(size.width, size.height), height: max(size.width, size.height))

        func calculateRowsForSize(size: CGSize, columns: Int) -> Int {
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
    func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath) {
        if editingThumbnails {
            return
        }

        if let site = dataSource[indexPath.item] {
            // We're gonna call Top Sites bookmarks for now.
            let urlString = "\(NSURL(string: site.url)?.scheme ?? "")://\(NSURL(string: site.url)?.host ?? "")"
            homePanelDelegate?.homePanel(self, didSelectURL: NSURL(string: urlString) ?? site.tileURL)
        }
    }

    func collectionView(collectionView: UICollectionView, willDisplayCell cell: UICollectionViewCell, forItemAtIndexPath indexPath: NSIndexPath) {
        if let thumbnailCell = cell as? ThumbnailCell {
            thumbnailCell.delegate = self
            if editingThumbnails && indexPath.item < dataSource.count() && thumbnailCell.removeButton.hidden {
                thumbnailCell.removeButton.hidden = false
            }
        }
    }
}

extension TopSitesPanel: ThumbnailCellDelegate {
    func didRemoveThumbnail(thumbnailCell: ThumbnailCell) {
        guard let indexPath = collection?.indexPathForCell(thumbnailCell),
              let site = dataSource[indexPath.item] else { return }

        self.deleteHistoryTileForSite(site, atIndexPath: indexPath)
    }

    func didLongPressThumbnail(thumbnailCell: ThumbnailCell) {
        editingThumbnails = true
        (view.window as! BraveMainWindow).addTouchFilter(self)
    }
}

private class TopSitesCollectionView: UICollectionView {
    private override func touchesBegan(touches: Set<UITouch>, withEvent event: UIEvent?) {
        // Hide the keyboard if this view is touched.
        window?.rootViewController?.view.endEditing(true)
        super.touchesBegan(touches, withEvent: event)
    }
}

class TopSitesLayout: UICollectionViewLayout {

    var thumbnailCount: Int {
        assertIsMainThread("layout.thumbnailCount interacts with UIKit components - cannot call from background thread.")
        return thumbnailRows * thumbnailCols
    }

    private var thumbnailRows: Int {
        assert(NSThread.isMainThread(), "Interacts with UIKit components - not thread-safe.")
        return 2 // max(2, Int((self.collectionView?.frame.height ?? self.thumbnailHeight) / self.thumbnailHeight))
    }

    private var thumbnailCols: Int {
        assert(NSThread.isMainThread(), "Interacts with UIKit components - not thread-safe.")

        let size = collectionView?.bounds.size ?? CGSizeZero
        let traitCollection = collectionView!.traitCollection
        var cols = 0
        if traitCollection.horizontalSizeClass == .Compact {
            // Landscape iPhone
            if traitCollection.verticalSizeClass == .Compact {
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

    private var width: CGFloat {
        assertIsMainThread("layout.width interacts with UIKit components - cannot call from background thread.")
        return self.collectionView?.frame.width ?? 0
    }

    // The width and height of the thumbnail here are the width and height of the tile itself, not the image inside the tile.
    private var thumbnailWidth: CGFloat {
        assertIsMainThread("layout.thumbnailWidth interacts with UIKit components - cannot call from background thread.")

        let size = collectionView?.bounds.size ?? CGSizeZero
        let insets = ThumbnailCellUX.insetsForCollectionViewSize(size,
            traitCollection:  collectionView!.traitCollection)

        return floor(width - insets.left - insets.right) / CGFloat(thumbnailCols)
    }
    // The tile's height is determined the aspect ratio of the thumbnails width. We also take into account
    // some padding between the title and the image.
    private var thumbnailHeight: CGFloat {
        assertIsMainThread("layout.thumbnailHeight interacts with UIKit components - cannot call from background thread.")

        return floor(thumbnailWidth / (CGFloat(ThumbnailCellUX.ImageAspectRatio) - 0.1))
    }

    // Used to calculate the height of the list.
    private var count: Int {
        if let dataSource = self.collectionView?.dataSource as? TopSitesDataSource {
            return dataSource.collectionView(self.collectionView!, numberOfItemsInSection: 0)
        }
        return 0
    }

    private var topSectionHeight: CGFloat {
        let maxRows = ceil(Float(count) / Float(thumbnailCols))
        let rows = min(Int(maxRows), thumbnailRows)
        let size = collectionView?.bounds.size ?? CGSizeZero
        let insets = ThumbnailCellUX.insetsForCollectionViewSize(size,
            traitCollection:  collectionView!.traitCollection)
        return thumbnailHeight * CGFloat(rows) + insets.top + insets.bottom
    }

    private func getIndexAtPosition(y: CGFloat) -> Int {
        if y < topSectionHeight {
            let row = Int(y / thumbnailHeight)
            return min(count - 1, max(0, row * thumbnailCols))
        }
        return min(count - 1, max(0, Int((y - topSectionHeight) / UIConstants.DefaultRowHeight + CGFloat(thumbnailCount))))
    }

    override func collectionViewContentSize() -> CGSize {
        if count <= thumbnailCount {
            return CGSize(width: width, height: topSectionHeight)
        }

        let bottomSectionHeight = CGFloat(count - thumbnailCount) * UIConstants.DefaultRowHeight
        return CGSize(width: width, height: topSectionHeight + bottomSectionHeight)
    }

    private var layoutAttributes:[UICollectionViewLayoutAttributes]?

    override func prepareLayout() {
        var layoutAttributes = [UICollectionViewLayoutAttributes]()
        for section in 0..<(self.collectionView?.numberOfSections() ?? 0) {
            for item in 0..<(self.collectionView?.numberOfItemsInSection(section) ?? 0) {
                let indexPath = NSIndexPath(forItem: item, inSection: section)
                guard let attrs = self.layoutAttributesForItemAtIndexPath(indexPath) else { continue }
                layoutAttributes.append(attrs)
            }
        }
        self.layoutAttributes = layoutAttributes
    }

    override func layoutAttributesForElementsInRect(rect: CGRect) -> [UICollectionViewLayoutAttributes]? {
        var attrs = [UICollectionViewLayoutAttributes]()
        if let layoutAttributes = self.layoutAttributes {
            for attr in layoutAttributes {
                if CGRectIntersectsRect(rect, attr.frame) {
                    attrs.append(attr)
                }
            }
        }

        return attrs
    }

    override func layoutAttributesForItemAtIndexPath(indexPath: NSIndexPath) -> UICollectionViewLayoutAttributes? {
        let attr = UICollectionViewLayoutAttributes(forCellWithIndexPath: indexPath)

        // Set the top thumbnail frames.
        let row = floor(Double(indexPath.item / thumbnailCols))
        let col = indexPath.item % thumbnailCols
        let size = collectionView?.bounds.size ?? CGSizeZero
        let insets = ThumbnailCellUX.insetsForCollectionViewSize(size,
            traitCollection:  collectionView!.traitCollection)
        let x = insets.left + thumbnailWidth * CGFloat(col)
        let y = insets.top + CGFloat(row) * thumbnailHeight
        attr.frame = CGRectMake(ceil(x), ceil(y), thumbnailWidth, thumbnailHeight)

        return attr
    }
}

private class TopSitesDataSource: NSObject, UICollectionViewDataSource {
    var editingThumbnails: Bool = false
    var suggestedSites = [SuggestedSite]()
    var sites = [Site]()
    private var sitesInvalidated = true

    weak var collectionView: UICollectionView?
    private let BackgroundFadeInDuration: NSTimeInterval = 0.3

    @objc func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        // If there aren't enough data items to fill the grid, look for items in suggested sites.
        if let layout = collectionView.collectionViewLayout as? TopSitesLayout {
            return min(count(), layout.thumbnailCount)
        }

        return 0
    }

    private func setDefaultThumbnailBackgroundForCell(cell: ThumbnailCell) {
        cell.imageView.image = UIImage(named: "defaultTopSiteIcon")!
        cell.imageView.contentMode = UIViewContentMode.Center
    }
    
    private func setColorBackground(image: UIImage, withURL url: NSURL, forCell cell: ThumbnailCell) {
        // TODO:
        // Currently just calculate the background image color everytime.
        // This will be refactored when the switch to coredata happens (then the image color can be stored)
        
        let rgba = UnsafeMutablePointer<CUnsignedChar>.alloc(4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.PremultipliedLast.rawValue)
        let context: CGContextRef = CGBitmapContextCreate(rgba, 1, 1, 8, 4, colorSpace, info.rawValue)!

        guard let newImage = image.CGImage else { return }
        CGContextDrawImage(context, CGRectMake(0, 0, 1, 1), newImage)
        
        let red = CGFloat(rgba[0]) / 255.0
        let green = CGFloat(rgba[1]) / 255.0
        let blue = CGFloat(rgba[2]) / 255.0
        let colorFill: UIColor = UIColor(red: red, green: green, blue: blue, alpha: 1.0)
        
        cell.imageView.backgroundColor = colorFill
    }

    private func downloadFaviconsAndUpdateForSite(site: Site) {
        guard let siteURL = site.url.asURL else { return }

        FaviconFetcher.getForURL(siteURL).uponQueue(dispatch_get_main_queue()) { result in
            guard let favicons = result.successValue where favicons.count > 0,
                  let url = favicons.first?.url.asURL,
                  let indexOfSite = (self.sites.indexOf { $0 == site }) else {
                return
            }

            let indexPathToUpdate = NSIndexPath(forItem: indexOfSite, inSection: 0)
            guard let cell = self.collectionView?.cellForItemAtIndexPath(indexPathToUpdate) as? ThumbnailCell else { return }
            cell.imageView.sd_setImageWithURL(url) { (img, err, type, url) -> Void in
                guard let img = img else {
                    self.setDefaultThumbnailBackgroundForCell(cell)
                    return
                }
                cell.image = img
                self.setColorBackground(img, withURL: url, forCell: cell)
            }
        }
    }

    private func configureCell(cell: ThumbnailCell, forSite site: Site, isEditing editing: Bool) {

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
        cell.removeButton.hidden = !editing

        guard let icon = site.icon else {
            setDefaultThumbnailBackgroundForCell(cell)
            downloadFaviconsAndUpdateForSite(site)
            return
        }

        // We've looked before recently and didn't find a favicon
        switch icon.type {
        case .NoneFound where NSDate().timeIntervalSinceDate(icon.date) < FaviconFetcher.ExpirationTime:
            self.setDefaultThumbnailBackgroundForCell(cell)
        default:
            cell.imageView.sd_setImageWithURL(icon.url.asURL, completed: { (img, err, type, url) -> Void in
                if let img = img {
                    cell.image = img
                    self.setColorBackground(img, withURL: url, forCell: cell)
                } else {
                    self.setDefaultThumbnailBackgroundForCell(cell)
                    self.downloadFaviconsAndUpdateForSite(site)
                }
            })
        }
    }

    private func configureCell(cell: ThumbnailCell, forSuggestedSite site: SuggestedSite) {
        cell.textLabel.text = site.title.isEmpty ? NSURL(string: site.url)?.normalizedHostAndPath() : site.title.lowercaseString
        cell.imageView.backgroundColor = site.backgroundColor
        cell.imageView.contentMode = .ScaleAspectFit
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
                image.drawInRect(CGRect(origin: CGPoint(x: 3, y: 6), size: CGSizeMake(image.size.width - 6, image.size.height - 6)))
                let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
                UIGraphicsEndImageContext()
                cell.imageView.image = scaledImage
            }

        } else {
            cell.imageView.sd_setImageWithURL(icon, completed: { img, err, type, key in
                if img == nil {
                    self.setDefaultThumbnailBackgroundForCell(cell)
                }
            })
        }
    }

    private func setHistorySites(historySites: [Site], completion: ()->()) {
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
            if let index = historySites.indexOf({ extractDomainURL($0.url) == extractDomainURL(site.url) }) {
                historySites.removeAtIndex(index)
                return true
            }

            return site is SuggestedSite
        }

        self.sites += historySites
        
        let prefs: Prefs? = getApp().profile?.prefs
        if prefs?.boolForKey("ClearedBrowsingHistory") == false {
            mergeBuiltInSuggestedSites { completion() }
        }
        else {
            completion()
        }
    }

    private func mergeBuiltInSuggestedSites(completion: ()->()) {
        suggestedSites = SuggestedSites.asArray()
        var blocked = [Domain]()

        let context = DataController.shared.workerContext()
        context.performBlock {
            blocked = Domain.blockedTopSites(context)
            postAsyncToMain {
                for domain in blocked {
                    self.suggestedSites = self.suggestedSites.filter { self.extractDomainURL($0.url) != self.extractDomainURL(domain.url!) }
                }

                self.sites = self.sites.map { site in
                    let domainURL = self.extractDomainURL(site.url)
                    if let index = (self.suggestedSites.indexOf { self.extractDomainURL($0.url) == domainURL }) {
                        let suggestedSite = self.suggestedSites[index]
                        self.suggestedSites.removeAtIndex(index)
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

    private func count() -> Int {
        return PrivateBrowsing.singleton.isOn ? 0 : sites.count
    }

    private func extractDomainURL(url: String) -> String {
        return NSURL(string: url)?.normalizedHost() ?? url
    }

    @objc func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        
        // Cells for the top site thumbnails.
        let site = self[indexPath.item]!
        let cell = collectionView.dequeueReusableCellWithReuseIdentifier(ThumbnailIdentifier, forIndexPath: indexPath) as! ThumbnailCell
        
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
    func filterTouch(touch: UITouch) -> Bool {
        if (touch.view as? UIButton) == nil && touch.phase == .Began {
            self.endEditing()
        }
        return false
    }
}

