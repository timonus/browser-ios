/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

class SyncSettingsViewController: AppSettingsTableViewController {
    
    private enum SyncSection: Int {
        
        case devices, options, reset
        
        // To disable a section, just remove it from this enum, and it will no longer be loaded
        static let allSections: [SyncSection] = [.options, .reset]
        
        func settings(profile profile: Profile) -> SettingSection? {
            // TODO: move these prefKeys somewhere else
            let syncPrefBookmarks = "syncBookmarksKey"
//            let syncPrefTabs = "syncTabsKey"
//            let syncPrefHistory = "syncHistoryKey"
            
            switch self {
            case .devices:
                guard let devices = Device.deviceSettings(profile: profile) else {
                    return nil
                }
                
                return SettingSection(title: NSAttributedString(string: Strings.Devices.uppercaseString), children: devices)
            case .options:
                let prefs = profile.prefs
                return SettingSection(title: NSAttributedString(string: Strings.SyncOnDevice.uppercaseString), children:
                    [BoolSetting(prefs: prefs, prefKey: syncPrefBookmarks, defaultValue: true, titleText: Strings.Bookmarks)
//                    ,BoolSetting(prefs: prefs, prefKey: syncPrefTabs, defaultValue: true, titleText: Strings.Tabs)
//                    ,BoolSetting(prefs: prefs, prefKey: syncPrefHistory, defaultValue: true, titleText: Strings.History)
                    ]
                )
            case .reset:
                return SettingSection(title: nil, children: [RemoveDeviceSetting(profile: profile)])
            }
        }
        
        static func allSyncSettings(profile profile: Profile) -> [SettingSection] {
            
            var settings = [SettingSection]()
            SyncSection.allSections.forEach {
                if let section = $0.settings(profile: profile) {
                    settings.append(section)
                }
            }
            
            return settings
        }
    }
    

    
    override func tableView(tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let footerView = InsetLabel(frame: CGRectMake(0, 5, tableView.frame.size.width, 60))
        footerView.leftInset = CGFloat(20)
        footerView.rightInset = CGFloat(45)
        footerView.numberOfLines = 0
        footerView.lineBreakMode = .ByWordWrapping
        footerView.font = UIFont.systemFontOfSize(13)
        footerView.textColor = UIColor(rgb: 0x696969)
        
        if section == SyncSection.options.rawValue {
            footerView.text = Strings.SyncDeviceSettingsFooter
        }
        
        return footerView
    }
    
    override func tableView(tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return section == SyncSection.options.rawValue ? 40 : 20
    }
    
    deinit {
        NSNotificationCenter.defaultCenter().removeObserver(self)
    }
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        title = Strings.Devices
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .Add, target: self, action: #selector(SEL_addDevice))
    }
    
    override func viewWillDisappear(animated: Bool) {
        super.viewWillDisappear(animated)
    }
    
    override func generateSettings() -> [SettingSection] {

        settings += SyncSection.allSyncSettings(profile: self.profile)
        
        return settings
    }
    
    func SEL_addDevice() {
        let view = SyncAddDeviceViewController()
        navigationController?.pushViewController(view, animated: true)
    }
}
