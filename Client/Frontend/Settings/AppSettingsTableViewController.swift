/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import Shared


/// App Settings Screen (triggered by tapping the 'Gear' in the Tab Tray Controller)
class AppSettingsTableViewController: SettingsTableViewController {
    fileprivate let SectionHeaderIdentifier = "SectionHeaderIdentifier"

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = Strings.Settings
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: Strings.Done,
            style: UIBarButtonItemStyle.done,
            target: navigationController, action: #selector(SettingsNavigationController.SELdone))
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "AppSettingsTableViewController.navigationItem.leftBarButtonItem"
        navigationItem.rightBarButtonItem?.tintColor = BraveUX.BraveOrange

        tableView.accessibilityIdentifier = "AppSettingsTableViewController.tableView"
    }

    override func generateSettings() -> [SettingSection] {
        var settings = [SettingSection]()

        let accountDebugSettings: [Setting]
        accountDebugSettings = []

        let prefs = profile.prefs
        let generalSettings = [
            SearchSetting(settings: self),
            BoolSetting(prefs: prefs, prefKey: "blockPopups", defaultValue: true,
                titleText: Strings.BlockPopupWindows),
            BoolSetting(prefs: prefs, prefKey: "saveLogins", defaultValue: true,
                titleText: Strings.Save_Logins),
        ]

        let accountChinaSyncSetting: [Setting]
        let locale = Locale.current
        if locale.identifier != "zh_CN" {
            accountChinaSyncSetting = []
        } else {
            accountChinaSyncSetting = [
                // Show China sync service setting:
//                ChinaSyncServiceSetting(settings: self)
            ]
        }
        
        settings += [
            SettingSection(title: nil, children: [
//                // Without a Firefox Account:
//                ConnectSetting(settings: self),
//                // With a Firefox Account:
//                AccountStatusSetting(settings: self),
//                SyncNowSetting(settings: self)
            ] + accountChinaSyncSetting + accountDebugSettings)]

        settings += [ SettingSection(title: NSAttributedString(string: Strings.General), children: generalSettings)]

        var privacySettings = [Setting]()

        privacySettings.append(ClearPrivateDataSetting(settings: self))

        privacySettings += [
            BoolSetting(prefs: prefs,
                prefKey: "settings.closePrivateTabs",
                defaultValue: false,
                titleText: Strings.Close_Private_Tabs,
                statusText:Strings.When_Leaving_Private_Browsing)
        ]

        privacySettings += [
            PrivacyPolicySetting()
        ]

        return settings
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
#if !BRAVE
        if !profile.hasAccount() {
            let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: SectionHeaderIdentifier) as! SettingsTableSectionHeaderFooterView
            let sectionSetting = settings[section]
            headerView.titleLabel.text = sectionSetting.title?.string

            switch section {
                // Hide the bottom border for the Sign In to Firefox value prop
                case 1:
                    headerView.titleAlignment = .top
                    headerView.titleLabel.numberOfLines = 0
                    headerView.showBottomBorder = false
                    headerView.titleLabel.snp.updateConstraints { make in
                        make.right.equalTo(headerView).offset(-50)
                    }

                // Hide the top border for the General section header when the user is not signed in.
                case 2:
                    headerView.showTopBorder = false
                default:
                    return super.tableView(tableView, viewForHeaderInSection: section)
            }
            return headerView
        }
#endif
        return super.tableView(tableView, viewForHeaderInSection: section)
    }
}
