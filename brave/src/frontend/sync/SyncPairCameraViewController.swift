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
    
    fileprivate let prefs: Prefs = getApp().profile!.prefs
    fileprivate let prefKey: String = "CameraPermissionsSetting"
    
    var loadingView: UIView!
    let loadingSpinner = UIActivityIndicatorView(activityIndicatorStyle: .whiteLarge)
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = Strings.Pair
        view.backgroundColor = SyncBackgroundColor
        
        // Start observing, this will handle child vc popping too for successful sync (e.g. pair words)
        NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: NotificationSyncReady), object: nil, queue: OperationQueue.main, using: {
            notification in
            self.navigationController?.popToRootViewController(animated: true)
        })
        
        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        cameraView = SyncCameraView()
        cameraView.translatesAutoresizingMaskIntoConstraints = false
        cameraView.backgroundColor = UIColor.black
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
                self.loadingView.isHidden = false
                
                // Forced timeout
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(25.0) * Int64(NSEC_PER_SEC)) / Double(NSEC_PER_SEC), execute: {
                    Scanner.Lock = false
                    self.loadingView.isHidden = true
                    self.cameraView.cameraOverlayError()
                })
                
                // If multiple calls get in here due to race conditions it isn't a big deal
                
                // Block Sync
                // Sync.shared.initializeSync(seed: bytes, deviceName: self.deviceName)

            } else {
                self.cameraView.cameraOverlayError()
            }
        }
        
        cameraView.authorizedCallback = { authorized in
            if authorized {
                postAsyncToMain(0) {
                    self.cameraAccessButton.isHidden = true
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
        titleLabel.font = UIFont.systemFont(ofSize: 20, weight: UIFontWeightSemibold)
        titleLabel.textColor = UIColor.black
        titleLabel.text = Strings.SyncToDevice
        scrollView.addSubview(titleLabel)
        
        descriptionLabel = UILabel()
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
        descriptionLabel.font = UIFont.systemFont(ofSize: 15, weight: UIFontWeightRegular)
        descriptionLabel.textColor = UIColor(rgb: 0x696969)
        descriptionLabel.numberOfLines = 0
        descriptionLabel.lineBreakMode = .byWordWrapping
        descriptionLabel.textAlignment = .center
        descriptionLabel.text = Strings.SyncToDeviceDescription
        scrollView.addSubview(descriptionLabel)
        
        cameraAccessButton = UIButton(type: .roundedRect)
        cameraAccessButton.translatesAutoresizingMaskIntoConstraints = false
        cameraAccessButton.setTitle(Strings.GrantCameraAccess, for: .normal)
        cameraAccessButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: UIFontWeightBold)
        cameraAccessButton.setTitleColor(UIColor.white, for: .normal)
        cameraAccessButton.backgroundColor = BraveUX.DefaultBlue
        cameraAccessButton.layer.cornerRadius = 8
        cameraAccessButton.addTarget(self, action: #selector(SEL_cameraAccess), for: .touchUpInside)
        scrollView.addSubview(cameraAccessButton)
        
        enterWordsButton = UIButton(type: .roundedRect)
        enterWordsButton.translatesAutoresizingMaskIntoConstraints = false
        enterWordsButton.setTitle(Strings.EnterCodeWords, for: .normal)
        enterWordsButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: UIFontWeightSemibold)
        enterWordsButton.setTitleColor(UIColor(rgb: 0x696969), for: .normal)
        enterWordsButton.addTarget(self, action: #selector(SEL_enterWords), for: .touchUpInside)
        scrollView.addSubview(enterWordsButton)
        
        loadingSpinner.startAnimating()
        
        loadingView = UIView()
        loadingView.translatesAutoresizingMaskIntoConstraints = false
        loadingView.backgroundColor = UIColor(white: 0.5, alpha: 0.5)
        loadingView.isHidden = true
        loadingView.addSubview(loadingSpinner)
        scrollView.addSubview(loadingView)
        
        edgesForExtendedLayout = UIRectEdge()
        
        scrollView.snp.makeConstraints { (make) in
            make.edges.equalTo(self.view)
        }
        
        cameraView.snp.makeConstraints { (make) in
            make.top.equalTo(self.scrollView).offset(24)
            make.size.equalTo(300)
            make.centerX.equalTo(self.scrollView)
        }
        
        titleLabel.snp.makeConstraints { (make) in
            make.top.equalTo(self.cameraView.snp.bottom).offset(30)
            make.centerX.equalTo(self.scrollView)
        }
        
        descriptionLabel.snp.makeConstraints { (make) in
            make.top.equalTo(self.titleLabel.snp.bottom).offset(7)
            make.leftMargin.equalTo(30)
            make.rightMargin.equalTo(-30)
        }
        
        cameraAccessButton.snp.makeConstraints { (make) in
            make.top.equalTo(self.descriptionLabel.snp.bottom).offset(30)
            make.centerX.equalTo(self.scrollView)
            make.left.equalTo(16)
            make.right.equalTo(-16)
            make.height.equalTo(50)
        }
        
        enterWordsButton.snp.makeConstraints { (make) in
            make.top.equalTo(self.cameraAccessButton.snp.bottom).offset(8)
            make.centerX.equalTo(self.scrollView)
            make.bottom.equalTo(-10)
        }
        
        loadingView.snp.makeConstraints { make in
            make.margins.equalTo(cameraView.snp.margins)
        }
        
        loadingSpinner.snp.makeConstraints { make in
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
        let pairWords = SyncPairWordsViewController()
        pairWords.deviceName = self.deviceName
        navigationController?.pushViewController(pairWords, animated: true)
    }
}

