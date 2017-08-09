/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import UIKit
import SnapKit
import Storage
import Shared

private struct LoginListUX {
    static let RowHeight: CGFloat = 58
    static let SearchHeight: CGFloat = 58
    static let selectionButtonFont = UIFont.systemFont(ofSize: 16)
    static let selectionButtonTextColor = UIColor.white
    static let selectionButtonBackground = UIConstants.HighlightBlue
    static let NoResultsFont: UIFont = UIFont.systemFont(ofSize: 16)
    static let NoResultsTextColor: UIColor = UIColor.lightGray
}

private extension UITableView {
    var allIndexPaths: [IndexPath] {
        return (0..<self.numberOfSections).flatMap { sectionNum in
            (0..<self.numberOfRows(inSection: sectionNum)).map { IndexPath(row: $0, section: sectionNum) }
        }
    }
}

private let LoginCellIdentifier = "LoginCell"

class LoginListViewController: UIViewController {

    fileprivate lazy var loginSelectionController: ListSelectionController = {
        return ListSelectionController(tableView: self.tableView)
    }()

    fileprivate lazy var loginDataSource: LoginCursorDataSource = {
        return LoginCursorDataSource()
    }()

    fileprivate let profile: Profile

    fileprivate let searchView = SearchInputView()

    fileprivate var activeLoginQuery: Success?

    fileprivate let loadingStateView = LoadingLoginsView()

    // Titles for selection/deselect/delete buttons
    fileprivate let deselectAllTitle = Strings.DeselectAll
    fileprivate let selectAllTitle = Strings.SelectAll
    fileprivate let deleteLoginTitle = Strings.Delete

