/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

#if !NO_FABRIC
    import Crashlytics
#endif
import Shared
import MessageUI
import SwiftyJSON
import SwiftKeychainWrapper

let kPrefKeyNoScriptOn = "noscript_on"
let kPrefKeyFingerprintProtection = "fingerprintprotection_on"
let kPrefKeyPrivateBrowsingAlwaysOn = "privateBrowsingAlwaysOn"
let kPrefKeyBrowserLock = "browserLock"
let kPrefKeySetBrowserLock = "setBrowserLockPin"
let kPrefKeyPopupForBrowserLock = "popupForBrowserLock"

class BraveSettingsView : AppSettingsTableViewController {

    static var cachedIs3rdPartyPasswordManagerInstalled = false

    override func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let footerView = InsetLabel(frame: CGRect(x: 0, y: 0, width: tableView.frame.size.width, height: 40))
        footerView.leftInset = CGFloat(20)
        footerView.rightInset = CGFloat(10)
        footerView.numberOfLines = 0
        footerView.font = UIFont.boldSystemFont(ofSize: 13)
        
        return footerView
    }

    override func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 0
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if BraveApp.getPrefs()?.boolForKey(kPrefKeyFingerprintProtection) ?? false {
            if let tab = getApp().tabManager.selectedTab, tab.getHelper(FingerprintingProtection.self) == nil {
                let fp = FingerprintingProtection(browser: tab)
                tab.addHelper(fp)
            }
        }
    }

    override func generateSettings() -> [SettingSection] {
        let prefs = profile.prefs
        var generalSettings = [
            SearchSetting(settings: self),
            BoolSetting(prefs: prefs, prefKey: "saveLogins", defaultValue: true, titleText: Strings.Save_Logins, statusText: nil)
            ,BoolSetting(prefs: prefs, prefKey: "blockPopups", defaultValue: true,
                titleText: Strings.Block_Popups)
        ]

        if UIDevice.current.userInterfaceIdiom == .pad {
            generalSettings.append(BoolSetting(prefs: prefs, prefKey: kPrefKeyTabsBarShowPolicy, defaultValue: true,
                titleText: Strings.Show_Tabs_Bar, statusText: nil,
                settingDidChange: { value in
                    getApp().browserViewController.urlBar.updateTabsBarShowing()
                }
            ))
        } else {
            generalSettings.append(TabsBarIPhoneSetting(profile: self.profile))
        }


        if BraveSettingsView.cachedIs3rdPartyPasswordManagerInstalled {
            generalSettings.append(PasswordManagerButtonSetting(profile: self.profile))
        }

        BraveApp.is3rdPartyPasswordManagerInstalled(true).upon {
            result in
            if result == BraveSettingsView.cachedIs3rdPartyPasswordManagerInstalled {
                return
            }
            BraveSettingsView.cachedIs3rdPartyPasswordManagerInstalled = result

            // TODO: if PW manager is removed, settings must be opening a 2nd time for setting to disappear.
            if result {
                postAsyncToMain(0) { // move from db thread back to main
                    generalSettings.append(PasswordManagerButtonSetting(profile: self.profile))
                    self.settings[0] = SettingSection(title: NSAttributedString(string: Strings.General.uppercased()), children: generalSettings)
                    let range = NSMakeRange(0, 1)
                    let section = IndexSet(integersIn: range.toRange() ?? 0..<0)
                    self.tableView.reloadSections(section, with: .automatic)
                }
            }
        }


        var shieldSettingsList = [BoolSetting(prefs: prefs, prefKey: AdBlocker.prefKey, defaultValue: true, titleText: Strings.Block_Ads_and_Tracking),
                                  BoolSetting(prefs: prefs, prefKey: HttpsEverywhere.prefKey, defaultValue: true, titleText: Strings.HTTPS_Everywhere),
                                  BoolSetting(prefs: prefs, prefKey: SafeBrowsing.prefKey, defaultValue: true, titleText: Strings.Block_Phishing_and_Malware),
                                  BoolSetting(prefs: prefs, prefKey: kPrefKeyNoScriptOn, defaultValue: false, titleText: Strings.Block_Scripts),
                                  BoolSetting(prefs: prefs, prefKey: kPrefKeyFingerprintProtection, defaultValue: false, titleText: Strings.Fingerprinting_Protection)
                                  ]

        let adblockRegionOption = AdBlocker.singleton.isRegionalAdblockPossible()
        if adblockRegionOption.hasRegionalFile {
            let defaultOn = adblockRegionOption.isDefaultSettingOn
            shieldSettingsList.append(BoolSetting(prefs: prefs, prefKey: AdBlocker.prefKeyUseRegional, defaultValue: defaultOn, titleText: Strings.Use_regional_adblock))
        }
        
        weak var weakSelf = self

        settings += [
            SettingSection(title: NSAttributedString(string: Strings.General.uppercased()), children: generalSettings),
            
//            SettingSection(title: NSAttributedString(string: Strings.Sync.uppercased()), children:
//                [SyncDevicesSetting(settings: self)]
//            ),
            SettingSection(title: NSAttributedString(string: Strings.Privacy.uppercased()), children:
                [ClearPrivateDataSetting(settings: self), CookieSetting(profile: self.profile),
                    BoolSetting(prefs: prefs, prefKey: kPrefKeyPrivateBrowsingAlwaysOn, defaultValue: false, titleText: Strings.Private_Browsing_Only, statusText: nil, settingDidChange: { isOn in
                        getApp().browserViewController.switchBrowsingMode(toPrivate: isOn)
                    })]
            ),
            SettingSection(title: NSAttributedString(string: Strings.Security.uppercased()), children:
                [BoolSetting(prefs: prefs, prefKey: kPrefKeyBrowserLock, defaultValue: false, titleText: Strings.Browser_Lock, statusText: nil, settingDidChange: { isOn in
                    if isOn {
                        if KeychainWrapper.pinLockInfo() == nil || !(prefs.boolForKey(kPrefKeySetBrowserLock) ?? false) {
                            let view = PinViewController()
                            view.delegate = weakSelf
                            weakSelf?.navigationController?.pushViewController(view, animated: true)
                        }
                    }
                    else {
                        // Requires verification to turn off.
                        if let profile = weakSelf?.profile {
                            getApp().securityViewController?.start()
                            getApp().securityWindow?.isHidden = false
                            getApp().securityViewController?.successCallback = { (success) in
                                // if we fail to auth user then we set back to ON
                                profile.prefs.setBool(!success, forKey: kPrefKeyBrowserLock)
                                postAsyncToMain {
                                    weakSelf?.tableView.reloadData()
                                    getApp().securityWindow?.isHidden = true
                                }
                            }
                            getApp().securityViewController?.auth()
                        }
                    }
                }),
                 ChangePinSetting(settings: self)]
            ),
            SettingSection(title: NSAttributedString(string: Strings.Brave_Shield_Defaults.uppercased()), children: shieldSettingsList)]

        
        var supportChildren: [Setting] = [
            BoolSetting(prefs: prefs, prefKey: BraveUX.PrefKeyUserAllowsTelemetry, defaultValue: true, titleText: Strings.Opt_in_to_telemetry),
        ]
        
        // If this macro is ever removed, this array can be inline, like the other settings
        #if !DISABLE_INTRO_SCREEN
            supportChildren += [ShowIntroductionSetting(settings: self)]
        #endif
        
        supportChildren += [
            BraveSupportLinkSetting(),
            BravePrivacyPolicySetting(), BraveTermsOfUseSetting()
        ]
    
        settings += [
            SettingSection(title: NSAttributedString(string: Strings.Support.uppercased()), children: supportChildren)]
        
        settings += [
            SettingSection(title: NSAttributedString(string: Strings.About.uppercased()), children: [
                VersionSetting(settings: self),
                ])
        ]
        
        if kIsDevelomentBuild {
            supportChildren = [LoadTabsDebugSettings(), CrashDebugSettings()]
            settings += [
                SettingSection(title: NSAttributedString(string: "DEBUG - BETA ONLY"), children: supportChildren)
            ]
        }
    
        return settings
    }
}

