/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared
import Deferred

private let SectionToggles = 0
private let SectionButton = 1
private let NumberOfSections = 2
private let SectionHeaderFooterIdentifier = "SectionHeaderFooterIdentifier"
private let TogglesPrefKey = "clearprivatedata.toggles"

private let log = Logger.browserLogger

private let HistoryClearableIndex = 0

class ClearPrivateDataTableViewController: UITableViewController {
    private var clearButton: UITableViewCell?

    var profile: Profile!

    private var gotNotificationDeathOfAllWebViews = false

    private typealias DefaultCheckedState = Bool

    private lazy var clearables: [(clearable: Clearable, checked: DefaultCheckedState)] = {
        return [
            (HistoryClearable(), true),
            (CacheClearable(), true),
            (CookiesClearable(), true),
            (PasswordsClearable(profile: self.profile), true),
            ]
    }()

    private lazy var toggles: [Bool] = {
        if let savedToggles = self.profile.prefs.arrayForKey(TogglesPrefKey) as? [Bool] {
            return savedToggles
        }

        return self.clearables.map { $0.checked }
    }()

    private var clearButtonEnabled = true {
        didSet {
            clearButton?.textLabel?.textColor = clearButtonEnabled ? UIConstants.DestructiveRed : UIColor.lightGrayColor()
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = Strings.ClearPrivateData

        tableView.registerClass(SettingsTableSectionHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: SectionHeaderFooterIdentifier)

        tableView.separatorColor = UIConstants.TableViewSeparatorColor
        tableView.backgroundColor = UIConstants.TableViewHeaderBackgroundColor
        let footer = SettingsTableSectionHeaderFooterView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.width, height: UIConstants.TableViewHeaderFooterHeight))
        footer.showBottomBorder = false
        tableView.tableFooterView = footer
    }

    override func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: UITableViewCellStyle.Default, reuseIdentifier: nil)

        if indexPath.section == SectionToggles {
            cell.textLabel?.text = clearables[indexPath.item].clearable.label
            let control = UISwitch()
            control.onTintColor = UIConstants.ControlTintColor
            control.addTarget(self, action: #selector(ClearPrivateDataTableViewController.switchValueChanged(_:)), forControlEvents: UIControlEvents.ValueChanged)
            control.on = toggles[indexPath.item]
            cell.accessoryView = control
            cell.selectionStyle = .None
            control.tag = indexPath.item
        } else {
            assert(indexPath.section == SectionButton)
            cell.textLabel?.text = Strings.ClearPrivateData
            cell.textLabel?.textAlignment = NSTextAlignment.Center
            cell.textLabel?.textColor = UIConstants.DestructiveRed
            cell.accessibilityTraits = UIAccessibilityTraitButton
            cell.accessibilityIdentifier = "ClearPrivateData"
            clearButton = cell
        }

        return cell
    }

    override func numberOfSectionsInTableView(tableView: UITableView) -> Int {
        return NumberOfSections
    }

    override func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == SectionToggles {
            return clearables.count
        }

        assert(section == SectionButton)
        return 1
    }

    override func tableView(tableView: UITableView, shouldHighlightRowAtIndexPath indexPath: NSIndexPath) -> Bool {
        guard indexPath.section == SectionButton else { return false }

        // Highlight the button only if it's enabled.
        return clearButtonEnabled
    }

    static func clearPrivateData(clearables: [Clearable], secondAttempt: Bool = false) -> Deferred<Void> {
        let deferred = Deferred<Void>()

        clearables.enumerate().map { clearable in
                print("Clearing \(clearable.element).")
            
                if "\(clearable.element)" == "Client.HistoryClearable" {
                    let prefs: Prefs? = getApp().profile?.prefs
                    prefs?.setBool(true, forKey: "ClearedBrowsingHistory")
                }
            
                let res = Success()
                succeed().upon() { _ in // move off main thread
                    clearable.element.clear().upon() { result in
                        res.fill(result)
                    }
                }
                return res
            }
            .allSucceed()
            .upon { result in
                if !result.isSuccess && !secondAttempt {
                    print("Private data NOT cleared successfully")
                    postAsyncToMain(0.5) {
                        // For some reason, a second attempt seems to always succeed
                        clearPrivateData(clearables, secondAttempt: true).upon() { _ in
                            deferred.fill(())
                        }
                    }
                    return
                }

                if !result.isSuccess {
                    print("Private data NOT cleared after 2 attempts")
                }
                deferred.fill(())
        }
        return deferred
    }

    @objc private func allWebViewsKilled() {
        gotNotificationDeathOfAllWebViews = true

        postAsyncToMain(0.5) { // for some reason, even after all webviews killed, an big delay is needed before the filehandles are unlocked
            var clear = [Clearable]()
            for i in 0..<self.clearables.count {
                if self.toggles[i] {
                    clear.append(self.clearables[i].clearable)
                }
            }

            if PrivateBrowsing.singleton.isOn {
                PrivateBrowsing.singleton.exit().upon {
                    ClearPrivateDataTableViewController.clearPrivateData(clear).upon {
                        postAsyncToMain(0.1) {
                            PrivateBrowsing.singleton.enter()
                            getApp().tabManager.addTabAndSelect()
                        }
                    }
                }
            } else {
                ClearPrivateDataTableViewController.clearPrivateData(clear).uponQueue(dispatch_get_main_queue()) {
                    // TODO: add API to avoid add/remove
                    getApp().tabManager.removeTab(getApp().tabManager.addTab()!, createTabIfNoneLeft: true)
                }
            }

            getApp().braveTopViewController.dismissAllSidePanels()
        }
    }

    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        guard indexPath.section == SectionButton else { return }
        
        getApp().profile?.prefs.setObject(self.toggles, forKey: TogglesPrefKey)
        self.clearButtonEnabled = false
        tableView.deselectRowAtIndexPath(indexPath, animated: false)

        NSNotificationCenter.defaultCenter().removeObserver(self)
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(allWebViewsKilled), name: kNotificationAllWebViewsDeallocated, object: nil)

        if (BraveWebView.allocCounter == 0) {
            allWebViewsKilled()
        } else {
            getApp().tabManager.removeAll()
            postAsyncToMain(0.5, closure: {
                if !self.gotNotificationDeathOfAllWebViews {
                    getApp().tabManager.tabs.internalTabList.forEach { $0.deleteWebView(isTabDeleted: true) }
                    self.allWebViewsKilled()
                }
            })
        }
    }

    override func tableView(tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        return tableView.dequeueReusableHeaderFooterViewWithIdentifier(SectionHeaderFooterIdentifier) as! SettingsTableSectionHeaderFooterView
    }

    override func tableView(tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return UIConstants.TableViewHeaderFooterHeight
    }

    @objc func switchValueChanged(toggle: UISwitch) {
        toggles[toggle.tag] = toggle.on

        // Dim the clear button if no clearables are selected.
        clearButtonEnabled = toggles.contains(true)
    }
}
