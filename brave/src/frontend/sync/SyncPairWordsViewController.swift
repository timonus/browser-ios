/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

class SyncPairWordsViewController: UIViewController {
    
    var scrollView: UIScrollView!
    var containerView: UIView!
    var helpLabel: UILabel!
    var codewordsView: SyncCodewordsView!
    
    // Kind of an odd mechanism for passing this info
    var deviceName: String?
    
    var loadingView: UIView!
    let loadingSpinner = UIActivityIndicatorView(activityIndicatorStyle: .whiteLarge)
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = Strings.Pair
        view.backgroundColor = SyncBackgroundColor
        
        scrollView = UIScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        
        containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = UIColor.white
        containerView.layer.shadowColor = UIColor(rgb: 0xC8C7CC).cgColor
        containerView.layer.shadowRadius = 0
        containerView.layer.shadowOpacity = 1.0
        containerView.layer.shadowOffset = CGSize(width: 0, height: 0.5)
        scrollView.addSubview(containerView)
        
        codewordsView = SyncCodewordsView(data: [])
        codewordsView.doneKeyCallback = {
            self.checkCodes()
        }
        containerView.addSubview(codewordsView)
        
        helpLabel = UILabel()
        helpLabel.translatesAutoresizingMaskIntoConstraints = false
        helpLabel.font = UIFont.systemFont(ofSize: 15, weight: UIFontWeightRegular)
        helpLabel.textColor = UIColor(rgb: 0x696969)
        helpLabel.text = Strings.EnterCodeWordsBelow
        scrollView.addSubview(helpLabel)
        
        loadingSpinner.startAnimating()
        
        loadingView = UIView()
        loadingView.backgroundColor = UIColor(white: 0.5, alpha: 0.5)
        loadingView.isHidden = true
        loadingView.addSubview(loadingSpinner)
        view.addSubview(loadingView)
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(SEL_done))
        
        edgesForExtendedLayout = UIRectEdge()
        
        scrollView.snp.makeConstraints { (make) in
            make.edges.equalTo(self.view)
        }
        
        containerView.snp.makeConstraints { (make) in
            // Making these edges based off of the scrollview removes selectability on codewords.
            //  This currently works for all layouts and enables interaction, so using `view` instead.
            make.top.equalTo(self.view)
            make.left.equalTo(self.view)
            make.right.equalTo(self.view)
            make.height.equalTo(295)
            make.width.equalTo(self.view)
        }
        
        helpLabel.snp.makeConstraints { (make) in
            make.top.equalTo(self.containerView.snp.top).offset(10)
            make.centerX.equalTo(self.scrollView)
        }
        
        codewordsView.snp.makeConstraints { (make) in
            make.edges.equalTo(self.containerView).inset(UIEdgeInsetsMake(44, 0, 0, 0))
        }
        
        loadingView.snp.makeConstraints { (make) in
            make.edges.equalTo(loadingView.superview!)
        }
        
        loadingSpinner.snp.makeConstraints { (make) in
            make.center.equalTo(loadingView)
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Focus on first input field.
        codewordsView.fields[0].becomeFirstResponder()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
    }
    
    func SEL_done() {
        checkCodes()
    }
    
    func checkCodes() {
        debugPrint("check codes")
        
        func alert(title: String? = nil, message: String? = nil) {
            if Sync.shared.isInSyncGroup {
                // No alert
                return
            }
            let title = title ?? "Unable to Connect"
            let message = message ?? "Unable to join sync group. Please check the entered words and try again."
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "ok", style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
        
        func loading(_ isLoading: Bool = true) {
            self.loadingView.isHidden = !isLoading
            navigationItem.rightBarButtonItem?.isEnabled = !isLoading
        }
        
        let codes = self.codewordsView.codeWords()

        // Maybe temporary validation, sync server has issues without this validation
        if codes.count < Sync.SeedByteLength / 2 {
            alert(title: "Not Enough Words", message: "Please enter all of the words and try again.")
            return
        }
        
        self.view.endEditing(true)
        loading()
        
        // forced timeout
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + Double(Int64(25.0) * Int64(NSEC_PER_SEC)) / Double(NSEC_PER_SEC), execute: {
            loading(false)
            alert()
        })
        
        Niceware.shared.bytes(fromPassphrase: codes) { (result, error) in
            if result?.count == 0 || error != nil {
                var errorText = error?.userInfo["WKJavaScriptExceptionMessage"] as? String
                if let er = errorText, er.contains("Invalid word") {
                    errorText = er + "\n Please recheck spelling"
                }
                
                alert(message: errorText)
                loading(false)
                return
            }
            
            // Block Sync
            // Sync.shared.initializeSync(seed: result)
        }
    }
}
