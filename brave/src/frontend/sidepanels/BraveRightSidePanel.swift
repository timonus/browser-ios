/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Storage
import SnapKit
import Shared

struct ShieldBlockedStats {
    var abAndTp = 0
    var httpse = 0
    var js = 0
    var fp = 0
}

class BraveRightSidePanelViewController : SidePanelBaseViewController {

    let siteName = UILabel()
    let shieldToggle = UISwitch()
    let shieldToggleTitle = UILabel()
    let toggleHttpse =  UISwitch()
    let toggleHttpseTitle =  UILabel()
    let toggleBlockAds = UISwitch()
    let toggleBlockAdsTitle =  UILabel()
    let toggleBlockScripts = UISwitch()
    let toggleBlockScriptsTitle =  UILabel()
    let toggleBlockMalware = UISwitch()
    let toggleBlockMalwareTitle =  UILabel()
    let toggleBlockFingerprinting = UISwitch()
    let toggleBlockFingerprintingTitle =  UILabel()
    let shieldsOverview = UILabel()
    let shieldsOverviewFooter = UILabel()
    
    // Constraints stored for updating dynamically
    var shieldsOverviewContainerHeightConstraint: Constraint?

    let headerContainer = UIView()
    // Shield description container on new tab page
    let shieldsOverviewContainer = UIView()
    let siteNameContainer = UIView()
    let statsContainer = UIView()
    let togglesContainer = UIView()

    let statAdsBlocked = UILabel()
    let statHttpsUpgrades = UILabel()
    let statFPBlocked = UILabel()
    let statScriptsBlocked = UILabel()

    let ui_edgeInset = CGFloat(20)
    let ui_sectionTitleHeight = CGFloat(26)
    let ui_sectionTitleFontSize = CGFloat(15)
    let ui_siteNameSectionHeight = CGFloat(84)
    let ui_togglesContainerRowHeight = CGFloat(46)

    lazy var views_toggles: [UISwitch] = {
        return [self.toggleBlockAds, self.toggleHttpse, self.toggleBlockMalware, self.toggleBlockScripts, self.toggleBlockFingerprinting]
    }()

    let screenHeightRequiredForSectionHeader = CGFloat(600)

    override var canShow: Bool {
        let site = BraveApp.getCurrentWebView()?.URL?.normalizedHost
        return site != nil
    }

