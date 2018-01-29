/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

enum DeviceType {
    case mobile
    case computer
}

class SyncAddDeviceViewController: SyncViewController {

    lazy var stackView: UIStackView = {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.distribution = .equalSpacing
        stack.spacing = 4
        return stack
    }()

    var containerView: UIView!
    var barcodeView: SyncBarcodeView!
    var codewordsView: SyncCodewordList!
    var modeControl: UISegmentedControl!
    var titleLabel: UILabel!
    var descriptionLabel: UILabel!
    var doneButton: RoundInterfaceButton!
    var enterWordsButton: RoundInterfaceButton!
    var pageTitle: String = Strings.Sync
    var deviceType: DeviceType = .mobile
    
    convenience init(title: String, type: DeviceType) {
        self.init()
        pageTitle = title
        deviceType = type
    }
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = pageTitle

        view.addSubview(stackView)
        stackView.snp.makeConstraints { make in
            make.top.equalTo(self.topLayoutGuide.snp.bottom)
            make.left.right.equalTo(self.view)
            make.bottom.equalTo(self.view.safeArea.bottom).inset(24)
        }

        containerView = UIView()
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = UIColor.white
        containerView.layer.shadowColor = UIColor(rgb: 0xC8C7CC).cgColor
        containerView.layer.shadowRadius = 0
        containerView.layer.shadowOpacity = 1.0
        containerView.layer.shadowOffset = CGSize(width: 0, height: 0.5)

        guard let syncSeed = Sync.shared.syncSeedArray else {
            // TODO: Pop and error
            return
        }

        let qrSyncSeed = Niceware.shared.joinBytes(fromCombinedBytes: syncSeed)
        if qrSyncSeed.isEmpty {
            // Error
            return
        }

        Niceware.shared.passphrase(fromBytes: syncSeed) { (words, error) in
            guard let words = words, error == nil else {
                return
            }

            self.barcodeView = SyncBarcodeView(data: qrSyncSeed)
            self.codewordsView = SyncCodewordList(words: words)
            self.setupVisuals()
        }
    }
    
    func setupVisuals() {
        containerView.addSubview(barcodeView)

        codewordsView.isHidden = true
        containerView.addSubview(codewordsView)

        modeControl = UISegmentedControl(items: [Strings.QRCode, Strings.CodeWords])
        modeControl.translatesAutoresizingMaskIntoConstraints = false
        modeControl.tintColor = BraveUX.BraveOrange
        modeControl.selectedSegmentIndex = 0
        modeControl.addTarget(self, action: #selector(SEL_changeMode), for: .valueChanged)

        containerView.addSubview(modeControl)
        stackView.addArrangedSubview(containerView)

        let titleDescriptionStackView = UIStackView()
        titleDescriptionStackView.axis = .vertical
        titleDescriptionStackView.spacing = 4
        titleDescriptionStackView.alignment = .center
        
        titleLabel = UILabel()
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = UIFont.systemFont(ofSize: 20, weight: UIFontWeightSemibold)
        titleLabel.textColor = BraveUX.GreyJ
        titleLabel.text = deviceType == .mobile ? Strings.SyncAddMobile : Strings.SyncAddComputer
        titleDescriptionStackView.addArrangedSubview(titleLabel)

        descriptionLabel = UILabel()
        descriptionLabel.font = UIFont.systemFont(ofSize: 15, weight: UIFontWeightRegular)
        descriptionLabel.textColor = BraveUX.GreyH
        descriptionLabel.numberOfLines = 0
        descriptionLabel.lineBreakMode = .byTruncatingTail
        descriptionLabel.textAlignment = .center
        descriptionLabel.text = deviceType == .mobile ? Strings.SyncAddMobileDescription : Strings.SyncAddComputerDescription
        descriptionLabel.adjustsFontSizeToFitWidth = true
        descriptionLabel.minimumScaleFactor = 0.5
        titleDescriptionStackView.addArrangedSubview(descriptionLabel)

        let textStackView = UIStackView(arrangedSubviews: [UIView.spacer(.horizontal, amount: 32),
                                                           titleDescriptionStackView,
                                                           UIView.spacer(.horizontal, amount: 32)])
        textStackView.setContentCompressionResistancePriority(100, for: .vertical)

        stackView.addArrangedSubview(textStackView)

        let doneEnterWordsStackView = UIStackView()
        doneEnterWordsStackView.axis = .vertical
        doneEnterWordsStackView.spacing = 4

        doneButton = RoundInterfaceButton(type: .roundedRect)
        doneButton.translatesAutoresizingMaskIntoConstraints = false
        doneButton.setTitle(Strings.Done, for: .normal)
        doneButton.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: UIFontWeightBold)
        doneButton.setTitleColor(UIColor.white, for: .normal)
        doneButton.backgroundColor = BraveUX.Blue
        doneButton.addTarget(self, action: #selector(SEL_done), for: .touchUpInside)

        doneEnterWordsStackView.addArrangedSubview(doneButton)

        enterWordsButton = RoundInterfaceButton(type: .roundedRect)
        enterWordsButton.translatesAutoresizingMaskIntoConstraints = false
        enterWordsButton.setTitle(Strings.ShowCodeWords, for: .normal)
        enterWordsButton.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: UIFontWeightSemibold)
        enterWordsButton.setTitleColor(BraveUX.GreyH, for: .normal)
        enterWordsButton.addTarget(self, action: #selector(SEL_showCodewords), for: .touchUpInside)

        let buttonsStackView = UIStackView(arrangedSubviews: [UIView.spacer(.horizontal, amount: 16),
                                                              doneEnterWordsStackView,
                                                              UIView.spacer(.horizontal, amount: 16)])
        buttonsStackView.setContentCompressionResistancePriority(1000, for: .vertical)


        stackView.addArrangedSubview(buttonsStackView)

        containerView.snp.makeConstraints { (make) in
            make.height.equalTo(270)
        }

        modeControl.snp.makeConstraints { (make) in
            make.top.equalTo(self.containerView.snp.top).offset(10)
            make.left.equalTo(8)
            make.right.equalTo(-8)
        }

        barcodeView.snp.makeConstraints { (make) in
            make.top.equalTo(modeControl.snp.bottom).offset(16)
            make.centerX.equalTo(self.containerView)
            make.size.equalTo(BarcodeSize)
        }

        codewordsView.snp.makeConstraints { (make) in
            make.top.equalTo(modeControl.snp.bottom).offset(16)
            make.left.right.bottom.equalTo(self.containerView).inset(16)
        }

        doneButton.snp.makeConstraints { (make) in
            make.height.equalTo(40)
        }

        enterWordsButton.snp.makeConstraints { (make) in
            make.height.equalTo(20)
        }

        if deviceType == .computer {
            SEL_showCodewords()
        }
    }
    
    func SEL_showCodewords() {
        modeControl.selectedSegmentIndex = 1
        enterWordsButton.isHidden = true
        SEL_changeMode()
    }
    
    func SEL_changeMode() {
        barcodeView.isHidden = (modeControl.selectedSegmentIndex == 1)
        codewordsView.isHidden = (modeControl.selectedSegmentIndex == 0)
    }
    
    func SEL_done() {
        // Re-activate pop gesture in case it was removed
        navigationController?.interactivePopGestureRecognizer?.isEnabled = true
        
        self.navigationController?.popToRootViewController(animated: true)
    }
}