    fileprivate lazy var selectionButton: UIButton = {
        let button = UIButton()
        button.titleLabel?.font = LoginListUX.selectionButtonFont
        button.setTitle(self.selectAllTitle, for: .normal)
        button.setTitleColor(LoginListUX.selectionButtonTextColor, for: .normal)
        button.backgroundColor = LoginListUX.selectionButtonBackground
        button.addTarget(self, action: #selector(LoginListViewController.SELdidTapSelectionButton), for: .touchUpInside)
        return button
    }()

    fileprivate var selectionButtonHeightConstraint: Constraint?
    fileprivate var selectedIndexPaths = [IndexPath]()

    fileprivate let tableView = UITableView()

    weak var settingsDelegate: SettingsDelegate?

    init(profile: Profile) {
        self.profile = profile
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        let notificationCenter = NotificationCenter.default
        notificationCenter.addObserver(self, selector: #selector(LoginListViewController.SELreloadLogins), name: NotificationDataRemoteLoginChangesWereApplied, object: nil)

        automaticallyAdjustsScrollViewInsets = false
        self.view.backgroundColor = UIColor.white
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(LoginListViewController.SELedit))

        self.title = Strings.Logins

        searchView.delegate = self
        tableView.register(LoginTableViewCell.self, forCellReuseIdentifier: LoginCellIdentifier)

        view.addSubview(searchView)
        view.addSubview(tableView)
        view.addSubview(loadingStateView)
        view.addSubview(selectionButton)

        loadingStateView.isHidden = true

        searchView.snp.makeConstraints { make in
            make.top.equalTo(self.topLayoutGuide.snp.bottom).constraint
            make.left.right.equalTo(self.view)
            make.height.equalTo(LoginListUX.SearchHeight)
        }

        tableView.snp.makeConstraints { make in
            make.top.equalTo(searchView.snp.bottom)
            make.left.right.equalTo(self.view)
            make.bottom.equalTo(self.selectionButton.snp.top)
        }

        selectionButton.snp.makeConstraints { make in
            make.left.right.bottom.equalTo(self.view)
            make.top.equalTo(self.tableView.snp.bottom)
            make.bottom.equalTo(self.view)
            selectionButtonHeightConstraint = make.height.equalTo(0).constraint
        }

        loadingStateView.snp.makeConstraints { make in
            make.edges.equalTo(tableView)
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        tableView.accessibilityIdentifier = "Login List"
        tableView.dataSource = loginDataSource
        tableView.allowsMultipleSelectionDuringEditing = true
        tableView.delegate = self
        tableView.tableFooterView = UIView()

        KeyboardHelper.defaultHelper.addDelegate(self)

        searchView.isEditing ? loadLogins(searchView.inputField.text) : loadLogins()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.loginDataSource.emptyStateView.searchBarHeight = searchView.frame.height
        self.loadingStateView.searchBarHeight = searchView.frame.height
    }

    deinit {
        let notificationCenter = NotificationCenter.default
        notificationCenter.removeObserver(self, name: NotificationProfileDidFinishSyncing, object: nil)
        notificationCenter.removeObserver(self, name: NotificationDataLoginDidChange, object: nil)
    }

    fileprivate func toggleDeleteBarButton() {
        // Show delete bar button item if we have selected any items
        if loginSelectionController.selectedCount > 0 {
            if (navigationItem.rightBarButtonItem == nil) {
                navigationItem.rightBarButtonItem = UIBarButtonItem(title: deleteLoginTitle, style: .plain, target: self, action: #selector(LoginListViewController.SELdelete))
                navigationItem.rightBarButtonItem?.tintColor = UIColor.red
            }
        } else {
            navigationItem.rightBarButtonItem = nil
        }
    }

    fileprivate func toggleSelectionTitle() {
        if loginSelectionController.selectedCount == loginDataSource.allLogins.count {
            selectionButton.setTitle(deselectAllTitle, for: .normal)
        } else {
            selectionButton.setTitle(selectAllTitle, for: .normal)
        }
    }

    fileprivate func loadLogins(_ query: String? = nil) -> Success {
        loadingStateView.isHidden = false
        let query = profile.logins.searchLoginsWithQuery(query).bindQueue(DispatchQueue.main, f: reloadTableWithResult)
        activeLoginQuery = query
        return query
    }

    fileprivate func reloadTableWithResult(_ result: Maybe<Cursor<Login>>) -> Success {
        loadingStateView.isHidden = true
        loginDataSource.allLogins = result.successValue?.asArray() ?? []
        tableView.reloadData()
        activeLoginQuery = nil

        if loginDataSource.count > 0 {
            navigationItem.rightBarButtonItem?.isEnabled = true
        } else {
            navigationItem.rightBarButtonItem?.isEnabled = false
        }

        return succeed()
    }
}

// MARK: - Selectors
extension LoginListViewController {

    func SELreloadLogins() {
        loadLogins()
    }

    func SELedit() {
        navigationItem.rightBarButtonItem = nil
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(LoginListViewController.SELcancel))
        selectionButtonHeightConstraint?.updateOffset(amount: UIConstants.ToolbarHeight)
        self.view.layoutIfNeeded()
        tableView.setEditing(true, animated: true)
    }

    func SELcancel() {
        // Update selection and select all button
        loginSelectionController.deselectAll()
        toggleSelectionTitle()
        selectionButtonHeightConstraint?.updateOffset(amount: 0)
        self.view.layoutIfNeeded()

        tableView.setEditing(false, animated: true)
        navigationItem.leftBarButtonItem = nil
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(LoginListViewController.SELedit))
    }

    func SELdelete() {
        profile.logins.hasSyncedLogins().uponQueue(DispatchQueue.main) { yes in
            let deleteAlert = UIAlertController.deleteLoginAlertWithDeleteCallback({ [unowned self] _ in
                // Delete here
                let guidsToDelete = self.loginSelectionController.selectedIndexPaths.map { indexPath in
                    self.loginDataSource.loginAtIndexPath(indexPath)!.guid
                }

                self.profile.logins.removeLoginsWithGUIDs(guidsToDelete).uponQueue(DispatchQueue.main) { _ in
                    self.SELcancel()
                    self.loadLogins()
                }
            }, hasSyncedLogins: yes.successValue ?? true)

            self.present(deleteAlert, animated: true, completion: nil)
        }
    }

    func SELdidTapSelectionButton() {
        // If we haven't selected everything yet, select all
        if loginSelectionController.selectedCount < loginDataSource.count {
            // Find all unselected indexPaths
            let unselectedPaths = tableView.allIndexPaths.filter { indexPath in
                return !loginSelectionController.indexPathIsSelected(indexPath)
            }
            loginSelectionController.selectIndexPaths(unselectedPaths)
            unselectedPaths.forEach { indexPath in
                self.tableView.selectRow(at: indexPath, animated: true, scrollPosition: .none)
            }
        }

        // If everything has been selected, deselect all
        else {
            loginSelectionController.deselectAll()
            tableView.allIndexPaths.forEach { indexPath in
                self.tableView.deselectRow(at: indexPath, animated: true)
            }
        }

        toggleSelectionTitle()
        toggleDeleteBarButton()
    }
}

// MARK: - UITableViewDelegate
extension LoginListViewController: UITableViewDelegate {

    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        // Force the headers to be hidden
        return 0
    }

    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return LoginListUX.RowHeight
    }

    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCellEditingStyle {
        return .none
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            loginSelectionController.selectIndexPath(indexPath)
            toggleSelectionTitle()
            toggleDeleteBarButton()
        } else {
            tableView.deselectRow(at: indexPath, animated: true)
            let login = loginDataSource.loginAtIndexPath(indexPath)!
            let detailViewController = LoginDetailViewController(profile: profile, login: login)
            detailViewController.settingsDelegate = settingsDelegate
            navigationController?.pushViewController(detailViewController, animated: true)
        }
    }

    func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        if tableView.isEditing {
            loginSelectionController.deselectIndexPath(indexPath)
            toggleSelectionTitle()
            toggleDeleteBarButton()
        }
    }
}

