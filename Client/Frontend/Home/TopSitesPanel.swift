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

struct TopSitesPanelUX {
    static let iPadThumbnailSize = 150
    static let iPhoneThumbnailSize = 90
    static let statsHeight: CGFloat = 150.0
    static let statsBottomMargin: CGFloat = 25.0
}

class TopSitesPanel: UIViewController, HomePanel {
    weak var homePanelDelegate: HomePanelDelegate?

    // MARK: - Favorites collection view properties
    fileprivate lazy var collection: UICollectionView = {
        let layout = UICollectionViewFlowLayout()

        // TODO: A bit larger thumbnails for iPhone horizontal? Currently it shows 7 sites.
        let size = DeviceDetector.isIpad ? TopSitesPanelUX.iPadThumbnailSize : TopSitesPanelUX.iPhoneThumbnailSize
        layout.itemSize = CGSize(width: size, height: size)
        layout.minimumInteritemSpacing = 4
        layout.minimumLineSpacing = 4

        let view = UICollectionView(frame: self.view.frame, collectionViewLayout: layout)
        view.backgroundColor = PrivateBrowsing.singleton.isOn ? BraveUX.BackgroundColorForTopSitesPrivate : BraveUX.BackgroundColorForBookmarksHistoryAndTopSites
        view.delegate = self

        let thumbnailIdentifier = "Thumbnail"
        view.register(ThumbnailCell.self, forCellWithReuseIdentifier: thumbnailIdentifier)
        view.keyboardDismissMode = .onDrag
        view.accessibilityIdentifier = "Top Sites View"
        // Entire site panel, including the stats view insets
        view.contentInset = UIEdgeInsetsMake(TopSitesPanelUX.statsHeight, 0, 0, 0)

        return view
    }()
    fileprivate lazy var dataSource: FavoritesDataSource = { return FavoritesDataSource() }()

    // MARK: - Lazy views
    fileprivate lazy var privateTabMessageContainer: UIView = {
        let view = UIView()
        view.isUserInteractionEnabled = true
        view.isHidden = !PrivateBrowsing.singleton.isOn
        return view
    }()

    fileprivate lazy var privateTabGraphic: UIImageView = {
        return UIImageView(image: UIImage(named: "privateLion"))
    }()

    fileprivate lazy var privateTabTitleLabel: UILabel = {
        let view = UILabel()
        view.lineBreakMode = .byWordWrapping
        view.textAlignment = .center
        view.numberOfLines = 0
        view.font = UIFont.systemFont(ofSize: 18, weight: UIFontWeightSemibold)
        view.textColor = UIColor(white: 1, alpha: 0.6)
        view.text = Strings.Private_Tab_Title
        return view
    }()

    fileprivate lazy var privateTabInfoLabel: UILabel = {
        let view = UILabel()
        view.lineBreakMode = .byWordWrapping
        view.textAlignment = .center
        view.numberOfLines = 0
        view.font = UIFont.systemFont(ofSize: 14, weight: UIFontWeightMedium)
        view.textColor = UIColor(white: 1, alpha: 1.0)
        view.text = Strings.Private_Tab_Body
        return view
    }()

