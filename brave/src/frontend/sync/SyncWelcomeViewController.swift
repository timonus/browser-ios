/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

let SyncBackgroundColor = UIColor(rgb: 0xF8F8F8)

class SyncWelcomeViewController: UIViewController {
    
    var scrollView: UIScrollView!
    var graphic: UIImageView!
    var titleLabel: UILabel!
    var descriptionLabel: UILabel!
    var newToSyncButton: UIButton!
    var existingUserButton: UIButton!
    
    var loadingView = UIView()
    
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
        titleLabel.textColor = UIColor.black
        titleLabel.text = Strings.BraveSync
        scrollView.addSubview(titleLabel)
        
        descriptionLabel = UILabel()
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.font = UIFont.systemFont(ofSize: 15, weight: UIFontWeightRegular)
        descriptionLabel.textColor = UIColor(rgb: 0x696969)
        descriptionLabel.numberOfLines = 0
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.textAlignment = .center
        descriptionLabel.text = Strings.BraveSyncWelcome
        scrollView.addSubview(descriptionLabel)
        
        existingUserButton = UIButton(type: .roundedRect)
        existingUserButton.translatesAutoresizingMaskIntoConstraints = false
        existingUserButton.setTitle(Strings.ScanSyncCode, for: .normal)
        existingUserButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: UIFontWeightBold)
        existingUserButton.setTitleColor(UIColor.white, for: .normal)
        existingUserButton.backgroundColor = BraveUX.DefaultBlue
        existingUserButton.layer.cornerRadius = 8
        existingUserButton.addTarget(self, action: #selector(SEL_existingUser), for: .touchUpInside)
        scrollView.addSubview(existingUserButton)
        
        newToSyncButton = UIButton(type: .roundedRect)
        newToSyncButton.translatesAutoresizingMaskIntoConstraints = false
        newToSyncButton.setTitle(Strings.NewSyncCode, for: .normal)
        newToSyncButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: UIFontWeightSemibold)
        newToSyncButton.setTitleColor(UIColor(rgb: 0x696969), for: .normal)
        newToSyncButton.addTarget(self, action: #selector(SEL_newToSync), for: .touchUpInside)
        scrollView.addSubview(newToSyncButton)
        
        let spinner = UIActivityIndicatorView(activityIndicatorStyle: .whiteLarge)
        spinner.startAnimating()
        loadingView.backgroundColor = UIColor(white: 0.5, alpha: 0.5)
        loadingView.isHidden = true
        loadingView.addSubview(spinner)
        view.addSubview(loadingView)
        
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
            make.top.equalTo(self.titleLabel.snp.bottom).offset(7)
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
        
        spinner.snp.makeConstraints { (make) in
            make.center.equalTo(spinner.superview!)
        }
        
        loadingView.snp.makeConstraints { (make) in
            make.edges.equalTo(loadingView.superview!)
        }
    }
    
    func SEL_newToSync() {
        
        func attemptPush() {
            if navigationController?.topViewController is SyncAddDeviceViewController {
                // Already showing
                return
            }
            
            if Sync.shared.isInSyncGroup {
                let view = SyncAddDeviceTypeViewController()
                view.navigationItem.hidesBackButton = true
                navigationController?.pushViewController(view, animated: true)
            } else {
                self.loadingView.isHidden = true
                let alert = UIAlertController(title: Strings.SyncUnsuccessful, message: Strings.SyncUnableCreateGroup, preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: Strings.OK, style: .default, handler: nil))
                self.present(alert, animated: true, completion: nil)
            }
        }
        
        if !Sync.shared.isInSyncGroup {
            NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: NotificationSyncReady), object: nil, queue: OperationQueue.main) {
                _ in attemptPush()
            }
            
            getDeviceName {
                input in
                
                if let input = input {
                    Sync.shared.initializeNewSyncGroup(deviceName: input)
                }
//                let view = SyncAddDeviceTypeViewController()
//                self.navigationController?.pushViewController(view, animated: true)
            }
            
        } else {
            attemptPush()
        }
    }
    
    func SEL_existingUser() {
        getDeviceName {
            input in
            
            if let input = input {
                let view = SyncPairCameraViewController()
                view.deviceName = input
                self.navigationController?.pushViewController(view, animated: true)
            }
        }
    }
    
    func getDeviceName(callback: @escaping (String?) -> ()) {
        self.loadingView.isHidden = false

        let alert = UIAlertController.userTextInputAlert(title: Strings.NewDevice, message: Strings.DeviceFolderName, startingText: UIDevice.current.name, forcedInput: false) { input, _ in
            callback(input)
            self.loadingView.isHidden = true
        }
        self.present(alert, animated: true, completion: nil)
    }
    
}