// MARK: - KeyboardHelperDelegate
extension LoginListViewController: KeyboardHelperDelegate {

    func keyboardHelper(_ keyboardHelper: KeyboardHelper, keyboardWillShowWithState state: KeyboardState) {
        let coveredHeight = state.intersectionHeightForView(tableView)
        tableView.contentInset.bottom = coveredHeight
    }

    func keyboardHelper(_ keyboardHelper: KeyboardHelper, keyboardDidShowWithState state: KeyboardState) {
    }

    func keyboardHelper(_ keyboardHelper: KeyboardHelper, keyboardWillHideWithState state: KeyboardState) {
        tableView.contentInset.bottom = 0
    }
}

// MARK: - SearchInputViewDelegate
extension LoginListViewController: SearchInputViewDelegate {

    @objc func searchInputView(_ searchView: SearchInputView, didChangeTextTo text: String) {
        loadLogins(text)
    }

    @objc func searchInputViewBeganEditing(_ searchView: SearchInputView) {
        // Trigger a cancel for editing
        SELcancel()

        // Hide the edit button while we're searching
        navigationItem.rightBarButtonItem = nil
        loadLogins()
    }

    @objc func searchInputViewFinishedEditing(_ searchView: SearchInputView) {
        // Show the edit after we're done with the search
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(LoginListViewController.SELedit))
        loadLogins()
    }
}

/// Controller that keeps track of selected indexes
fileprivate class ListSelectionController: NSObject {

    fileprivate unowned let tableView: UITableView

    fileprivate(set) var selectedIndexPaths = [IndexPath]()

    var selectedCount: Int {
        return selectedIndexPaths.count
    }

    init(tableView: UITableView) {
        self.tableView = tableView
        super.init()
    }

    func selectIndexPath(_ indexPath: IndexPath) {
        selectedIndexPaths.append(indexPath)
    }

    func indexPathIsSelected(_ indexPath: IndexPath) -> Bool {
        return selectedIndexPaths.contains(indexPath) { path1, path2 in
            return path1.row == path2.row && path1.section == path2.section
        }
    }

    func deselectIndexPath(_ indexPath: IndexPath) {
        guard let foundSelectedPath = (selectedIndexPaths.filter { $0.row == indexPath.row && $0.section == indexPath.section }).first,
              let indexToRemove = selectedIndexPaths.index(of: foundSelectedPath) else {
            return
        }

        selectedIndexPaths.remove(at: indexToRemove)
    }

    func deselectAll() {
        selectedIndexPaths.removeAll()
    }

    func selectIndexPaths(_ indexPaths: [IndexPath]) {
        selectedIndexPaths += indexPaths
    }
}

