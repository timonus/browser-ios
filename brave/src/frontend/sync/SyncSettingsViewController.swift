/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

class SyncSettingsViewController: AppSettingsTableViewController {
    
    private enum SyncSection: Int {
        // Raw values correspond to table sections.
        case pushSync, devices, actionButtons
        
        // To disable a section, just remove it from this enum, and it will no longer be loaded
        static let allSections: [SyncSection] = [.pushSync, .devices, .actionButtons]
        
        func settings(profile: Profile) -> SettingSection? {
            // TODO: move prefKey somewhere else
            let syncPrefBookmarks = "syncBookmarksKey"
            
            switch self {
            case .devices:
                guard let devices = Device.deviceSettings(profile: profile) else {
                    return nil
                }
                
                return SettingSection(title: NSAttributedString(string: Strings.Devices.uppercased()), children: devices)
            case .pushSync:
                let prefs = profile.prefs
                return SettingSection(title: NSAttributedString(string: Strings.SyncOnDevice.uppercased()), children:
                    [BoolSetting(prefs: prefs, prefKey: syncPrefBookmarks, defaultValue: true,
                                 titleText: Strings.PushSyncEnabled)]
                )
            case .actionButtons:
                return SettingSection(title: nil, children: [AddDeviceSetting(), RemoveDeviceSetting(profile: profile)])
            }
        }
        
        static func allSyncSettings(profile: Profile) -> [SettingSection] {
            
            var settings = [SettingSection]()
            SyncSection.allSections.forEach {
                if let section = $0.settings(profile: profile) {
                    settings.append(section)
                }
            }
            
            return settings
        }
    }
    
    lazy var refreshView: UIRefreshControl = {
        let refresh = UIRefreshControl(frame: CGRect.zero)
        refresh.tintColor = BraveUX.GreyE
        refresh.addTarget(self, action: #selector(reloadDevicesAndSettings), for: .valueChanged)
        return refresh
    }()
    
    var disableBackButton: Bool = false

    override func viewDidLoad() {
        super.viewDidLoad()
        title = Strings.Sync

        // Need to clear it, superclass adds 'Done' button.
        navigationItem.rightBarButtonItem = nil
        
        refreshControl = refreshView
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        if disableBackButton {
            navigationController?.interactivePopGestureRecognizer?.isEnabled = false
            
            navigationItem.setHidesBackButton(true, animated: false)
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(SEL_done))
            
            tableView.reloadData()
        }
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return section == SyncSection.pushSync.rawValue ? nil : super.tableView(tableView, viewForHeaderInSection: section)
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {

        guard let syncSection = SyncSection(rawValue: section) else { return nil }

        switch syncSection {
        case .pushSync:
            // TODO: Better/more user friendly text for explaining users what push sync does.
            return Strings.PushSyncFooter
        case .devices:
            return Strings.SyncDeviceSettingsFooter
        default:
            return nil
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        super.tableView(tableView, didSelectRowAt: indexPath)
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section != SyncSection.devices.rawValue
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        if indexPath.section != SyncSection.devices.rawValue { return false }

        // First cell is our own device, we don't want to allow swipe to delete it.
        return indexPath.row != 0
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        guard let devices = Device.deviceSettings(profile: profile), editingStyle == .delete else { return }
            
        devices[indexPath.row].device.remove(save: true)

        reloadDevicesAndSettings()
    }

    @discardableResult override func generateSettings() -> [SettingSection] {
        settings += SyncSection.allSyncSettings(profile: self.profile)
        
        return settings
    }
    
    func reloadDevicesAndSettings() {
        settings = []
        generateSettings()
        tableView.reloadData()
        refreshControl?.endRefreshing()
    }
    
    func SEL_done() {
        navigationController?.popToRootViewController(animated: true)
    }
}

// MARK: - Table buttons

class RemoveDeviceSetting: Setting {
    let profile: Profile

    override var accessoryType: UITableViewCellAccessoryType { return .none }
    override var accessibilityIdentifier: String? { return "RemoveDeviceSetting" }
    override var textAlignment: NSTextAlignment { return .center }

    init(profile: Profile) {
        self.profile = profile
        let clearTitle = Strings.SyncRemoveThisDevice
        super.init(title: NSAttributedString(string: clearTitle, attributes: [NSForegroundColorAttributeName: UIColor.red, NSFontAttributeName: UIFont.systemFont(ofSize: 17, weight: UIFontWeightRegular)]))
    }

    override func onClick(_ navigationController: UINavigationController?) {
        let alert = UIAlertController(title: Strings.SyncRemoveThisDeviceQuestion, message: Strings.SyncRemoveThisDeviceQuestionDesc, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Strings.Cancel, style: UIAlertActionStyle.cancel, handler: nil))
        alert.addAction(UIAlertAction(title: Strings.Remove, style: UIAlertActionStyle.destructive) { action in
            Sync.shared.leaveSyncGroup()
            navigationController?.popToRootViewController(animated: true)
        })

        navigationController?.present(alert, animated: true, completion: nil)
    }
}

class AddDeviceSetting: Setting {
    override var accessoryType: UITableViewCellAccessoryType { return .none }
    override var accessibilityIdentifier: String? { return "AddDeviceSetting" }
    override var textAlignment: NSTextAlignment { return .center }

    init() {
        let addDeviceString = Strings.SyncAddAnotherDevice

        super.init(title: NSAttributedString(string: addDeviceString, attributes: [NSForegroundColorAttributeName: BraveUX.Blue, NSFontAttributeName: UIFont.systemFont(ofSize: 17, weight: UIFontWeightRegular)]))
    }

    override func onClick(_ navigationController: UINavigationController?) {
        let view = SyncAddDeviceTypeViewController()
        navigationController?.pushViewController(view, animated: true)
    }
}
