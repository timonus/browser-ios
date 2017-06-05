/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

class SyncSettingsViewController: AppSettingsTableViewController {
    
    override func tableView(tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let footerView = InsetLabel(frame: CGRectMake(0, 5, tableView.frame.size.width, 60))
        footerView.leftInset = CGFloat(20)
        footerView.rightInset = CGFloat(45)
        footerView.numberOfLines = 0
        footerView.lineBreakMode = .ByWordWrapping
        footerView.font = UIFont.systemFontOfSize(13)
        footerView.textColor = UIColor(rgb: 0x696969)
        
        if section == 1 {
            footerView.text = Strings.SyncDeviceSettingsFooter
        }
        
        return footerView
    }
    
    override func tableView(tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return section == 1 ? 40 : 20
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
        let prefs = profile.prefs
        
        // TODO: move these prefKeys somewhere else
        let syncPrefBookmarks = "syncBookmarksKey"
        let syncPrefTabs = "syncTabsKey"
        let syncPrefHistory = "syncHistoryKey"
        
        guard let devices = Device.deviceSettings(profile: self.profile) else {
            return [SettingSection]()
        }
        
        settings += [
            SettingSection(title: NSAttributedString(string: Strings.Devices.uppercaseString), children: devices),
            SettingSection(title: NSAttributedString(string: Strings.SyncOnDevice.uppercaseString), children:
                [BoolSetting(prefs: prefs, prefKey: syncPrefBookmarks, defaultValue: true, titleText: Strings.Bookmarks)
//                    ,BoolSetting(prefs: prefs, prefKey: syncPrefTabs, defaultValue: true, titleText: Strings.Tabs)
//                    ,BoolSetting(prefs: prefs, prefKey: syncPrefHistory, defaultValue: true, titleText: Strings.History)
                ]
            ),
            SettingSection(title: nil, children:
                [RemoveDeviceSetting(settings: self)]
            )
        ]
        return settings
    }
    
    func SEL_addDevice() {
        let view = SyncAddDeviceViewController()
        navigationController?.pushViewController(view, animated: true)
    }
}