/// Data source for handling LoginData objects from a Cursor
fileprivate class LoginCursorDataSource: NSObject, UITableViewDataSource {

    var count: Int {
        return allLogins.count
    }

    fileprivate var allLogins: [Login] = [] {
        didSet {
            computeLoginSections()
        }
    }

    fileprivate let emptyStateView = NoLoginsView()

    fileprivate var sections = [Character: [Login]]()

    fileprivate var titles = [Character]()

    fileprivate func loginsForSection(_ section: Int) -> [Login]? {
        let titleForSectionIndex = titles[section]
        return sections[titleForSectionIndex]
    }

    func loginAtIndexPath(_ indexPath: IndexPath) -> Login? {
        let titleForSectionIndex = titles[indexPath.section]
        return sections[titleForSectionIndex]?[indexPath.row]
    }

    @objc func numberOfSections(in tableView: UITableView) -> Int {
        let numOfSections = sections.count
        if numOfSections == 0 {
            tableView.backgroundView = emptyStateView
            tableView.separatorStyle = .none
        } else {
            tableView.backgroundView = nil
            tableView.separatorStyle = .singleLine
        }
        return numOfSections
    }

    @objc func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return loginsForSection(section)?.count ?? 0
    }

    @objc func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: LoginCellIdentifier, for: indexPath) as! LoginTableViewCell
        let login = loginAtIndexPath(indexPath)!
        cell.style = .noIconAndBothLabels
        cell.updateCellWithLogin(login)
        return cell
    }

    @objc func sectionIndexTitles(for tableView: UITableView) -> [String]? {
        return titles.map { String($0) }
    }

    @objc func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
        return titles.index(of: Character(title)) ?? 0
    }

    @objc func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return String(titles[section])
    }

    fileprivate func computeLoginSections() {
        titles.removeAll()
        sections.removeAll()

        guard allLogins.count > 0 else {
            return
        }

        // Precompute the baseDomain, host, and hostname values for sorting later on. At the moment
        // baseDomain() is a costly call because of the ETLD lookup tables.
        var domainLookup = [GUID: (baseDomain: String?, host: String?, hostname: String)]()
        allLogins.forEach { login in
            domainLookup[login.guid] = (
                login.hostname.asURL?.baseDomain,
                login.hostname.asURL?.host,
                login.hostname
            )
        }

        // Rules for sorting login URLS:
        // 1. Compare base domains
        // 2. If bases are equal, compare hosts
        // 3. If login URL was invalid, revert to full hostname
        func sortByDomain(_ loginA: Login, loginB: Login) -> Bool {
            guard let domainsA = domainLookup[loginA.guid],
                  let domainsB = domainLookup[loginB.guid] else {
                return false
            }

            guard let baseDomainA = domainsA.baseDomain,
                  let baseDomainB = domainsB.baseDomain,
                  let hostA = domainsA.host,
                let hostB = domainsB.host else {
                return domainsA.hostname < domainsB.hostname
            }

            if baseDomainA == baseDomainB {
                return hostA < hostB
            } else {
                return baseDomainA < baseDomainB
            }
        }

        // Temporarily insert titles into a Set to get duplicate removal for 'free'.
        var titleSet = Set<Character>()
        allLogins.forEach { login in
            // Fallback to hostname if we can't extract a base domain.
            let sortBy = login.hostname.asURL?.baseDomain?.uppercased() ?? login.hostname
            let sectionTitle = sortBy.characters.first ?? Character("")
            titleSet.insert(sectionTitle)

            var logins = sections[sectionTitle] ?? []
            logins.append(login)
            logins.sort(by: sortByDomain)
            sections[sectionTitle] = logins
        }
        titles = Array(titleSet).sorted()
    }

    subscript(index: Int) -> Login {
        get {
            return allLogins[index]
        }
    }
}

/// Empty state view when there is no logins to display.
fileprivate class NoLoginsView: UIView {

    // We use the search bar height to maintain visual balance with the whitespace on this screen. The
    // title label is centered visually using the empty view + search bar height as the size to center with.
    var searchBarHeight: CGFloat = 0 {
        didSet {
            setNeedsUpdateConstraints()
        }
    }

    lazy var titleLabel: UILabel = {
        let label = UILabel()
        label.font = LoginListUX.NoResultsFont
        label.textColor = LoginListUX.NoResultsTextColor
        label.text = Strings.NoLoginsFound
        return label
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(titleLabel)
    }

    fileprivate override func updateConstraints() {
        super.updateConstraints()
        titleLabel.snp.remakeConstraints { make in
            make.centerX.equalTo(self)
            make.centerY.equalTo(self).offset(-(searchBarHeight / 2))
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

/// View to display to the user while we are loading the logins
fileprivate class LoadingLoginsView: UIView {

    var searchBarHeight: CGFloat = 0 {
        didSet {
            setNeedsUpdateConstraints()
        }
    }

    lazy var indicator: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(activityIndicatorStyle: .gray)
        indicator.hidesWhenStopped = false
        return indicator
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        addSubview(indicator)
        backgroundColor = UIColor.white
        indicator.startAnimating()
    }

    fileprivate override func updateConstraints() {
        super.updateConstraints()
        indicator.snp.remakeConstraints { make in
            make.centerX.equalTo(self)
            make.centerY.equalTo(self).offset(-(searchBarHeight / 2))
        }
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