extension BraveSettingsView : PinViewControllerDelegate {
    func pinViewController(_ completed: Bool) {
        if !completed {
            profile.prefs.setBool(false, forKey: kPrefKeyBrowserLock)
            tableView.reloadData()
        }
        else {
            // Corrects issue where fresh install should ignore keychain.
            self.profile?.prefs.setBool(true, forKey: kPrefKeySetBrowserLock)
            self.profile?.prefs.setBool(true, forKey: kPrefKeyBrowserLock)
            tableView.reloadData()
        }
    }
}


class VersionSetting : Setting {
    let settings: SettingsTableViewController

    init(settings: SettingsTableViewController) {
        self.settings = settings
        super.init(title: nil)
    }

    override var title: NSAttributedString? {
        let appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as! String
        let buildNumber = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as! String
        return NSAttributedString(string: String(format: Strings.Version_template, appVersion, buildNumber), attributes: [NSForegroundColorAttributeName: UIConstants.TableViewRowTextColor])
    }

    override func onConfigureCell(_ cell: UITableViewCell) {
        super.onConfigureCell(cell)
        cell.selectionStyle = .none
    }
}


// Opens the search settings pane
class PasswordManagerButtonSetting: PicklistSettingMainItem<String> {

    static var currentSetting: ThirdPartyPasswordManagerType?

