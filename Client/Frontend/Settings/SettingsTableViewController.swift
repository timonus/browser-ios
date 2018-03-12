/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */


import Shared
import UIKit
import XCGLogger

// A base setting class that shows a title. You probably want to subclass this, not use it directly.
class Setting : NSObject {
    fileprivate var _title: NSAttributedString?

    weak var delegate: SettingsDelegate?

    // The url the SettingsContentViewController will show, e.g. Licenses and Privacy Policy.
    var url: URL? { return nil }

    // The title shown on the pref.
    var title: NSAttributedString? { return _title }
    var accessibilityIdentifier: String? { return nil }

    // An optional second line of text shown on the pref.
    var status: NSAttributedString? { return nil }

    // Whether or not to show this pref.
    var hidden: Bool { return false }

    var style: UITableViewCellStyle { return .subtitle }

    var accessoryType: UITableViewCellAccessoryType { return .none }

    var textAlignment: NSTextAlignment { return .left }

    fileprivate(set) var enabled: Bool = true

    // Called when the cell is setup. Call if you need the default behaviour.
    func onConfigureCell(_ cell: UITableViewCell) {
        cell.detailTextLabel?.attributedText = status
        cell.detailTextLabel?.numberOfLines = 1
        cell.detailTextLabel?.adjustsFontSizeToFitWidth = true
        cell.textLabel?.attributedText = title
        cell.textLabel?.textAlignment = textAlignment
        cell.textLabel?.numberOfLines = 0
        cell.textLabel?.adjustsFontSizeToFitWidth = true
        cell.accessoryType = accessoryType
        cell.accessoryView = nil
        cell.selectionStyle = enabled ? .default : .none
        cell.accessibilityIdentifier = accessibilityIdentifier
        if let title = title?.string {
            let detail = cell.detailTextLabel?.text ?? status?.string
            cell.accessibilityLabel = title + (detail != nil ? ", \(detail!)" : "")
        }
        cell.accessibilityTraits = UIAccessibilityTraitButton
        cell.indentationWidth = 0
        cell.layoutMargins = UIEdgeInsets.zero
        // So that the separator line goes all the way to the left edge.
        cell.separatorInset = UIEdgeInsets.zero
    }

    // Called when the pref is tapped.
    func onClick(_ navigationController: UINavigationController?) { return }

    // Helper method to set up and push a SettingsContentViewController
    func setUpAndPushSettingsContentViewController(_ navigationController: UINavigationController?) {
        if let url = self.url {
            let viewController = SettingsContentViewController()
            viewController.settingsTitle = self.title
            viewController.url = url
            navigationController?.pushViewController(viewController, animated: true)
        }
    }

    init(title: NSAttributedString? = nil, delegate: SettingsDelegate? = nil, enabled: Bool? = nil) {
        self._title = title
        self.delegate = delegate
        self.enabled = enabled ?? true
    }
}

// A setting in the sections panel. Contains a sublist of Settings
class SettingSection : Setting {
    fileprivate let children: [Setting]

    init(title: NSAttributedString? = nil, children: [Setting]) {
        self.children = children
        super.init(title: title)
    }

    var count: Int {
        return children.filter { !$0.hidden }.count
    }

    subscript(val: Int) -> Setting? {
        let settings = children.filter { !$0.hidden }
        return 0..<settings.count ~= val ? settings[val] : nil
    }
}

private class PaddedSwitch: UIView {
    fileprivate static let Padding: CGFloat = 8

