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
    
    lazy var codewordsView: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 18.0, weight: UIFontWeightMedium)
        label.textColor = BraveUX.GreyJ
        label.lineBreakMode = NSLineBreakMode.byWordWrapping
        label.numberOfLines = 0
        return label
    }()
    
    lazy var copyPasteButton: UIButton = {
        let button = UIButton()
        button.setImage(UIImage(named: "copy_paste"), for: .normal)
        button.addTarget(self, action: #selector(SEL_copy), for: .touchUpInside)
        button.sizeToFit()
        button.isHidden = true
        return button
    }()
    
    lazy var copiedlabel: UILabel = {
        let label = UILabel()
        label.font = UIFont.systemFont(ofSize: 13)
        label.textColor = BraveUX.GreyE
        label.text = Strings.Copied
        label.isHidden = true
        return label
    }()

    var containerView: UIView!
    var qrCodeView: SyncQRCodeView!
    var modeControl: UISegmentedControl!
    var titleLabel: UILabel!
    var descriptionLabel: UILabel!
    var doneButton: RoundInterfaceButton!
    var enterWordsButton: RoundInterfaceButton!
    var pageTitle: String = Strings.Sync
    var deviceType: DeviceType = .mobile
    var didCopy = false {
        didSet {
            copiedlabel.isHidden = !didCopy
        }
    }
    
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

            self.qrCodeView = SyncQRCodeView(data: qrSyncSeed)
            self.codewordsView.text = words.joined(separator: " ")
            self.setupVisuals()
        }
    }
    
    func setupVisuals() {
        containerView.addSubview(qrCodeView)
        containerView.addSubview(copyPasteButton)
        containerView.addSubview(copiedlabel)

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
        titleDescriptionStackView.addArrangedSubview(titleLabel)

        descriptionLabel = UILabel()
        descriptionLabel.font = UIFont.systemFont(ofSize: 15, weight: UIFontWeightRegular)
        descriptionLabel.textColor = BraveUX.GreyH
        descriptionLabel.numberOfLines = 0
        descriptionLabel.lineBreakMode = .byTruncatingTail
        descriptionLabel.textAlignment = .center
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

        qrCodeView.snp.makeConstraints { (make) in
            make.top.equalTo(modeControl.snp.bottom).offset(16)
            make.centerX.equalTo(self.containerView)
            make.size.equalTo(BarcodeSize)
        }

        codewordsView.snp.makeConstraints { (make) in
            make.top.equalTo(modeControl.snp.bottom).offset(22)
            make.left.right.equalTo(self.containerView).inset(22)
        }
        
        copyPasteButton.snp.makeConstraints { (make) in
            make.bottom.right.equalTo(containerView).inset(24)
        }
        
        copiedlabel.snp.makeConstraints { (make) in
            make.right.equalTo(copyPasteButton.snp.left).offset(-8)
            make.centerY.equalTo(copyPasteButton)
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
        
        updateLabels()
    }
    
    func updateLabels() {
        let isFirstIndex = modeControl.selectedSegmentIndex == 0
        
        titleLabel.text = isFirstIndex ? Strings.SyncAddDeviceScan : Strings.SyncAddDeviceWords
        
        if deviceType == .mobile {
            descriptionLabel.text = isFirstIndex ? Strings.SyncAddMobileScanDescription : Strings.SyncAddMobileWordsDescription
        }
        else if deviceType == .computer {
            descriptionLabel.text = isFirstIndex ? Strings.SyncAddComputerScanDescription : Strings.SyncAddComputerWordsDescription
        }
    }
    
    func SEL_showCodewords() {
        modeControl.selectedSegmentIndex = 1
        enterWordsButton.isHidden = true
        SEL_changeMode()
    }
    
    func SEL_copy() {
        UIPasteboard.general.string = self.codewordsView.text
        didCopy = true
    }
    
    func SEL_changeMode() {
        let isFirstIndex = modeControl.selectedSegmentIndex == 0
        
        qrCodeView.isHidden = !isFirstIndex
        codewordsView.isHidden = isFirstIndex
        copyPasteButton.isHidden = isFirstIndex
        
        if copyPasteButton.isHidden {
            copiedlabel.isHidden = true
        }
        
        updateLabels()
    }
    
    func SEL_done() {
        // At this point we're not sure if we started from welcome screen or sync settings vc
        // SyncSettings may not be on the stack. Alternatively, chaining back to BraveSettings through
        // references adds significantly more complexity and some loss of context clarity.
        // The drawback is that this check is needed in two places. Durring add and after joining existing chain.
        
        if let syncSettingsView = navigationController?.viewControllers.first(where: { $0.isKind(of: SyncSettingsViewController.self) }) {
            navigationController?.popToViewController(syncSettingsView, animated: true)
        } else {
            let syncSettingsView = SyncSettingsViewController(style: .grouped)
            syncSettingsView.profile = getApp().profile
            syncSettingsView.disableBackButton = true
            navigationController?.pushViewController(syncSettingsView, animated: true)
        }
    }
}