    fileprivate lazy var privateTabLinkButton: UIButton = {
        let view = UIButton()
        let linkButtonTitle = NSAttributedString(string: Strings.Private_Tab_Link, attributes:
            [NSUnderlineStyleAttributeName: NSUnderlineStyle.styleSingle.rawValue])
        view.setAttributedTitle(linkButtonTitle, for: .normal)
        view.titleLabel?.font = UIFont.systemFont(ofSize: 16, weight: UIFontWeightMedium)
        view.titleLabel?.textColor = UIColor(white: 1, alpha: 0.25)
        view.titleLabel?.textAlignment = .center
        view.titleLabel?.lineBreakMode = .byWordWrapping
        view.addTarget(self, action: #selector(showPrivateTabInfo), for: .touchUpInside)
        return view
    }()

    fileprivate lazy var braveShieldStatsView: BraveShieldStatsView = {
        let view = BraveShieldStatsView(frame: CGRect.zero)
        view.autoresizingMask = [.flexibleWidth]
        return view
    }()

    // MARK: - Init/lifecycle
    init() {
        super.init(nibName: nil, bundle: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TopSitesPanel.privateBrowsingModeChanged), name: NotificationPrivacyModeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(TopSitesPanel.updateIphoneConstraints), name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: NotificationPrivacyModeChanged, object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name.UIDeviceOrientationDidChange, object: nil)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.view.backgroundColor = PrivateBrowsing.singleton.isOn ? BraveUX.BackgroundColorForTopSitesPrivate : BraveUX.BackgroundColorForBookmarksHistoryAndTopSites

        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongGesture(gesture:)))
        collection.addGestureRecognizer(longPressGesture)

        view.addSubview(collection)
        collection.dataSource = PrivateBrowsing.singleton.isOn ? nil : dataSource
        self.dataSource.collectionView = self.collection

        // Could setup as section header but would need to use flow layout,
        // Auto-layout subview within collection doesn't work properly,
        // Quick-and-dirty layout here.
        var statsViewFrame: CGRect = braveShieldStatsView.frame
        statsViewFrame.origin.x = 20
        // Offset the stats view from the inset set above
        statsViewFrame.origin.y = -(TopSitesPanelUX.statsHeight + TopSitesPanelUX.statsBottomMargin)
        statsViewFrame.size.width = collection.frame.width - statsViewFrame.minX * 2
        statsViewFrame.size.height = TopSitesPanelUX.statsHeight
        braveShieldStatsView.frame = statsViewFrame

        collection.addSubview(braveShieldStatsView)

        privateTabMessageContainer.addSubview(privateTabGraphic)
        privateTabMessageContainer.addSubview(privateTabTitleLabel)
        privateTabMessageContainer.addSubview(privateTabInfoLabel)
        privateTabMessageContainer.addSubview(privateTabLinkButton)
        collection.addSubview(privateTabMessageContainer)

        makeConstraints()
    }

    /// Handles long press gesture for UICollectionView cells reorder.
    func handleLongGesture(gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            guard let selectedIndexPath = collection.indexPathForItem(at: gesture.location(in: collection)) else {
                break
            }
            collection.beginInteractiveMovementForItem(at: selectedIndexPath)
        case .changed:
            collection.updateInteractiveMovementTargetPosition(gesture.location(in: gesture.view!))
        case .ended:
            collection.endInteractiveMovement()
        default:
            collection.cancelInteractiveMovement()
        }
    }

    // MARK: - Constraints setup
    fileprivate func makeConstraints() {
        collection.snp.makeConstraints { make -> Void in
            if #available(iOS 11.0, *) {
                make.edges.equalTo(self.view.safeAreaLayoutGuide.snp.edges)
            } else {
                make.edges.equalTo(self.view)
            }
        }

        privateTabMessageContainer.snp.makeConstraints { (make) -> Void in
            make.centerX.equalTo(collection)
            if UIDevice.current.userInterfaceIdiom == .pad {
                make.centerY.equalTo(self.view)
                make.width.equalTo(400)
            }
            else {
                make.top.equalTo(self.braveShieldStatsView.snp.bottom).offset(20)
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
            collection.snp.remakeConstraints { make -> Void in
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


    // MARK: - Private browsing modde
    func privateBrowsingModeChanged() {
        let isPrivateBrowsing = PrivateBrowsing.singleton.isOn

        // TODO: This entire blockshould be abstracted
        //  to make code in this class DRY (duplicates from elsewhere)
        collection.backgroundColor = isPrivateBrowsing ? BraveUX.BackgroundColorForTopSitesPrivate : BraveUX.BackgroundColorForBookmarksHistoryAndTopSites
        privateTabMessageContainer.isHidden = !isPrivateBrowsing
        braveShieldStatsView.timeStatView.color = isPrivateBrowsing ? .white : .black
        // Handling edge case when app starts in private only browsing mode and is switched back to normal mode.
        if collection.dataSource == nil && !isPrivateBrowsing {
            collection.dataSource = dataSource
        } else if isPrivateBrowsing {
            collection.dataSource = nil
        }
        collection.reloadData()
    }
    
    func showPrivateTabInfo() {
        let url = URL(string: "https://github.com/brave/browser-laptop/wiki/What-a-Private-Tab-actually-does")!
        postAsyncToMain {
            let t = getApp().tabManager
            _ = t?.addTabAndSelect(URLRequest(url: url))
        }
    }
}

// MARK: - Delegates
extension TopSitesPanel: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let fav = dataSource.frc?.object(at: indexPath) as? Bookmark

        guard let urlString = fav?.url, let url = URL(string: urlString) else { return }

        homePanelDelegate?.homePanel(self, didSelectURL: url)
    }
}