    init(switchView: UISwitch) {
        super.init(frame: CGRect.zero)

        addSubview(switchView)

        frame.size = CGSize(width: switchView.frame.width + PaddedSwitch.Padding, height: switchView.frame.height)
        switchView.frame.origin = CGPoint(x: PaddedSwitch.Padding, y: 0)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

// A helper class for settings with a UISwitch.
// Takes and optional settingsDidChange callback and status text.
class BoolSetting: Setting {
    let prefKey: String

    fileprivate let prefs: Prefs
    fileprivate let defaultValue: Bool
    fileprivate let settingDidChange: ((Bool) -> Void)?
    fileprivate let statusText: NSAttributedString?

    init(prefs: Prefs, prefKey: String, defaultValue: Bool, attributedTitleText: NSAttributedString, attributedStatusText: NSAttributedString? = nil, settingDidChange: ((Bool) -> Void)? = nil) {
        self.prefs = prefs
        self.prefKey = prefKey
        self.defaultValue = defaultValue
        self.settingDidChange = settingDidChange
        self.statusText = attributedStatusText
        super.init(title: attributedTitleText)
    }

    convenience init(prefs: Prefs, prefKey: String, defaultValue: Bool, titleText: String, statusText: String? = nil, settingDidChange: ((Bool) -> Void)? = nil) {
        var statusTextAttributedString: NSAttributedString?
        if let statusTextString = statusText {
            statusTextAttributedString = NSAttributedString(string: statusTextString, attributes: [NSForegroundColorAttributeName: UIConstants.TableViewHeaderTextColor])
        }
        self.init(prefs: prefs, prefKey: prefKey, defaultValue: defaultValue, attributedTitleText: NSAttributedString(string: titleText, attributes: [NSForegroundColorAttributeName: UIConstants.TableViewRowTextColor]), attributedStatusText: statusTextAttributedString, settingDidChange: settingDidChange)
    }

    override var status: NSAttributedString? {
        return statusText
    }

    override func onConfigureCell(_ cell: UITableViewCell) {
        super.onConfigureCell(cell)

        let control = UISwitch()
        control.onTintColor = UIConstants.ControlTintColor
        control.addTarget(self, action: #selector(BoolSetting.switchValueChanged(_:)), for: UIControlEvents.valueChanged)
        control.isOn = prefs.boolForKey(prefKey) ?? defaultValue
        if let title = title {
            if let status = status {
                control.accessibilityLabel = "\(title.string), \(status.string)"
            } else {
                control.accessibilityLabel = title.string
            }
        }
        cell.accessoryView = PaddedSwitch(switchView: control)
        cell.selectionStyle = .none
    }

    @objc func switchValueChanged(_ control: UISwitch) {
        prefs.setBool(control.isOn, forKey: prefKey)
        settingDidChange?(control.isOn)
    }
}

@objc
protocol SettingsDelegate: class {
    func settingsOpenURLInNewTab(_ url: URL)
}

// The base settings view controller.
class SettingsTableViewController: UITableViewController {

    typealias SettingsGenerator = (SettingsTableViewController, SettingsDelegate?) -> [SettingSection]

    fileprivate let Identifier = "CellIdentifier"
    fileprivate let SectionHeaderIdentifier = "SectionHeaderIdentifier"
    var settings = [SettingSection]()

    weak var settingsDelegate: SettingsDelegate?

    var profile: Profile!

    /// Used to calculate cell heights.
    fileprivate lazy var dummyToggleCell: UITableViewCell = {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: "dummyCell")
        cell.accessoryView = UISwitch()
        return cell
    }()

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.register(UITableViewCell.self, forCellReuseIdentifier: Identifier)
        tableView.register(SettingsTableSectionHeaderFooterView.self, forHeaderFooterViewReuseIdentifier: SectionHeaderIdentifier)
        tableView.tableFooterView = UIView()

        tableView.separatorColor = UIConstants.TableViewSeparatorColor
        tableView.backgroundColor = UIConstants.TableViewHeaderBackgroundColor
        tableView.estimatedRowHeight = 44
        tableView.estimatedSectionHeaderHeight = 44

        settings = generateSettings()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)

        NotificationCenter.default.addObserver(self, selector: #selector(SettingsTableViewController.SELsyncDidChangeState), name: NotificationProfileDidStartSyncing, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(SettingsTableViewController.SELsyncDidChangeState), name: NotificationProfileDidFinishSyncing, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(SettingsTableViewController.SELfirefoxAccountDidChange), name: NotificationFirefoxAccountChanged, object: nil)

        tableView.reloadData()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        SELrefresh()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: NotificationProfileDidStartSyncing, object: nil)
        NotificationCenter.default.removeObserver(self, name: NotificationProfileDidFinishSyncing, object: nil)
        NotificationCenter.default.removeObserver(self, name: NotificationFirefoxAccountChanged, object: nil)
    }

