/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

class SyncWelcomeViewController: SyncViewController {

    lazy var mainStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.distribution = .equalSpacing
        stackView.alignment = .fill
        stackView.spacing = 8
        return stackView
    }()

    lazy var syncImage: UIImageView = {
        let imageView = UIImageView(image: UIImage(named: "sync-art"))
        // Shrinking image a bit on smaller devices.
        imageView.setContentCompressionResistancePriority(250, for: .vertical)
        imageView.contentMode = .scaleAspectFit

        return imageView
    }()

    lazy var textStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 4
        return stackView
    }()

    lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 20, weight: UIFontWeightSemibold)
        label.textColor = BraveUX.GreyJ
        label.text = Strings.BraveSync
        label.textAlignment = .center
        return label
    }()

    lazy var descriptionLabel: UILabel = {
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = UIFont.systemFont(ofSize: 15, weight: UIFontWeightRegular)
        label.textColor = BraveUX.GreyH
        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.textAlignment = .center
        label.text = Strings.BraveSyncWelcome
        label.setContentHuggingPriority(250, for: .horizontal)

        return label
    }()

    lazy var buttonsStackView: UIStackView = {
        let stackView = UIStackView()
        stackView.axis = .vertical
        stackView.spacing = 4
        return stackView
    }()

    lazy var existingUserButton: RoundInterfaceButton = {
        let button = RoundInterfaceButton(type: .roundedRect)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(Strings.ScanSyncCode, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 17, weight: UIFontWeightBold)
        button.setTitleColor(UIColor.white, for: .normal)
        button.backgroundColor = BraveUX.BraveOrange
        button.addTarget(self, action: #selector(existingUserAction), for: .touchUpInside)

        button.snp.makeConstraints { make in
            make.height.equalTo(50)
        }

        return button
    }()

    lazy var newToSyncButton: RoundInterfaceButton = {
        let button = RoundInterfaceButton(type: .roundedRect)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.setTitle(Strings.NewSyncCode, for: .normal)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 15, weight: UIFontWeightSemibold)
        button.setTitleColor(BraveUX.GreyH, for: .normal)
        button.addTarget(self, action: #selector(newToSyncAction), for: .touchUpInside)
        return button
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        title = Strings.Sync

        view.addSubview(mainStackView)
        mainStackView.snp.makeConstraints { make in
            make.top.equalTo(self.topLayoutGuide.snp.bottom)
            // This VC doesn't rotate, no need to check for left and right safe area constraints.
            make.left.right.equalTo(self.view).inset(16)
            make.bottom.equalTo(self.view.safeArea.bottom).inset(32)
        }

        // Adding top margin to the image.
        let syncImageStackView = UIStackView(arrangedSubviews: [UIView.spacer(.vertical, amount: 60), syncImage])
        syncImageStackView.axis = .vertical
        mainStackView.addArrangedSubview(syncImageStackView)

        textStackView.addArrangedSubview(titleLabel)
        // Side margins for description text.
        let descriptionStackView = UIStackView(arrangedSubviews: [UIView.spacer(.horizontal, amount: 8),
                                                                  descriptionLabel,
                                                                  UIView.spacer(.horizontal, amount: 8)])

        textStackView.addArrangedSubview(descriptionStackView)
        mainStackView.addArrangedSubview(textStackView)

        buttonsStackView.addArrangedSubview(existingUserButton)
        buttonsStackView.addArrangedSubview(newToSyncButton)
        mainStackView.addArrangedSubview(buttonsStackView)
    }
    
    func newToSyncAction() {
        let addDevice = SyncAddDeviceTypeViewController()
        addDevice.syncInitHandler = { (title, type) in
            weak var weakSelf = self
            func attemptPush() {
                guard Sync.shared.isInSyncGroup else {
                    addDevice.loadingView.isHidden = true
                    let alert = UIAlertController(title: Strings.SyncUnsuccessful, message: Strings.SyncUnableCreateGroup, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: Strings.OK, style: .default, handler: nil))
                    addDevice.present(alert, animated: true, completion: nil)
                    return
                }
                
                // Successful!
                
                let view = SyncAddDeviceViewController(title: title, type: type)
                view.doneHandler = {
                    let settings = SyncSettingsViewController()
                    settings.disableBackButton = true
                    self.navigationController?.pushViewController(settings, animated: true)
                }
                
                view.navigationItem.hidesBackButton = true
                weakSelf?.navigationController?.pushViewController(view, animated: true)
            }
            
            if Sync.shared.isInSyncGroup {
                attemptPush()
                return
            }

            addDevice.loadingView.isHidden = false
            
            NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: NotificationSyncReady),
                                                   object: nil,
                                                   queue: OperationQueue.main,
                                                   using: { _ in attemptPush() })
            
            Sync.shared.initializeNewSyncGroup(deviceName: UIDevice.current.name)
        }

        navigationController?.pushViewController(addDevice, animated: true)
    }
    
    func existingUserAction() {
        let pairCamera = SyncPairCameraViewController()
        
        pairCamera.syncHandler = { bytes in
            Sync.shared.initializeSync(seed: bytes, deviceName: UIDevice.current.name)
            
            func syncJoinedHandler() {
                let settings = SyncSettingsViewController()
                settings.disableBackButton = true
                self.navigationController?.pushViewController(settings, animated: true)
            }
            
            NotificationCenter.default.addObserver(forName: NSNotification.Name(rawValue: NotificationSyncReady),
                                                   object: nil,
                                                   queue: OperationQueue.main,
                                                   using: { _ in syncJoinedHandler() })
        }
        
        navigationController?.pushViewController(pairCamera, animated: true)
    }
}
