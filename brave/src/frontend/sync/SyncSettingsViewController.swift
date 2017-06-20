/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

class SyncSettingsViewController: AppSettingsTableViewController {
    
    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let footerView = InsetLabel(frame: CGRect(x: 0, y: 5, width: tableView.frame.size.width, height: 60))
        footerView.leftInset = CGFloat(20)
        footerView.rightInset = CGFloat(45)
        footerView.numberOfLines = 0
        footerView.lineBreakMode = .byWordWrapping
        footerView.font = UIFont.systemFont(ofSize: 13)
        footerView.textColor = UIColor(rgb: 0x696969)
        
        if section == 1 {
            footerView.text = Strings.SyncDeviceSettingsFooter
        }
        
        return footerView
    }
    
    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return section == 1 ? 40 : 20
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
        let prefs = profile.prefs
        
        // TODO: move these prefKeys somewhere else
        let syncPrefBookmarks = "syncBookmarksKey"
        let syncPrefTabs = "syncTabsKey"
        let syncPrefHistory = "syncHistoryKey"
        
        // Generate devices array
        var devices:[Setting] = []
        
        let device1 = SyncDeviceSetting(settings: self, title: "James's Macbook Pro")
        device1.onTap = {
            debugPrint("Show action menu with delete option")
        }
        devices.append(device1)
        
        settings += [
            SettingSection(title: NSAttributedString(string: Strings.Devices.uppercased()), children: devices),
            SettingSection(title: NSAttributedString(string: Strings.SyncOnDevice.uppercased()), children:
                [BoolSetting(prefs: prefs, prefKey: syncPrefBookmarks, defaultValue: true, titleText: Strings.Bookmarks),
                    BoolSetting(prefs: prefs, prefKey: syncPrefTabs, defaultValue: true, titleText: Strings.Tabs),
                    BoolSetting(prefs: prefs, prefKey: syncPrefHistory, defaultValue: true, titleText: Strings.History)]
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