    // Override to provide settings in subclasses
    func generateSettings() -> [SettingSection] {
        return []
    }

    @objc fileprivate func SELsyncDidChangeState() {
        DispatchQueue.main.async {
            self.tableView.reloadData()
        }
    }

    @objc fileprivate func SELrefresh() {
        self.tableView.reloadData()
    }

    @objc func SELfirefoxAccountDidChange() {
        self.tableView.reloadData()
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let section = settings[indexPath.section]
        if let setting = section[indexPath.row] {
            var cell: UITableViewCell!
            if let _ = setting.status {
                // Work around http://stackoverflow.com/a/9999821 and http://stackoverflow.com/a/25901083 by using a new cell.
                // I could not make any setNeedsLayout solution work in the case where we disconnect and then connect a new account.
                // Be aware that dequeing and then ignoring a cell appears to cause issues; only deque a cell if you're going to return it.
                cell = UITableViewCell(style: setting.style, reuseIdentifier: nil)
            } else {
                cell = tableView.dequeueReusableCell(withIdentifier: Identifier, for: indexPath)
            }
            setting.onConfigureCell(cell)
            return cell
        }
        return tableView.dequeueReusableCell(withIdentifier: Identifier, for: indexPath)
    }

    override func numberOfSections(in tableView: UITableView) -> Int {
        return settings.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        let section = settings[section]
        return section.count
    }

    override func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = tableView.dequeueReusableHeaderFooterView(withIdentifier: SectionHeaderIdentifier) as! SettingsTableSectionHeaderFooterView
        let sectionSetting = settings[section]
        if let sectionTitle = sectionSetting.title?.string {
            headerView.titleLabel.text = sectionTitle
        }

        headerView.showTopBorder = false
        return headerView
    }

    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let section = settings[indexPath.section]
        // Workaround for calculating the height of default UITableViewCell cells with a subtitle under
        // the title text label.
        if let setting = section[indexPath.row], setting is BoolSetting && setting.status != nil {
            return calculateStatusCellHeightForSetting(setting)
        }

        return UITableViewAutomaticDimension
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let section = settings[indexPath.section]
        if let setting = section[indexPath.row], setting.enabled {
            setting.onClick(navigationController)
        }
    }

    fileprivate func calculateStatusCellHeightForSetting(_ setting: Setting) -> CGFloat {
        let topBottomMargin: CGFloat = 10

        let tableWidth = tableView.frame.width
        let accessoryWidth = dummyToggleCell.accessoryView!.frame.width
        let insetsWidth = 2 * tableView.separatorInset.left
        let width = tableWidth - accessoryWidth - insetsWidth

        return
            heightForLabel(dummyToggleCell.textLabel!, width: width, text: setting.title?.string) +
                heightForLabel(dummyToggleCell.detailTextLabel!, width: width, text: setting.status?.string) +
                2 * topBottomMargin
    }

    fileprivate func heightForLabel(_ label: UILabel, width: CGFloat, text: String?) -> CGFloat {
        guard let text = text else { return 0 }

        let size = CGSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        let attrs = [NSFontAttributeName: label.font]
        let boundingRect = NSString(string: text).boundingRect(with: size,
                                                                       options: NSStringDrawingOptions.usesLineFragmentOrigin, attributes: attrs, context: nil)
        return boundingRect.height
    }
}

class SettingsTableFooterView: UIView {
    var logo: UIImageView = {
        var image =  UIImageView(image: UIImage(named: "settingsFlatfox"))
        image.contentMode = UIViewContentMode.center
        image.accessibilityIdentifier = "SettingsTableFooterView.logo"
        return image
    }()

