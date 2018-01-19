/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

let SyncBackgroundColor = UIColor(rgb: 0xF8F8F8)

class RoundInterfaceButton: UIButton {
    override func layoutSubviews() {
        super.layoutSubviews()
        layer.cornerRadius = bounds.height / 2.0
    }
}

class SyncWelcomeViewController: UIViewController {
    
    var scrollView: UIScrollView!
    var graphic: UIImageView!
    var titleLabel: UILabel!
    var descriptionLabel: UILabel!
    var newToSyncButton: RoundInterfaceButton!
    var existingUserButton: RoundInterfaceButton!
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = Strings.Sync
        view.backgroundColor = SyncBackgroundColor
        
        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        
        graphic = UIImageView(image: UIImage(named: "sync-art"))
        graphic.translatesAutoresizingMaskIntoConstraints = false
        graphic.contentMode = .center
        scrollView.addSubview(graphic)
        
        titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 20, weight: UIFontWeightSemibold)
        titleLabel.textColor = BraveUX.GreyJ
        titleLabel.text = Strings.BraveSync
        scrollView.addSubview(titleLabel)
        
        descriptionLabel = UILabel()
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.font = UIFont.systemFont(ofSize: 15, weight: UIFontWeightRegular)
        descriptionLabel.textColor = BraveUX.GreyH
        descriptionLabel.numberOfLines = 0
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.textAlignment = .center
        descriptionLabel.text = Strings.BraveSyncWelcome
        scrollView.addSubview(descriptionLabel)
        
        existingUserButton = RoundInterfaceButton(type: .roundedRect)
        existingUserButton.translatesAutoresizingMaskIntoConstraints = false
        existingUserButton.setTitle(Strings.ScanSyncCode, for: .normal)
        existingUserButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: UIFontWeightBold)
        existingUserButton.setTitleColor(UIColor.white, for: .normal)
        existingUserButton.backgroundColor = BraveUX.Blue
        existingUserButton.addTarget(self, action: #selector(SEL_existingUser), for: .touchUpInside)
        scrollView.addSubview(existingUserButton)
        
        newToSyncButton = RoundInterfaceButton(type: .roundedRect)
        newToSyncButton.translatesAutoresizingMaskIntoConstraints = false
        newToSyncButton.setTitle(Strings.NewSyncCode, for: .normal)
        newToSyncButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: UIFontWeightSemibold)
        newToSyncButton.setTitleColor(BraveUX.GreyH, for: .normal)
        newToSyncButton.addTarget(self, action: #selector(SEL_newToSync), for: .touchUpInside)
        scrollView.addSubview(newToSyncButton)
        
        edgesForExtendedLayout = UIRectEdge()
        
        scrollView.snp.makeConstraints { (make) in
            make.edges.equalTo(self.view)
        }
        
        graphic.snp.makeConstraints { (make) in
            make.left.right.equalTo(0)
            make.height.equalTo(187)
            make.top.equalTo(50)
        }
        
        titleLabel.snp.makeConstraints { (make) in
            make.top.equalTo(self.graphic.snp.bottom).offset(50)
            make.centerX.equalTo(self.scrollView)
        }
        
        descriptionLabel.snp.makeConstraints { (make) in
            make.top.equalTo(self.titleLabel.snp.bottom).offset(8)
            make.left.equalTo(30)
            make.right.equalTo(-30)
        }
        
        existingUserButton.snp.makeConstraints { (make) in
            make.top.equalTo(self.descriptionLabel.snp.bottom).offset(30)
            make.centerX.equalTo(self.scrollView)
            make.left.equalTo(16)
            make.right.equalTo(-16)
            make.height.equalTo(50)
        }
        
        newToSyncButton.snp.makeConstraints { (make) in
            make.top.equalTo(self.existingUserButton.snp.bottom).offset(8)
            make.centerX.equalTo(self.scrollView)
            make.bottom.equalTo(-10)
        }
    }
    
    func SEL_newToSync() {
        navigationController?.pushViewController(SyncAddDeviceTypeViewController(), animated: true)
    }
    
    func SEL_existingUser() {
        self.navigationController?.pushViewController(SyncPairCameraViewController(), animated: true)
    }
}
