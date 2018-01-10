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
private let NewTopIdentifier = "NewTop"

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
    fileprivate static let iPhoneThumbnailSize = 90
    fileprivate static let iPadThumbnailSize = 150
}

class TopSitesPanel: UIViewController {
    weak var homePanelDelegate: HomePanelDelegate?
    fileprivate var collection: TopSitesCollectionView? = nil
    fileprivate var privateTabMessageContainer: UIView!
    fileprivate var privateTabGraphic: UIImageView!
    fileprivate var privateTabTitleLabel: UILabel!
    fileprivate var privateTabInfoLabel: UILabel!
    fileprivate var privateTabLinkButton: UIButton!
    fileprivate var braveShieldStatsView: BraveShieldStatsView? = nil
    fileprivate lazy var dataSource: FavouritesDataSource = { return FavouritesDataSource() }()
    fileprivate lazy var layout: UICollectionViewFlowLayout = {
        let layout = UICollectionViewFlowLayout()

        // TODO: A bit larger thumbnails for iPhone horizontal? Currently it shows 7 sites.
        let size = DeviceDetector.isIpad ? TopSitesPanelUX.iPadThumbnailSize : TopSitesPanelUX.iPhoneThumbnailSize
        layout.itemSize = CGSize(width: size, height: size)
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4

        return layout

    }()

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
        NotificationCenter.default.addObserver(self, selector: #selector(TopSitesPanel.updateIphoneConstraints), name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = PrivateBrowsing.singleton.isOn ? BraveUX.BackgroundColorForTopSitesPrivate : BraveUX.BackgroundColorForBookmarksHistoryAndTopSites
        
        let statsHeight: CGFloat = 150.0
        let statsBottomMargin: CGFloat = 25.0
        
        privateTabMessageContainer = UIView()
        privateTabMessageContainer.isUserInteractionEnabled = true
        privateTabMessageContainer.isHidden = !PrivateBrowsing.singleton.isOn
        
        privateTabGraphic = UIImageView(image: UIImage(named: "privateLion"))
        privateTabMessageContainer.addSubview(privateTabGraphic)
        
        privateTabTitleLabel = UILabel()
        privateTabTitleLabel.lineBreakMode = .byWordWrapping
        privateTabTitleLabel.textAlignment = .center
        privateTabTitleLabel.numberOfLines = 0
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
        privateTabLinkButton.titleLabel?.lineBreakMode = .byWordWrapping
        privateTabLinkButton.addTarget(self, action: #selector(SEL_privateTabInfo), for: .touchUpInside)
        privateTabMessageContainer.addSubview(privateTabLinkButton)

        let collection = TopSitesCollectionView(frame: self.view.frame, collectionViewLayout: layout)
        collection.backgroundColor = PrivateBrowsing.singleton.isOn ? BraveUX.BackgroundColorForTopSitesPrivate : BraveUX.BackgroundColorForBookmarksHistoryAndTopSites
        collection.delegate = self
        collection.dataSource = PrivateBrowsing.singleton.isOn ? nil : dataSource
        collection.register(ThumbnailCell.self, forCellWithReuseIdentifier: ThumbnailIdentifier)
        collection.register(UICollectionViewCell.self, forCellWithReuseIdentifier: NewTopIdentifier)
        collection.keyboardDismissMode = .onDrag
        collection.accessibilityIdentifier = "Top Sites View"
        // Entire site panel, including the stats view insets
        collection.contentInset = UIEdgeInsetsMake(statsHeight, 0, 0, 0)
        view.addSubview(collection)
        collection.snp.makeConstraints { make -> Void in
            if #available(iOS 11.0, *) {
                make.edges.equalTo(self.view.safeAreaLayoutGuide.snp.edges)
            } else {
                make.edges.equalTo(self.view)
            }
        }

        self.collection = collection
        
        let braveShieldStatsView = BraveShieldStatsView(frame: CGRect.zero)
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
        
        privateTabMessageContainer.snp.makeConstraints { (make) -> Void in
            make.centerX.equalTo(collection)
            if UIDevice.current.userInterfaceIdiom == .pad {
                make.centerY.equalTo(self.view)
                make.width.equalTo(400)
            }
            else {
                make.top.equalTo(self.braveShieldStatsView?.snp.bottom ?? 0).offset(20)
                make.leftMargin.equalTo(collection).offset(8)
                make.rightMargin.equalTo(collection).offset(-8)
            }
            make.bottom.equalTo(collection)
        }
        
        privateTabGraphic.snp.makeConstraints { (make) -> Void in
            make.top.equalTo(0)
            make.centerX.equalTo(self.privateTabMessageContainer)
        }
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            privateTabTitleLabel.snp.makeConstraints { make in
                make.top.equalTo(self.privateTabGraphic.snp.bottom).offset(15)
                make.centerX.equalTo(self.privateTabMessageContainer)
                make.left.right.equalTo(0)
            }
            
            privateTabInfoLabel.snp.makeConstraints { (make) -> Void in
                make.top.equalTo(self.privateTabTitleLabel.snp.bottom).offset(10)
                if UIDevice.current.userInterfaceIdiom == .pad {
                    make.centerX.equalTo(collection)
                }
                
                make.left.equalTo(16)
                make.right.equalTo(-16)
            }
            
            privateTabLinkButton.snp.makeConstraints { (make) -> Void in
                make.top.equalTo(self.privateTabInfoLabel.snp.bottom).offset(10)
                make.left.equalTo(0)
                make.right.equalTo(0)
                make.bottom.equalTo(0)
            }
        } else {
            updateIphoneConstraints()
        }
    }
    
    override func viewSafeAreaInsetsDidChange() {
        // Not sure why but when a side panel is opened and you transition from portait to landscape
        // top site cells are misaligned, this is a workaroud for this edge case. Happens only on iPhoneX.
        if #available(iOS 11.0, *), DeviceDetector.iPhoneX {
            collection?.snp.remakeConstraints { make -> Void in
                make.top.equalTo(self.view.safeAreaLayoutGuide.snp.top)
                make.bottom.equalTo(self.view.safeAreaLayoutGuide.snp.bottom)
                make.leading.equalTo(self.view.safeAreaLayoutGuide.snp.leading)
                make.trailing.equalTo(self.view.safeAreaLayoutGuide.snp.trailing).offset(self.view.safeAreaInsets.right)
            }
        }
    }
    
    func updateIphoneConstraints() {
        if UIDevice.current.userInterfaceIdiom == .pad {
            return
        }
        
        let isLandscape = UIApplication.shared.statusBarOrientation.isLandscape
        
        UIView.animate(withDuration: 0.2, animations: {
            self.privateTabGraphic.alpha = isLandscape ? 0 : 1
        })
        
        let offset = isLandscape ? 10 : 15
        
        privateTabTitleLabel.snp.remakeConstraints { make in
            if isLandscape {
                make.top.equalTo(0)
            } else {
                make.top.equalTo(self.privateTabGraphic.snp.bottom).offset(offset)
            }
            make.centerX.equalTo(self.privateTabMessageContainer)
            make.left.right.equalTo(0)
        }
        
        privateTabInfoLabel.snp.remakeConstraints { make in
            make.top.equalTo(self.privateTabTitleLabel.snp.bottom).offset(offset)
            make.left.equalTo(32)
            make.right.equalTo(-32)
        }
        
        privateTabLinkButton.snp.remakeConstraints { make in
            make.top.equalTo(self.privateTabInfoLabel.snp.bottom).offset(offset)
            make.left.equalTo(32)
            make.right.equalTo(-32)
            make.bottom.equalTo(-8)
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
            // TODO: delete these notifications?
//            refreshTopSites(maxFrecencyLimit)
            break
        case NotificationPrivacyModeChanged:
            // TODO: This entire blockshould be abstracted
            //  to make code in this class DRY (duplicates from elsewhere)
            collection?.backgroundColor = PrivateBrowsing.singleton.isOn ? BraveUX.BackgroundColorForTopSitesPrivate : BraveUX.BackgroundColorForBookmarksHistoryAndTopSites
            privateTabMessageContainer.isHidden = !PrivateBrowsing.singleton.isOn
            braveShieldStatsView?.timeStatView.color = PrivateBrowsing.singleton.isOn ? .white : .black
            // Handling edge case when app starts in private only browsing mode and is switched back to normal mode.
            if collection?.dataSource == nil && !PrivateBrowsing.singleton.isOn {
                collection?.dataSource = dataSource
            }
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
            _ = t?.addTabAndSelect(URLRequest(url: url))
        }
    }
    
    //MARK: Private Helpers

    fileprivate func topSitesQuery() -> Deferred<[Site]> {
        let result = Deferred<[Site]>()

        let context = DataController.shared.workerContext
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

    fileprivate func deleteOrUpdateSites(_ indexPath: IndexPath) -> Success {
        guard let collection = self.collection else { return succeed() }

        let result = Success()

        collection.performBatchUpdates({
            collection.deleteItems(at: [indexPath as IndexPath])

            // If we have more items in our data source, replace the deleted site with a new one.
            let count = collection.numberOfItems(inSection: 0) - 1
            if let frcCount = self.dataSource.frc?.fetchedObjects?.count {
                if count < frcCount {
                    collection.insertItems(at: [ IndexPath(item: count, section: 0) ])
                }
            }
        }, completion: { _ in
            result.fill(Maybe(success: ()))
        })

        return result
    }
}

extension TopSitesPanel: HomePanel {
    func endEditing() {
        (view.window as! BraveMainWindow).removeTouchFilter(self)
        collection?.reloadData()
    }
}

extension TopSitesPanel: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let fav = dataSource.frc?.object(at: indexPath) as! Bookmark

        guard let urlString = fav.url, let url = URL(string: urlString) else { return }

        homePanelDelegate?.homePanel(self, didSelectURL: url)
    }
}

fileprivate class TopSitesCollectionView: UICollectionView {
    fileprivate override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        // Hide the keyboard if this view is touched.
        window?.rootViewController?.view.endEditing(true)
        super.touchesBegan(touches, with: event)
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
