/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

let SyncBackgroundColor = UIColor(rgb: 0xF8F8F8)

class SyncWelcomeViewController: UIViewController {
    
    var scrollView: UIScrollView!
    var graphic: UIImageView!
    var bg: UIImageView!
    var titleLabel: UILabel!
    var descriptionLabel: UILabel!
    var newToSyncButton: UIButton!
    var existingUserButton: UIButton!
    
    var loadingView = UIView()
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = Strings.Sync
        view.backgroundColor = SyncBackgroundColor
        
        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.alwaysBounceVertical = true
        view.addSubview(scrollView)
        
        bg = UIImageView(image: UIImage(named: "sync-gradient"))
        bg.translatesAutoresizingMaskIntoConstraints = false
        bg.contentMode = .ScaleAspectFill
        bg.clipsToBounds = true
        scrollView.addSubview(bg)
        
        graphic = UIImageView(image: UIImage(named: "sync-art"))
        graphic.translatesAutoresizingMaskIntoConstraints = false
        graphic.contentMode = .Center
        scrollView.addSubview(graphic)
        
        titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFontOfSize(20, weight: UIFontWeightSemibold)
        titleLabel.textColor = UIColor.blackColor()
        titleLabel.text = Strings.BraveSync
        scrollView.addSubview(titleLabel)
        
        descriptionLabel = UILabel()
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.font = UIFont.systemFontOfSize(15, weight: UIFontWeightRegular)
        descriptionLabel.textColor = UIColor(rgb: 0x696969)
        descriptionLabel.numberOfLines = 0
        descriptionLabel.lineBreakMode = .ByWordWrapping
        descriptionLabel.textAlignment = .Center
        descriptionLabel.text = Strings.BraveSyncWelcome
        scrollView.addSubview(descriptionLabel)
        
        newToSyncButton = UIButton(type: .RoundedRect)
        newToSyncButton.translatesAutoresizingMaskIntoConstraints = false
        newToSyncButton.setTitle(Strings.NewSyncCode, forState: .Normal)
        newToSyncButton.titleLabel?.font = UIFont.systemFontOfSize(17, weight: UIFontWeightBold)
        newToSyncButton.setTitleColor(UIColor.whiteColor(), forState: .Normal)
        newToSyncButton.backgroundColor = BraveUX.DefaultBlue
        newToSyncButton.layer.cornerRadius = 8
        newToSyncButton.addTarget(self, action: #selector(SEL_newToSync), forControlEvents: .TouchUpInside)
        scrollView.addSubview(newToSyncButton)
        
        existingUserButton = UIButton(type: .RoundedRect)
        existingUserButton.translatesAutoresizingMaskIntoConstraints = false
        existingUserButton.setTitle(Strings.ScanSyncCode, forState: .Normal)
        existingUserButton.titleLabel?.font = UIFont.systemFontOfSize(15, weight: UIFontWeightSemibold)
        existingUserButton.setTitleColor(UIColor(rgb: 0x696969), forState: .Normal)
        existingUserButton.addTarget(self, action: #selector(SEL_existingUser), forControlEvents: .TouchUpInside)
        scrollView.addSubview(existingUserButton)
        
        let spinner = UIActivityIndicatorView(activityIndicatorStyle: .WhiteLarge)
        spinner.startAnimating()
        loadingView.backgroundColor = UIColor(white: 0.5, alpha: 0.5)
        loadingView.hidden = true
        loadingView.addSubview(spinner)
        view.addSubview(loadingView)
        
        edgesForExtendedLayout = .None
        
        scrollView.snp_makeConstraints { (make) in
            make.edges.equalTo(self.view)
        }
        
        bg.snp_makeConstraints { (make) in
            make.top.equalTo(self.scrollView)
            make.width.equalTo(self.scrollView)
        }
        
        graphic.snp_makeConstraints { (make) in
            make.edges.equalTo(self.bg).inset(UIEdgeInsetsMake(0, 19, 0, 0))
        }
        
        titleLabel.snp_makeConstraints { (make) in
            make.top.equalTo(self.bg.snp_bottom).offset(30)
            make.centerX.equalTo(self.scrollView)
        }
        
        descriptionLabel.snp_makeConstraints { (make) in
            make.top.equalTo(self.titleLabel.snp_bottom).offset(7)
            make.left.equalTo(30)
            make.right.equalTo(-30)
        }
        
        newToSyncButton.snp_makeConstraints { (make) in
            make.top.equalTo(self.descriptionLabel.snp_bottom).offset(30)
            make.centerX.equalTo(self.scrollView)
            make.left.equalTo(16)
            make.right.equalTo(-16)
            make.height.equalTo(50)
        }
        
        existingUserButton.snp_makeConstraints { (make) in
            make.top.equalTo(self.newToSyncButton.snp_bottom).offset(8)
            make.centerX.equalTo(self.scrollView)
            make.bottom.equalTo(-10)
        }
        
        spinner.snp_makeConstraints { (make) in
            make.center.equalTo(spinner.superview!)
        }
        
        loadingView.snp_makeConstraints { (make) in
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
                let view = SyncAddDeviceViewController()
                view.navigationItem.hidesBackButton = true
                navigationController?.pushViewController(view, animated: true)
            } else {
                self.loadingView.hidden = true
                let alert = UIAlertController(title: "Unsuccessful", message: "Unable to create new sync group.", preferredStyle: .Alert)
                alert.addAction(UIAlertAction(title: "ok", style: .Default, handler: nil))
                self.presentViewController(alert, animated: true, completion: nil)
            }
        }
        
        if !Sync.shared.isInSyncGroup {
            NSNotificationCenter.defaultCenter().addObserverForName(NotificationSyncReady, object: nil, queue: NSOperationQueue.mainQueue()) {
                _ in attemptPush()
            }
            
            
            // TODO: Move to strings file
            getDeviceName {
                input in
                
                if let input = input {
                    Sync.shared.initializeNewSyncGroup(deviceName: input)
                }
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
    
    func getDeviceName(callback: String? -> ()) {
        self.loadingView.hidden = false

        // TODO: Move to strings file
        let alert = UIAlertController.userTextInputAlert(title: "Device Name", message: "Please enter a name for this device", startingText: UIDevice.currentDevice().name, forcedInput: false) {
            callback($0)
            self.loadingView.hidden = true
        }
        self.presentViewController(alert, animated: true, completion: nil)
    }
    
}
