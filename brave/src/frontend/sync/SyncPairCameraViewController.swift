/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

class SyncPairCameraViewController: UIViewController {
    
    var scrollView: UIScrollView!
    var cameraView: SyncCameraView!
    var titleLabel: UILabel!
    var descriptionLabel: UILabel!
    var cameraAccessButton: UIButton!
    var enterWordsButton: UIButton!
    
    // Kind of an odd mechanism for passing this info
    var deviceName: String?
    
    private let prefs: Prefs = getApp().profile!.prefs
    private let prefKey: String = "CameraPermissionsSetting"
    
    var loadingView: UIView!
    let loadingSpinner = UIActivityIndicatorView(activityIndicatorStyle: .WhiteLarge)
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = Strings.Pair
        view.backgroundColor = SyncBackgroundColor
        
        // Start observing, this will handle child vc popping too for successful sync (e.g. pair words)
        NSNotificationCenter.defaultCenter().addObserverForName(NotificationSyncReady, object: nil, queue: NSOperationQueue.mainQueue(), usingBlock: {
            notification in
            self.navigationController?.popToRootViewControllerAnimated(true)
        })
        
        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        cameraView = SyncCameraView()
        cameraView.translatesAutoresizingMaskIntoConstraints = false
        cameraView.backgroundColor = UIColor.blackColor()
        cameraView.layer.cornerRadius = 4
        cameraView.layer.masksToBounds = true
        cameraView.scanCallback = { data in
            
            
            // TODO: Check data against sync api

            // TODO: Functional, but needs some cleanup
            struct Scanner { static var Lock = false }
            if let bytes = Niceware.shared.splitBytes(fromJoinedBytes: data) {
                if (Scanner.Lock) {
                    // Have internal, so camera error does not show
                    return
                }
                
                Scanner.Lock = true
                self.cameraView.cameraOverlaySucess()
                
                // Will be removed on pop
                self.loadingView.hidden = false
                
                // Forced timeout
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(25.0) * Int64(NSEC_PER_SEC)), dispatch_get_main_queue(), {
                    Scanner.Lock = false
                    self.loadingView.hidden = true
                    self.cameraView.cameraOverlayError()
                })
                
                // If multiple calls get in here due to race conditions it isn't a big deal
                
                Sync.shared.initializeSync(bytes, deviceName: self.deviceName)

            } else {
                self.cameraView.cameraOverlayError()
            }
        }
        
        cameraView.authorizedCallback = { authorized in
            if authorized {
                postAsyncToMain(0) {
                    self.cameraAccessButton.hidden = true
                    self.prefs.setBool(true, forKey: self.prefKey)
                }
            }
            else {
                // TODO: Show alert.
            }
        }
        scrollView.addSubview(cameraView)
        
        titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFontOfSize(20, weight: UIFontWeightSemibold)
        titleLabel.textColor = UIColor.blackColor()
        titleLabel.text = Strings.SyncToDevice
        scrollView.addSubview(titleLabel)
        
        descriptionLabel = UILabel()
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.font = UIFont.systemFontOfSize(15, weight: UIFontWeightRegular)
        descriptionLabel.textColor = UIColor(rgb: 0x696969)
        descriptionLabel.numberOfLines = 0
        descriptionLabel.lineBreakMode = .ByWordWrapping
        descriptionLabel.textAlignment = .Center
        descriptionLabel.text = Strings.SyncToDeviceDescription
        scrollView.addSubview(descriptionLabel)
        
        cameraAccessButton = UIButton(type: .RoundedRect)
        cameraAccessButton.translatesAutoresizingMaskIntoConstraints = false
        cameraAccessButton.setTitle(Strings.GrantCameraAccess, forState: .Normal)
        cameraAccessButton.titleLabel?.font = UIFont.systemFontOfSize(17, weight: UIFontWeightBold)
        cameraAccessButton.setTitleColor(UIColor.whiteColor(), forState: .Normal)
        cameraAccessButton.backgroundColor = BraveUX.DefaultBlue
        cameraAccessButton.layer.cornerRadius = 8
        cameraAccessButton.addTarget(self, action: #selector(SEL_cameraAccess), forControlEvents: .TouchUpInside)
        scrollView.addSubview(cameraAccessButton)
        
        enterWordsButton = UIButton(type: .RoundedRect)
        enterWordsButton.translatesAutoresizingMaskIntoConstraints = false
        enterWordsButton.setTitle(Strings.EnterCodeWords, forState: .Normal)
        enterWordsButton.titleLabel?.font = UIFont.systemFontOfSize(15, weight: UIFontWeightSemibold)
        enterWordsButton.setTitleColor(UIColor(rgb: 0x696969), forState: .Normal)
        enterWordsButton.addTarget(self, action: #selector(SEL_enterWords), forControlEvents: .TouchUpInside)
        scrollView.addSubview(enterWordsButton)
        
        loadingSpinner.startAnimating()
        
        loadingView = UIView()
        loadingView.translatesAutoresizingMaskIntoConstraints = false
        loadingView.backgroundColor = UIColor(white: 0.5, alpha: 0.5)
        loadingView.hidden = true
        loadingView.addSubview(loadingSpinner)
        scrollView.addSubview(loadingView)
        
        edgesForExtendedLayout = .None
        
        scrollView.snp_makeConstraints { (make) in
            make.edges.equalTo(self.view)
        }
        
        cameraView.snp_makeConstraints { (make) in
            make.top.equalTo(self.scrollView).offset(24)
            make.size.equalTo(300)
            make.centerX.equalTo(self.scrollView)
        }
        
        titleLabel.snp_makeConstraints { (make) in
            make.top.equalTo(self.cameraView.snp_bottom).offset(30)
            make.centerX.equalTo(self.scrollView)
        }
        
        descriptionLabel.snp_makeConstraints { (make) in
            make.top.equalTo(self.titleLabel.snp_bottom).offset(7)
            make.leftMargin.equalTo(30)
            make.rightMargin.equalTo(-30)
        }
        
        cameraAccessButton.snp_makeConstraints { (make) in
            make.top.equalTo(self.descriptionLabel.snp_bottom).offset(30)
            make.centerX.equalTo(self.scrollView)
            make.left.equalTo(16)
            make.right.equalTo(-16)
            make.height.equalTo(50)
        }
        
        enterWordsButton.snp_makeConstraints { (make) in
            make.top.equalTo(self.cameraAccessButton.snp_bottom).offset(8)
            make.centerX.equalTo(self.scrollView)
            make.bottom.equalTo(-10)
        }
        
        loadingView.snp_makeConstraints { make in
            make.margins.equalTo(cameraView.snp_margins)
        }
        
        loadingSpinner.snp_makeConstraints { make in
            make.center.equalTo(loadingSpinner.superview!)
        }
        
        if prefs.boolForKey(prefKey) == true {
            cameraView.startCapture()
        }
    }
    
    func SEL_cameraAccess() {
        // TODO: check if already has access before requiring button tap.
        cameraView.startCapture()
    }
    
    func SEL_enterWords() {
        navigationController?.pushViewController(SyncPairWordsViewController(), animated: true)
    }
}