    fileprivate lazy var topBorder: CALayer = {
        let topBorder = CALayer()
        topBorder.backgroundColor = UIConstants.SeparatorColor.cgColor
        return topBorder
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIConstants.TableViewHeaderBackgroundColor
        layer.addSublayer(topBorder)
        addSubview(logo)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        topBorder.frame = CGRect(x: 0.0, y: 0.0, width: frame.size.width, height: 0.5)
        logo.center = CGPoint(x: frame.size.width / 2, y: frame.size.height / 2)
    }
}

struct SettingsTableSectionHeaderFooterViewUX {
    static let titleHorizontalPadding: CGFloat = 15
    static let titleVerticalPadding: CGFloat = 6
    static let titleVerticalLongPadding: CGFloat = 20
}

class SettingsTableSectionHeaderFooterView: UITableViewHeaderFooterView {

    enum TitleAlignment {
        case top
        case bottom
    }

    var titleAlignment: TitleAlignment = .bottom {
        didSet {
            remakeTitleAlignmentConstraints()
        }
    }

    var showTopBorder: Bool = false {
        didSet {
            topBorder.isHidden = !showTopBorder
        }
    }

    var showBottomBorder: Bool = false {
        didSet {
            bottomBorder.isHidden = !showBottomBorder
        }
    }

    lazy var titleLabel: UILabel = {
        var headerLabel = UILabel()
        headerLabel.textColor = UIConstants.TableViewHeaderTextColor
        headerLabel.font = UIFont.systemFont(ofSize: 12.0, weight: UIFontWeightRegular)
        headerLabel.numberOfLines = 0
        return headerLabel
    }()

    fileprivate lazy var topBorder: UIView = {
        let topBorder = UIView()
        topBorder.backgroundColor = UIConstants.SeparatorColor
        return topBorder
    }()

    fileprivate lazy var bottomBorder: UIView = {
        let bottomBorder = UIView()
        bottomBorder.backgroundColor = UIConstants.SeparatorColor
        return bottomBorder
    }()

    override init(reuseIdentifier: String?) {
        super.init(reuseIdentifier: reuseIdentifier)
        contentView.backgroundColor = UIConstants.TableViewHeaderBackgroundColor
        addSubview(titleLabel)
        addSubview(topBorder)
        addSubview(bottomBorder)

        setupInitialConstraints()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setupInitialConstraints() {
        bottomBorder.snp.makeConstraints { make in
            make.bottom.left.right.equalTo(self)
            make.height.equalTo(0.5)
        }

        topBorder.snp.makeConstraints { make in
            make.top.left.right.equalTo(self)
            make.height.equalTo(0.5)
        }

        remakeTitleAlignmentConstraints()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        showTopBorder = false
        showBottomBorder = false
        titleLabel.text = nil
        titleAlignment = .bottom
    }

    fileprivate func remakeTitleAlignmentConstraints() {
        switch titleAlignment {
        case .top:
            titleLabel.snp.remakeConstraints { make in
                make.left.right.equalTo(self).inset(SettingsTableSectionHeaderFooterViewUX.titleHorizontalPadding)
                make.top.equalTo(self).offset(SettingsTableSectionHeaderFooterViewUX.titleVerticalPadding)
                make.bottom.equalTo(self).offset(-SettingsTableSectionHeaderFooterViewUX.titleVerticalLongPadding)
            }
        case .bottom:
            titleLabel.snp.remakeConstraints { make in
                make.left.right.equalTo(self).inset(SettingsTableSectionHeaderFooterViewUX.titleHorizontalPadding)
                make.bottom.equalTo(self).offset(-SettingsTableSectionHeaderFooterViewUX.titleVerticalPadding)
                make.top.equalTo(self).offset(SettingsTableSectionHeaderFooterViewUX.titleVerticalLongPadding)
            }
        }
    }
}