    fileprivate static let _prefName = kPrefName3rdPartyPasswordShortcutEnabled

    static func setupOnAppStart() {
        guard let current = BraveApp.getPrefs()?.intForKey(_prefName) else { return }
        currentSetting = ThirdPartyPasswordManagerType(rawValue: Int(current))
    }

    init(profile: Profile) {
        super.init(profile: profile, displayName: "", prefName: PasswordManagerButtonSetting._prefName, options: ThirdPartyPasswordManagerType.choices)
        picklistFooterMessage = Strings.Password_manager_button_settings_footer
    }

    override func picklistSetting(_ setting: PicklistSettingOptionsView, pickedOptionId: Int) {
        super.picklistSetting(setting, pickedOptionId: pickedOptionId)
        PasswordManagerButtonSetting.setupOnAppStart()
    }

    override var title: NSAttributedString? {
        return NSAttributedString(string: Strings.Password_manager_button, attributes: [NSForegroundColorAttributeName: UIConstants.TableViewRowTextColor])
    }
}


// Opens the search settings pane
class CookieSetting: PicklistSettingMainItem<UInt> {
    fileprivate static let _prefName = "braveAcceptCookiesPref"
    fileprivate static let _options =  [
        Choice<UInt> { (displayName: Strings.Block_3rd_party_cookies, object: UInt(HTTPCookie.AcceptPolicy.onlyFromMainDocumentDomain.rawValue), optionId: 0) },
        Choice<UInt> { (displayName: Strings.Block_all_cookies, object: UInt(HTTPCookie.AcceptPolicy.never.rawValue), optionId: 1) },
        Choice<UInt> { (displayName: Strings.Dont_block_cookies, object: UInt( HTTPCookie.AcceptPolicy.always.rawValue), optionId: 2) }
    ]

    static func setPolicyFromOptionId(_ optionId: Int) {
        for option in _options {
            if option.item().optionId == optionId {
                HTTPCookieStorage.shared.cookieAcceptPolicy = HTTPCookie.AcceptPolicy.init(rawValue: option.item().object)!
            }
        }
    }

    static func setupOnAppStart() {
        let current = BraveApp.getPrefs()?.intForKey(_prefName) ?? 0
        setPolicyFromOptionId(Int(current))
    }

    init(profile: Profile) {
        super.init(profile: profile, displayName: Strings.Cookie_Control, prefName: CookieSetting._prefName, options: CookieSetting._options)
    }

    override func picklistSetting(_ setting: PicklistSettingOptionsView, pickedOptionId: Int) {
        super.picklistSetting(setting, pickedOptionId: pickedOptionId)
        CookieSetting.setPolicyFromOptionId(pickedOptionId)
    }
}

// Opens the search settings pane
class TabsBarIPhoneSetting: PicklistSettingMainItem<Int> {
    fileprivate static func getOptions() -> [Choice<Int>] {
        let opt = [
            Choice<Int> { (displayName: Strings.Never_show, object: TabsBarShowPolicy.never.rawValue, optionId: 0) },
            Choice<Int> { (displayName: Strings.Always_show, object: TabsBarShowPolicy.always.rawValue, optionId: 1) },
            Choice<Int> { (displayName: Strings.Show_in_landscape_only, object: TabsBarShowPolicy.landscapeOnly.rawValue, optionId: 2) }
        ]
        return opt

    }

    init(profile: Profile) {
        super.init(profile: profile, displayName: Strings.Show_Tabs_Bar, prefName: kPrefKeyTabsBarShowPolicy, options: TabsBarIPhoneSetting.getOptions())
    }

    override func picklistSetting(_ setting: PicklistSettingOptionsView, pickedOptionId: Int) {
        super.picklistSetting(setting, pickedOptionId: pickedOptionId)
        getApp().browserViewController.urlBar.updateTabsBarShowing()
    }