    override func viewDidLoad() {
        isLeftSidePanel = false
         NotificationCenter.default.addObserver(self, selector: #selector(pageChanged), name: NSNotification.Name(rawValue: kNotificationPageUnload), object: nil)
        super.viewDidLoad()
    }

    override func setupContainerViewSize() {
        let h = max(UIScreen.main.bounds.height, UIScreen.main.bounds.width)
        containerView.frame = CGRect(x: 0, y: 0, width: CGFloat(BraveUX.WidthOfSlideOut), height: h)
        setupContainerViewContentSize()
    }
    
    fileprivate func setupContainerViewContentSize() {
        containerView.setNeedsLayout()
        containerView.layoutIfNeeded()
        var height: CGFloat = 0.0
        containerView.subviews.forEach { height += $0.bounds.size.height }
        viewAsScrollView().contentSize = CGSize(width: containerView.frame.width, height: height)
    }

    @objc func pageChanged() {
        postAsyncToMain(0.4) {
            if !self.view.isHidden {
                self.updateSitenameAndTogglesState()
            }
        }
    }

    fileprivate func isTinyScreen() -> Bool{
        let h = max(UIScreen.main.bounds.height, UIScreen.main.bounds.width)
        return h < 500
    }

    fileprivate func isShowingShieldOverview() -> Bool {
        return getApp().browserViewController.homePanelController != nil
    }

    fileprivate func setGrayTextColor(_ v: UIView) {
        if let label = v as? UILabel {
            if label.textColor == UIColor.black {
                label.textColor = UIColor(white: 88/255, alpha: 1.0)
            }
        }
        v.subviews.forEach { setGrayTextColor($0) }
    }
    
    // Creates a new divider pinned to bottom of the super view
    fileprivate func newDivider(_ superView: UIView) -> UIView {

        let divider = UIView()
        superView.addSubview(divider)
        
        divider.backgroundColor = BraveUX.ColorForSidebarLineSeparators

        divider.snp_makeConstraints { make in
            make.right.bottom.left.equalTo(divider.superview!)
            make.height.equalTo(1.0)
        }
        
        return divider
    }

    override func setupUIElements() {
        super.setupUIElements()

        func makeSectionHeaderTitle(_ title: String, sectionHeight: CGFloat) -> UIView {
            let container = UIView()
            let topTitle = UILabel()
            container.addSubview(topTitle)
            topTitle.font = UIFont.systemFont(ofSize: ui_sectionTitleFontSize)
            topTitle.alpha = 0.6
            topTitle.text = title
            topTitle.snp_makeConstraints { (make) in
                make.left.equalTo(topTitle.superview!).offset(ui_edgeInset)
                make.bottom.equalTo(topTitle.superview!)
            }
            container.snp_makeConstraints { (make) in
                make.height.equalTo(sectionHeight)
            }
            return container
        }

        var togglesSectionTitle: UIView? = nil
        let titleSectionHeight = isTinyScreen() ? ui_sectionTitleHeight - 6 : ui_sectionTitleHeight
        if screenHeightRequiredForSectionHeader < max(UIScreen.main.bounds.height, UIScreen.main.bounds.width) {
            togglesSectionTitle = makeSectionHeaderTitle(Strings.Individual_Controls, sectionHeight: titleSectionHeight)
        }

        let statsSectionTitle = makeSectionHeaderTitle(Strings.Blocking_Monitor, sectionHeight: titleSectionHeight)

        var sections = [headerContainer, shieldsOverviewContainer, siteNameContainer, statsSectionTitle, statsContainer]
        
        if let togglesSectionTitle = togglesSectionTitle {
            sections.append(togglesSectionTitle)
        }
        sections.append(togglesContainer)
        containerView.subviews.forEach {
            $0.removeConstraints($0.constraints)
            $0.removeFromSuperview()
        }
        sections.forEach { containerView.addSubview($0) }
        sections.enumerated().forEach { i, section in
            section.snp_makeConstraints({ (make) in
                make.left.right.equalTo(section.superview!)

                if i == 0 {
                    make.top.equalTo(section.superview!)
                    // Height adjusted dynamically for status bar
                    // Must be assigned to something for snp to `update` constraints
                    make.height.equalTo(0)
                } else if section !== sections.last {
                    make.top.equalTo(sections[i - 1].snp.bottom)
                    make.bottom.equalTo(sections[i + 1].snp.top)
                }

                if section === siteNameContainer {
                    // Height adjusted dynamically
                    // Must be assigned to something for snp to `update` constraints
                    make.height.equalTo(0)
                } else if section === shieldsOverviewContainer {
                    // Updated dynamically
                    shieldsOverviewContainerHeightConstraint = make.height.equalTo(0).constraint
                } else if section === statsContainer {
                    make.height.equalTo(isTinyScreen() ? 120 : 160)
                } else if section === togglesContainer {
                    let togglesHeight = CGFloat(views_toggles.count) * ui_togglesContainerRowHeight
                    let togglesContainerHeight = togglesSectionTitle != nil  ? togglesHeight + titleSectionHeight : togglesHeight
                    make.height.equalTo(togglesContainerHeight)
                }
            })
        }

        view.backgroundColor = .white
        
        let headerColor = BraveUX.BackgroundColorForSideToolbars
        headerContainer.backgroundColor = headerColor
        shieldsOverviewContainer.backgroundColor = headerColor
        siteNameContainer.backgroundColor = headerColor

        let containerBackgroundColor = UIColor.clear
        containerView.backgroundColor = containerBackgroundColor
        statsSectionTitle.backgroundColor = containerBackgroundColor
        statsContainer.backgroundColor = containerBackgroundColor
        togglesSectionTitle?.backgroundColor = containerBackgroundColor
        togglesContainer.backgroundColor = containerBackgroundColor
        
        viewAsScrollView().isScrollEnabled = true
        viewAsScrollView().bounces = false

        func setupHeaderSection() {
            let heading = UILabel()
            
            headerContainer.addSubview(heading)
            newDivider(headerContainer)
            
            heading.text = Strings.Site_shield_settings
            heading.textColor = UIColor.black
            heading.font = UIFont.boldSystemFont(ofSize: 18)
            
            heading.snp_makeConstraints { (make) in
                make.right.equalTo(heading.superview!)
                make.bottom.equalTo(heading.superview!).inset(12)
                make.left.equalTo(heading.superview!).offset(ui_edgeInset)
            }
        }
        setupHeaderSection()

        func setupShieldsOverviewSection() {
            shieldsOverview.numberOfLines = 0
            shieldsOverviewFooter.numberOfLines = 0
            if UIDevice.current.userInterfaceIdiom != .pad {
                shieldsOverview.font = UIFont.systemFont(ofSize: 15)
                shieldsOverviewFooter.font = UIFont.systemFont(ofSize: 15)
            }
            
            shieldsOverview.text = Strings.Shields_Overview
            shieldsOverviewFooter.text = Strings.Shields_Overview_Footer
            shieldsOverviewFooter.textColor = UIColor.lightGray
            
            [shieldsOverview, shieldsOverviewFooter].forEach { shieldsOverviewContainer.addSubview($0) }
            
            shieldsOverview.snp_makeConstraints {
                make in
                make.top.equalTo(shieldsOverview.superview!).offset(30)
                make.left.equalTo(shieldsOverview.superview!).inset(ui_edgeInset)
                make.right.equalTo(shieldsOverview.superview!).inset(ui_edgeInset)
            }
            
            shieldsOverviewFooter.snp_makeConstraints {
                make in
                make.top.equalTo(shieldsOverview.snp_bottom).offset(20)
                make.left.equalTo(shieldsOverviewFooter.superview!).inset(ui_edgeInset)
                make.right.equalTo(shieldsOverviewFooter.superview!).inset(ui_edgeInset)
                make.bottom.equalTo(shieldsOverviewFooter.superview!).inset(50)
            }
        }
        // Always setup shield overview section, it will be hidden if not needed
        setupShieldsOverviewSection()
        
        func setupSiteNameSection() {
            siteName.font = UIFont.boldSystemFont(ofSize: 22)
            siteName.lineBreakMode = NSLineBreakMode.byTruncatingMiddle
            siteName.minimumScaleFactor = 0.75

            let down = UILabel()
            down.text = Strings.Down
            let up = UILabel()
            up.text = Strings.Up

            [siteName, up, down, shieldToggle].forEach { siteNameContainer.addSubview($0) }

            siteName.snp_makeConstraints {
                make in
                make.left.equalTo(siteName.superview!).inset(ui_edgeInset)
                make.right.equalTo(siteName.superview!).inset(ui_edgeInset)
                make.bottom.equalTo(shieldToggle.snp_top).inset(-8)
            }
            siteName.adjustsFontSizeToFitWidth = true

            [down, up].forEach {
                $0.font = UIFont.boldSystemFont(ofSize: 14)
                setGrayTextColor($0)
            }

            down.snp_makeConstraints {
                make in
                make.left.equalTo(down.superview!).inset(ui_edgeInset + 2)
                make.centerY.equalTo(shieldToggle)
            }

            up.snp_makeConstraints {
                make in
                make.left.equalTo(shieldToggle.snp_right).offset(10)
                make.centerY.equalTo(shieldToggle)
            }

            shieldToggle.snp_makeConstraints {
                make in
                make.left.equalTo(down.snp_right).offset(8)
                make.bottom.equalTo(shieldToggle.superview!.snp_bottomMargin)
            }
            shieldToggle.onTintColor = BraveUX.BraveOrange
            shieldToggle.tintColor = BraveUX.SwitchTintColor
            shieldToggle.addTarget(self, action: #selector(switchToggled(_:)), for: .valueChanged)
        }
        setupSiteNameSection()

        func setupSwitchesSection() {
            let views_labels = [toggleBlockAdsTitle, toggleHttpseTitle, toggleBlockMalwareTitle, toggleBlockScriptsTitle, toggleBlockFingerprintingTitle]
            let labelTitles = [Strings.Block_Ads_and_Tracking, Strings.HTTPS_Everywhere, Strings.Block_Phishing, Strings.Block_Scripts, Strings.Fingerprinting_Protection_wrapped]

            func layoutSwitch(_ switchItem: UISwitch, label: UILabel) -> UIView {
                let row = UIView()
                togglesContainer.addSubview(row)
                row.addSubview(switchItem)
                row.addSubview(label)
                
                switchItem.snp_makeConstraints { (make) in
                    make.left.equalTo(row)
                    make.centerY.equalTo(row)
                }

                label.snp_makeConstraints { make in
                    make.left.equalTo(switchItem.snp_right).offset(10)
                    make.centerY.equalTo(switchItem.snp_centerY)
                    make.right.equalTo(label.superview!.snp_right)
                }

                return row
            }

            var rows = [UIView]()
            for (i, item) in views_toggles.enumerated() {
                item.onTintColor = BraveUX.BraveOrange
                item.tintColor = BraveUX.SwitchTintColor
                item.addTarget(self, action: #selector(switchToggled(_:)), for: .valueChanged)
                views_labels[i].text = labelTitles[i]
                if UIDevice.current.userInterfaceIdiom != .pad {
                    views_labels[i].font = UIFont.systemFont(ofSize: 15)
                }
                views_labels[i].adjustsFontSizeToFitWidth = true
                rows.append(layoutSwitch(item, label: views_labels[i]))
            }

            rows.enumerated().forEach { i, row in
                row.snp_remakeConstraints({ (make) in
                    make.left.right.equalTo(row.superview!).inset(ui_edgeInset)
                    if i == 0 {
                        make.height.equalTo(ui_togglesContainerRowHeight)
                        make.top.equalTo(row.superview!).offset(5)
                        make.bottom.equalTo(rows[i + 1].snp_top)
                    } else if i == rows.count - 1 {
                        make.top.greaterThanOrEqualTo(rows[i - 1].snp_bottom)
                        make.bottom.greaterThanOrEqualTo(row.superview!).inset(5)
                    } else {
                        make.top.greaterThanOrEqualTo(rows[i - 1].snp_bottom)
                        make.bottom.equalTo(rows[i + 1].snp_top)
                    }
                    if i > 0 {
                        make.height.equalTo(rows[0])
                    }
                })
            }

            toggleBlockFingerprintingTitle.lineBreakMode = .byWordWrapping
            toggleBlockFingerprintingTitle.numberOfLines = 2
        }

        setupSwitchesSection()

        func setupStatsSection() {
            let statTitles = [Strings.Ads_and_Trackers, Strings.HTTPS_Upgrades, Strings.Scripts_Blocked, Strings.Fingerprinting_Methods]
            let statViews = [statAdsBlocked, statHttpsUpgrades, statScriptsBlocked, statFPBlocked]
            let statColors = [UIColor(red:254/255.0, green:82/255.0, blue:29/255.0, alpha:),
                              UIColor(red:7/255.0, green:150/255.0, blue:250/255.0, alpha:1),
                              UIColor(red:153/255.0, green:153/255.0, blue:153/255.0, alpha:1),
                              UIColor(red:255/255.0, green:192/255.0, blue:0/255.0, alpha:1)]

            var prevTitle:UIView? = nil
            for (i, stat) in statViews.enumerated() {
                let label = UILabel()
                label.text = statTitles[i]
                statsContainer.addSubview(label)
                statsContainer.addSubview(stat)

                stat.text = "0"
                stat.font = UIFont.boldSystemFont(ofSize: 28)
                stat.adjustsFontSizeToFitWidth = true
                stat.textColor = statColors[i]
                stat.textAlignment = .right

                stat.snp_makeConstraints {
                    make in
                    make.left.equalTo(stat.superview!).offset(ui_edgeInset)
                    if let prevTitle = prevTitle {
                        make.top.equalTo(prevTitle.snp_bottom)
                        make.height.equalTo(statViews[0])
                    } else {
                        make.top.equalTo(stat.superview!)
                    }

                    if i == statViews.count - 1 {
                        make.bottom.equalTo(stat.superview!)
                    }

                    make.width.equalTo(40)
                }

                label.snp_makeConstraints({ (make) in
                    make.left.equalTo(stat.snp_right).offset(6 + 14)
                    make.centerY.equalTo(stat)
                    make.right.equalTo(label.superview!.snp_right)
                })

                prevTitle = label

                if UIDevice.current.userInterfaceIdiom != .pad {
                    label.font = UIFont.systemFont(ofSize: 15)
                }

                label.adjustsFontSizeToFitWidth = true
            }
        }
        
        newDivider(statsContainer)
        setupStatsSection()

        setGrayTextColor(togglesContainer)
        setGrayTextColor(statsContainer)
        setGrayTextColor(shieldsOverviewContainer)
    }

    @objc func switchToggled(_ sender: UISwitch) {
        guard let site = siteName.text else { return }

        func setKeys(_ globalPrefKey: String, _ globalPrefDefaultValue: Bool, _ siteShieldKey: BraveShieldState.Shield) {
            var state: Bool? = nil
            if siteShieldKey == .AllOff {
                state = !sender.isOn
            } else {
                // state matches the prefs setting
                let pref = BraveApp.getPrefs()?.boolForKey(globalPrefKey) ?? globalPrefDefaultValue
                if sender.isOn != pref {
                    state = sender.isOn
                }
            }

            BraveShieldState.set(forDomain:site, state: (siteShieldKey, state))
            (getApp().browserViewController as! BraveBrowserViewController).updateBraveShieldButtonState(true)
            BraveApp.getCurrentWebView()?.reload()
        }

        switch (sender) {
        case toggleBlockAds:
            setKeys(AdBlocker.prefKey, AdBlocker.prefKeyDefaultValue, .AdblockAndTp)
        case toggleBlockMalware:
            setKeys(SafeBrowsing.prefKey, SafeBrowsing.prefKeyDefaultValue, .SafeBrowsing)
        case toggleBlockScripts:
            setKeys(kPrefKeyNoScriptOn, false, .NoScript)
        case toggleHttpse:
            setKeys(HttpsEverywhere.prefKey, HttpsEverywhere.prefKeyDefaultValue, .HTTPSE)
        case shieldToggle:
            setKeys("", false, .AllOff)
            updateSitenameAndTogglesState()
        case toggleBlockFingerprinting:
            setKeys(kPrefKeyFingerprintProtection, false, .FpProtection)
        default:
            break
        }
    }
    
    func updateSitenameAndTogglesState() {
        let current = stripLocalhostWebServer(BraveApp.getCurrentWebView()?.URL?.absoluteString ?? "")
        guard let url = URL(string:current) else { return }
        // hostName will generally be "localhost" if home page is showing, so checking home page
        siteName.text = isShowingShieldOverview() ? "" : url.normalizedHost

        shieldToggle.isEnabled = !isShowingShieldOverview()
        
        let state = BraveShieldState.getStateForDomain(siteName.text ?? "")
        shieldToggle.isOn = !(state?.isAllOff() ?? false)

        let masterOn = shieldToggle.isOn
        views_toggles.forEach { $0.isEnabled = masterOn && shieldToggle.isEnabled }

        if masterOn {
            toggleBlockAds.isOn = state?.isOnAdBlockAndTp() ?? AdBlocker.singleton.isNSPrefEnabled
            toggleHttpse.isOn = state?.isOnHTTPSE() ?? HttpsEverywhere.singleton.isNSPrefEnabled
            toggleBlockMalware.isOn = state?.isOnSafeBrowsing() ?? SafeBrowsing.singleton.isNSPrefEnabled
            toggleBlockScripts.isOn = state?.isOnScriptBlocking() ?? (BraveApp.getPrefs()?.boolForKey(kPrefKeyNoScriptOn) ?? false)
            toggleBlockFingerprinting.isOn = state?.isOnFingerprintProtection() ?? (BraveApp.getPrefs()?.boolForKey(kPrefKeyFingerprintProtection) ?? false)
        } else {
            views_toggles.forEach { $0.isOn = false }
        }
    }

    override func showPanel(_ showing: Bool, parentSideConstraints: [Constraint?]?) {

        super.showPanel(showing, parentSideConstraints: parentSideConstraints)

        if showing {
            updateSitenameAndTogglesState()
            updateConstraintsForPanelSections()
        }
    }
    
    func updateConstraintsForPanelSections() {
        
        var siteNameHeight = ui_siteNameSectionHeight
        if isShowingShieldOverview() {
            siteNameHeight -= 30
            shieldsOverviewContainerHeightConstraint?.deactivate()
        } else {
            shieldsOverviewContainerHeightConstraint?.activate()
        }
        
        siteNameContainer.snp.updateConstraints { $0.height.equalTo(siteNameHeight) }
        headerContainer.snp.updateConstraints { $0.height.equalTo(44 + CGFloat(spaceForStatusBar())) }
        
        setupContainerViewSize()
    }

    func setShieldBlockedStats(_ shieldStats: ShieldBlockedStats) {
        var shieldStats = shieldStats
        // This check is placed here (instead of an update view method) because it can get called via external
        //  sources, so safest to place right before assigning new text values
        if isShowingShieldOverview() {
            // HttpsUpgrade seems to be 1 for localhost, so overriding it
            shieldStats = ShieldBlockedStats()
        }
        
        statAdsBlocked.text = String(shieldStats.abAndTp)
        statHttpsUpgrades.text = String(shieldStats.httpse)
        statFPBlocked.text = String(shieldStats.fp)
        statScriptsBlocked.text = String(shieldStats.js)
    }
}

