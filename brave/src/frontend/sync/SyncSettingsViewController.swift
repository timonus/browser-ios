/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

class SyncSettingsViewController: AppSettingsTableViewController {
    
    private enum SyncSection: Int {
        
        case devices, options, reset
        
        // To disable a section, just remove it from this enum, and it will no longer be loaded
        static let allSections: [SyncSection] = [.options, .devices, .reset]
        
        func settings(profile: Profile) -> SettingSection? {
            // TODO: move these prefKeys somewhere else
            let syncPrefBookmarks = "syncBookmarksKey"
            let syncPrefTabs = "syncTabsKey"
            let syncPrefHistory = "syncHistoryKey"
            
            switch self {
            case .devices:
                guard let devices = Device.deviceSettings(profile: profile) else {
                    return nil
                }
                
                return SettingSection(title: NSAttributedString(string: Strings.Devices.uppercased()), children: devices + [SettingSection(title: nil, children: [RemoveDeviceSetting(profile: profile)])])
            case .options:
                let prefs = profile.prefs
                return SettingSection(title: NSAttributedString(string: Strings.SyncOnDevice.uppercased()), children:
                    [BoolSetting(prefs: prefs, prefKey: syncPrefBookmarks, defaultValue: true, titleText: Strings.Bookmarks)
                    ,BoolSetting(prefs: prefs, prefKey: syncPrefTabs, defaultValue: true, titleText: Strings.Tabs)
                    ,BoolSetting(prefs: prefs, prefKey: syncPrefHistory, defaultValue: true, titleText: Strings.History)
                    ]
                )
            case .reset:
                return SettingSection(title: nil, children: [RemoveDeviceSetting(profile: profile)])
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
    
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let footerView = InsetLabel(frame: CGRect(x: 0, y: 5, width: tableView.frame.size.width, height: 60))
        footerView.leftInset = CGFloat(20)
        footerView.rightInset = CGFloat(45)
        footerView.numberOfLines = 0
        footerView.lineBreakMode = .byWordWrapping
        footerView.font = UIFont.systemFont(ofSize: 13)
        footerView.textColor = UIColor(rgb: 0x696969)
        
        if section == SyncSection.options.rawValue {
            footerView.text = Strings.SyncDeviceSettingsFooter
        }
        
        return footerView
    }
    
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return section == SyncSection.options.rawValue ? 40 : 20
    }
    
    override func tableView(_ tableView: UITableView, shouldHighlightRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section != 1
    }
    
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        return indexPath.section == 1
    }
    
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            guard let devices = Device.deviceSettings(profile: profile) else {
                return;
            }
            
            devices[indexPath.row].device.remove(save: true)
            tableView.reloadData()
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        title = Strings.Devices
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(SEL_addDevice))
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
    }
    
    override func generateSettings() -> [SettingSection] {
        settings += SyncSection.allSyncSettings(profile: self.profile)
        
        return settings
    }
    
    func SEL_addDevice() {
        let view = SyncAddDeviceTypeViewController()
        navigationController?.pushViewController(view, animated: true)
    }
}