    override func getCurrent() -> Int {
        return Int(BraveApp.getPrefs()?.intForKey(prefName) ?? Int32(kPrefKeyTabsBarOnDefaultValue.rawValue))
    }
}




// Clear all stored passwords. This will clear SQLite storage and the system shared credential storage.
class PasswordsClearable: Clearable {
    let profile: Profile
    init(profile: Profile) {
        self.profile = profile
    }

    var label: String {
        return Strings.Saved_Logins
    }

    func clear() -> Success {
        // Clear our storage
        return profile.logins.removeAll() >>== { res in
            let storage = URLCredentialStorage.shared
            let credentials = storage.allCredentials
            for (space, credentials) in credentials {
                for (_, credential) in credentials {
                    storage.remove(credential, for: space)
                }
            }
            return succeed()
        }
    }
}

class BraveSupportLinkSetting: Setting {
    override var title: NSAttributedString? {
        return NSAttributedString(string: Strings.Report_a_bug, attributes: [NSForegroundColorAttributeName: UIConstants.TableViewRowTextColor])
    }

    override var url: URL? {
        return BraveUX.BraveCommunityURL as URL
    }

    override func onClick(_ navigationController: UINavigationController?) {
        (navigationController as! SettingsNavigationController).SELdone()
        let url = self.url!
        postAsyncToMain(0) {
            getApp().braveTopViewController.dismissAllSidePanels()
            postAsyncToMain(0.1) {
                let t = getApp().tabManager
                t?.addTabAndSelect(URLRequest(url: url))
            }
        }
    }

}

class BravePrivacyPolicySetting: Setting {
    override var title: NSAttributedString? {
        return NSAttributedString(string: Strings.Privacy_Policy, attributes: [NSForegroundColorAttributeName: UIConstants.TableViewRowTextColor])
    }

    override var url: URL? {
        return BraveUX.BravePrivacyURL as URL
    }

    override func onClick(_ navigationController: UINavigationController?) {
        setUpAndPushSettingsContentViewController(navigationController)
    }
}

class BraveTermsOfUseSetting: Setting {
    override var title: NSAttributedString? {
        return NSAttributedString(string: Strings.Terms_of_Use, attributes: [NSForegroundColorAttributeName: UIConstants.TableViewRowTextColor])
    }

    override var url: URL? {
        return URL(string: "https://www.brave.com/terms_of_use")
    }

    override func onClick(_ navigationController: UINavigationController?) {
        setUpAndPushSettingsContentViewController(navigationController)
    }
}

// MARK: - DEBUG

class LoadTabsDebugSettings: Setting, XMLParserDelegate {
    
    override var title: NSAttributedString? {
        return NSAttributedString(string: "Load All QA Tabs", attributes: [NSForegroundColorAttributeName: UIConstants.TableViewRowTextColor])
    }
    
    override func onClick(_ navigationController: UINavigationController?) {
        
        navigationController?.dismiss(animated: true) {
            getApp().braveTopViewController.togglePanel(getApp().braveTopViewController.mainSidePanel)
        }
        
        let url = URL(string: "https://raw.githubusercontent.com/brave/qa-resources/master/testlinks.json")!
        let string = try? String(contentsOf: url)
        let urls = JSON(parseJSON: string!)["links"].arrayValue.flatMap { URL(string: $0.stringValue) }
        
        for url in urls {
            let request = URLRequest(url: url)
            getApp().tabManager.addTab(request)
        }
        
    }
}

class CrashDebugSettings: Setting, XMLParserDelegate, UIAlertViewDelegate {
    
    override var title: NSAttributedString? {
        return NSAttributedString(string: "CRASH!!", attributes: [NSForegroundColorAttributeName: UIConstants.TableViewRowTextColor])
    }
    
    override func onClick(_ navigationController: UINavigationController?) {
        UIAlertView(title: "Trigger a crash for testing", message: "Force a crash?", delegate: self, cancelButtonTitle: "Cancel", otherButtonTitles: "OK").show()
    }
    
    func alertView(_ alertView: UIAlertView, didDismissWithButtonIndex buttonIndex: Int) {
        if buttonIndex == alertView.cancelButtonIndex {
            return
        }
        #if !NO_FABRIC
            Crashlytics.sharedInstance().crash()
        #endif
    }
}


