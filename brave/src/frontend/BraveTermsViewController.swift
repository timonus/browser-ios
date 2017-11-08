/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Foundation

protocol BraveTermsViewControllerDelegate {
    func braveTermsAcceptedTermsAndOptIn() -> Void
    func braveTermsAcceptedTermsAndOptOut() -> Void
    func dismissed()
}

class BraveTermsViewController: UIViewController {
    
    var delegate: BraveTermsViewControllerDelegate?
    
    fileprivate var braveLogo: UIImageView!
    fileprivate var termsLabel: UITextView!
    fileprivate var optLabel: UILabel!
    fileprivate var checkButton: UIButton!
    fileprivate var continueButton: UIButton!
    
    override func loadView() {
        super.loadView()
        
        braveLogo = UIImageView(image: UIImage(named: "braveLogoLarge"))
        braveLogo.contentMode = .center
        view.addSubview(braveLogo)
        
        termsLabel = UITextView()
        termsLabel.backgroundColor = UIColor.clear
        termsLabel.isScrollEnabled = false
        termsLabel.isSelectable = true
        termsLabel.isEditable = false
        termsLabel.dataDetectorTypes = [.all]
        
        let attributedString = NSMutableAttributedString(string: NSLocalizedString("By using this application, you agree to Brave’s Terms of Use.", comment: ""))
        let linkRange = (attributedString.string as NSString).range(of: NSLocalizedString("Terms of Use.", comment: ""))
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        
        let fontAttributes = [
            NSForegroundColorAttributeName: UIColor.white,
            NSFontAttributeName: UIFont.systemFont(ofSize: 18.0, weight: UIFontWeightMedium),
            NSParagraphStyleAttributeName: paragraphStyle ]
        
        attributedString.addAttributes(fontAttributes, range: NSMakeRange(0, (attributedString.string.characters.count - 1)))
        attributedString.addAttribute(NSLinkAttributeName, value: "https://brave.com/terms_of_use.html", range: linkRange)
        
        let linkAttributes = [
            NSForegroundColorAttributeName: UIColor(red: 255/255.0, green: 80/255.0, blue: 0/255.0, alpha: 1.0) ]
        
        termsLabel.linkTextAttributes = linkAttributes
        termsLabel.attributedText = attributedString
        termsLabel.delegate = self
        view.addSubview(termsLabel)
        
        optLabel = UILabel()
        optLabel.text = NSLocalizedString("Help make Brave better by sending usage statistics and crash reports to us.", comment: "")
        optLabel.font = UIFont.systemFont(ofSize: 18.0, weight: UIFontWeightMedium)
        optLabel.textColor = UIColor(white: 1.0, alpha: 0.5)
        optLabel.numberOfLines = 0
        optLabel.lineBreakMode = .byWordWrapping
        view.addSubview(optLabel)
        
        checkButton = UIButton(type: .custom)
        checkButton.setImage(UIImage(named: "sharedata_uncheck"), for: .normal)
        checkButton.setImage(UIImage(named: "sharedata_check"), for: .selected)
        checkButton.addTarget(self, action: #selector(checkUncheck(_:)), for: .touchUpInside)
        checkButton.isSelected = true
        view.addSubview(checkButton)
        
        continueButton = UIButton(type: .system)
        continueButton.titleLabel?.font = UIFont.systemFont(ofSize: 18.0, weight: UIFontWeightMedium)
        continueButton.setTitle(NSLocalizedString("Accept & Continue", comment: ""), for: .normal)
        continueButton.setTitleColor(UIColor.white, for: .normal)
        continueButton.addTarget(self, action: #selector(acceptAndContinue(_:)), for: .touchUpInside)
        continueButton.backgroundColor = UIColor(red: 255/255.0, green: 80/255.0, blue: 0/255.0, alpha: 1.0)
        continueButton.layer.cornerRadius = 4.5
        continueButton.layer.masksToBounds = true
        view.addSubview(continueButton)
        
        continueButton.snp.makeConstraints { (make) in
            make.centerX.equalTo(self.view)
            make.bottom.equalTo(self.view).offset(-30)
            make.height.equalTo(40)
            
            let width = self.continueButton.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).width
            make.width.equalTo(width + 40)
        }
        
        optLabel.snp.makeConstraints { (make) in
            make.centerX.equalTo(self.view).offset(36/2)
            
            let width = min(UIScreen.main.bounds.width * 0.65, 350)
            make.width.equalTo(width)
            
            if UIDevice.current.userInterfaceIdiom == .pad {
                make.bottom.equalTo(continueButton.snp.top).offset(-60).priorityHigh()
            }
            else {
                make.bottom.lessThanOrEqualTo(continueButton.snp.top).offset(-60).priorityHigh()
            }
        }
        
        checkButton.snp.makeConstraints { (make) in
            make.left.equalTo(optLabel.snp.left).offset(-36)
            make.top.equalTo(optLabel.snp.top).offset(4).priorityHigh()
        }
        
        termsLabel.snp.makeConstraints { (make) in
            make.centerX.equalTo(self.view)
            
            let width = min(UIScreen.main.bounds.width * 0.70, 350)
            make.width.equalTo(width)
            make.bottom.equalTo(optLabel.snp.top).offset(-35).priorityMedium()
        }
        
        braveLogo.snp.makeConstraints { (make) in
            make.centerX.equalTo(self.view)
            make.top.equalTo(10)
            
            if UIDevice.current.userInterfaceIdiom == .pad {
                make.bottom.equalTo(termsLabel.snp.top)
            }
            else {
                make.height.equalTo(UIScreen.main.bounds.width > UIScreen.main.bounds.height ? UIScreen.main.bounds.height : UIScreen.main.bounds.width)
            }
        }
        
        view.backgroundColor = UIColor(red: 63/255.0, green: 63/255.0, blue: 63/255.0, alpha: 1.0)
    }

//    override var prefersStatusBarHidden : Bool {
//        return true
//    }
    
    override func willRotate(to toInterfaceOrientation: UIInterfaceOrientation, duration: TimeInterval) {
        
        if UIDevice.current.userInterfaceIdiom == .pad {
            return
        }
        
        if toInterfaceOrientation == .landscapeLeft || toInterfaceOrientation == .landscapeRight {
            UIView.animate(withDuration: 0.2, animations: { 
                self.braveLogo.alpha = 0.15
            })
        }
        else {
            UIView.animate(withDuration: 0.2, animations: {
                self.braveLogo.alpha = 1.0
            })
        }
        
        self.view.setNeedsUpdateConstraints()
    }
    
    // MARK: Actions
    
    func checkUncheck(_ sender: UIButton) {
        sender.isSelected = !sender.isSelected
    }
    
    func acceptAndContinue(_ sender: UIButton) {
        if checkButton.isSelected {
            delegate?.braveTermsAcceptedTermsAndOptIn()
        }
        else {
            delegate?.braveTermsAcceptedTermsAndOptOut()
        }
        dismiss(animated: false, completion: nil)
    }

    override func dismiss(animated flag: Bool, completion: (() -> Void)?) {
        super.dismiss(animated: flag, completion: completion)
        delegate?.dismissed()
    }
}

extension BraveTermsViewController: UITextViewDelegate {
    func textView(_ textView: UITextView, shouldInteractWith URL: URL, in characterRange: NSRange) -> Bool {
        return true
    }
}
