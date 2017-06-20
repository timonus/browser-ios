/* This Source Code Form is subject to the terms of the Mozilla Public
* License, v. 2.0. If a copy of the MPL was not distributed with this
* file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Shared

protocol SearchEnginePickerDelegate {
    func searchEnginePicker(_ searchEnginePicker: SearchEnginePicker, didSelectSearchEngine engine: OpenSearchEngine?) -> Void
}

class SearchEnginePicker: UITableViewController {
    var delegate: SearchEnginePickerDelegate?
    var engines: [OpenSearchEngine]!
    var selectedSearchEngineName: String?

    override func viewDidLoad() {
        super.viewDidLoad()

        navigationItem.title = Strings.DefaultSearchEngine
        navigationItem.leftBarButtonItem = UIBarButtonItem(title: Strings.Cancel, style: .plain, target: self, action: #selector(SearchEnginePicker.SELcancel))
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return engines.count
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let engine = engines[indexPath.item]
        let cell = UITableViewCell(style: UITableViewCellStyle.default, reuseIdentifier: nil)
        cell.textLabel?.text = engine.shortName
        cell.imageView?.image = engine.image?.createScaled(CGSize(width: OpenSearchEngine.PreferredIconSize, height: OpenSearchEngine.PreferredIconSize))
        if engine.shortName == selectedSearchEngineName {
            cell.accessoryType = UITableViewCellAccessoryType.checkmark
        }
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let engine = engines[indexPath.item]
        delegate?.searchEnginePicker(self, didSelectSearchEngine: engine)

        guard let cell = tableView.cellForRow(at: indexPath) else { return }
        cell.accessoryType = UITableViewCellAccessoryType.checkmark
    }

    override func tableView(_ tableView: UITableView, didDeselectRowAt indexPath: IndexPath) {
        tableView.cellForRow(at: indexPath)?.accessoryType = UITableViewCellAccessoryType.none
    }

    func SELcancel() {
        delegate?.searchEnginePicker(self, didSelectSearchEngine: nil)
    }
}
