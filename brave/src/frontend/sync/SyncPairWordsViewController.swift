/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

class SyncPairWordsViewController: SyncViewController {
    
    var scrollView: UIScrollView!
    var containerView: UIView!
    var codewordsView: SyncCodewordsView!
    
    lazy var wordCountLabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13, weight: UIFontWeightRegular)
        label.textColor = BraveUX.GreyE
        label.text = String(format: Strings.WordCount, 0)
        return label
    }()
    
    lazy var copyPasteButton: UIButton = {
        let button = UIButton()
        button.setImage(UIImage(named: "copy_paste"), for: .normal)
        button.addTarget(self, action: #selector(SEL_paste), for: .touchUpInside)
        button.sizeToFit()
        return button
    }()
    
    var useCameraButton: RoundInterfaceButton!
    
    var loadingView: UIView!
    let loadingSpinner = UIActivityIndicatorView(activityIndicatorStyle: .whiteLarge)
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = Strings.SyncAddDeviceWords
        
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
        codewordsView.wordCountChangeCallback = { (count) in
            self.wordCountLabel.text = String(format: Strings.WordCount, count)
        }
        containerView.addSubview(codewordsView)
        containerView.addSubview(wordCountLabel)
        containerView.addSubview(copyPasteButton)
        
        useCameraButton = RoundInterfaceButton(type: .roundedRect)
        useCameraButton.translatesAutoresizingMaskIntoConstraints = false
        useCameraButton.setTitle(Strings.UseCameraButton, for: .normal)
        useCameraButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: UIFontWeightSemibold)
        useCameraButton.setTitleColor(BraveUX.GreyH, for: .normal)
        useCameraButton.addTarget(self, action: #selector(SEL_camera), for: .touchUpInside)
        view.addSubview(useCameraButton)
        
        loadingSpinner.startAnimating()
        
        loadingView = UIView()
        loadingView.backgroundColor = UIColor(white: 0.5, alpha: 0.5)
        loadingView.isHidden = true
        loadingView.addSubview(loadingSpinner)
        view.addSubview(loadingView)
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(title: Strings.Confirm, style: .done, target: self, action: #selector(SEL_done))
        
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
        
        codewordsView.snp.makeConstraints { (make) in
            make.edges.equalTo(self.containerView).inset(UIEdgeInsetsMake(0, 0, 45, 0))
        }
        
        wordCountLabel.snp.makeConstraints { (make) in
            make.top.equalTo(codewordsView.snp.bottom)
            make.left.equalTo(codewordsView).inset(24)
        }
        
        copyPasteButton.snp.makeConstraints { (make) in
            make.top.equalTo(codewordsView.snp.bottom)
            make.right.equalTo(codewordsView).inset(24)
        }
        
        useCameraButton.snp.makeConstraints { (make) in
            make.top.equalTo(containerView.snp.bottom).offset(20)
            make.centerX.equalTo(view)
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
        
        codewordsView.becomeFirstResponder()
    }
    
    func SEL_paste() {
        if let contents = UIPasteboard.general.string {
            // remove linebreaks and whitespace, split into codewords.
            codewordsView.setCodewords(data: contents.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: " "))
        }
    }
    
    func SEL_camera() {
        navigationController?.popViewController(animated: true)
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
            let title = title ?? Strings.UnableToConnectTitle
            let message = message ?? Strings.UnableToConnectDescription
            let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: Strings.OK, style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
        
        func loading(_ isLoading: Bool = true) {
            self.loadingView.isHidden = !isLoading
            navigationItem.rightBarButtonItem?.isEnabled = !isLoading
        }
        
        let codes = self.codewordsView.codeWords()

        // Maybe temporary validation, sync server has issues without this validation
        if codes.count < Sync.SeedByteLength / 2 {
            alert(title: Strings.NotEnoughWordsTitle, message: Strings.NotEnoughWordsDescription)
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
            
            Sync.shared.initializeSync(seed: result)
        }
    }
}
