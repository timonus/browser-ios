/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import WebKit
import Shared

class BackForwardListViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    var listData: [LegacyBackForwardListItem]?
    var tabManager: TabManager!

    override func viewDidLoad() {
        let toolbar = UIToolbar()
        view.addSubview(toolbar)

        let doneItem = UIBarButtonItem(title: Strings.Done, style: .done, target: self, action: #selector(BackForwardListViewController.SELdidClickDone))
        let spacer = UIBarButtonItem(barButtonSystemItem: UIBarButtonSystemItem.flexibleSpace, target: nil, action: nil)
        toolbar.items = [doneItem, spacer]

        let listTableView = UITableView()
        listTableView.dataSource = self
        listTableView.delegate = self
        view.addSubview(listTableView)

        toolbar.snp.makeConstraints { make in
            let topLayoutGuide = self.topLayoutGuide as! UIView
            make.top.equalTo(topLayoutGuide.snp.bottom)
            make.left.right.equalTo(self.view)
            return
        }

        listTableView.snp.makeConstraints { make in
            make.top.equalTo(toolbar.snp.bottom)
            make.left.right.bottom.equalTo(self.view)
        }
    }

    func SELdidClickDone() {
        dismiss(animated: true, completion: nil)
    }

    // MARK: - Table view

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return listData?.count ?? 0
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell()
        let item = listData![indexPath.item]
        cell.textLabel?.text = item.title ?? item.URL.absoluteString
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tabManager.selectedTab?.goToBackForwardListItem(listData![indexPath.item])
        dismiss(animated: true, completion: nil)
    }
}
