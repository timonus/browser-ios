/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit

import Shared
import Storage
import CoreData

private struct HistoryPanelUX {
    static let WelcomeScreenPadding: CGFloat = 15
    static let WelcomeScreenItemTextColor = UIColor.gray
    static let WelcomeScreenItemWidth = 170
}

class HistoryPanel: SiteTableViewController, HomePanel {
    weak var homePanelDelegate: HomePanelDelegate? = nil
    fileprivate lazy var emptyStateOverlayView: UIView = self.createEmptyStateOverview()
    fileprivate var kvoContext: UInt8 = 1
    var frc: NSFetchedResultsController<NSFetchRequestResult>?

    init() {
        super.init(nibName: nil, bundle: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(HistoryPanel.notificationReceived(_:)), name: NotificationFirefoxAccountChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(HistoryPanel.notificationReceived(_:)), name: NotificationPrivateDataClearedHistory, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(HistoryPanel.notificationReceived(_:)), name: NotificationDynamicFontChanged, object: nil)
    }

    override func viewDidLoad() {
        frc = History.frc()
        frc!.delegate = self
        super.viewDidLoad()
        self.tableView.accessibilityIdentifier = "History List"

        reloadData()
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self, name: NotificationFirefoxAccountChanged, object: nil)
        NotificationCenter.default.removeObserver(self, name: NotificationPrivateDataClearedHistory, object: nil)
        NotificationCenter.default.removeObserver(self, name: NotificationDynamicFontChanged, object: nil)
    }

    func notificationReceived(_ notification: Notification) {
        switch notification.name {
        case NotificationDynamicFontChanged:
            if emptyStateOverlayView.superview != nil {
                emptyStateOverlayView.removeFromSuperview()
            }
            emptyStateOverlayView = createEmptyStateOverview()
            break
        default:
            // no need to do anything at all
            break
        }
    }

    override func reloadData() {
        guard let frc = frc else {
            return
        }

        do {
            try frc.performFetch()
        } catch let error as NSError {
            print(error.description)
        }

        tableView.reloadData()
        updateEmptyPanelState()
    }

    fileprivate func updateEmptyPanelState() {
        if frc?.fetchedObjects?.count == 0 {
            if self.emptyStateOverlayView.superview == nil {
                self.tableView.addSubview(self.emptyStateOverlayView)
                self.emptyStateOverlayView.snp.makeConstraints { make -> Void in
                    make.edges.equalTo(self.tableView)
                    make.size.equalTo(self.view)
                }
            }
        } else {
            self.emptyStateOverlayView.removeFromSuperview()
        }
    }

    fileprivate func createEmptyStateOverview() -> UIView {
        let overlayView = UIView()
        overlayView.backgroundColor = UIColor.white

        return overlayView
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = super.tableView(tableView, cellForRowAt: indexPath)
        configureCell(cell, atIndexPath: indexPath)
        return cell
    }

    func configureCell(_ _cell: UITableViewCell, atIndexPath indexPath: IndexPath) {
        guard let cell = _cell as? TwoLineTableViewCell else { return }
        let site = frc!.object(at: indexPath) as! History
        cell.backgroundColor = UIColor.clear
        cell.setLines(site.title, detailText: site.url)
        
        cell.imageView?.contentMode = .center
        cell.imageView?.image = FaviconFetcher.defaultFavicon
        cell.imageView?.layer.cornerRadius = 6
        cell.imageView?.layer.masksToBounds = true
        
        if let faviconMO = site.domain?.favicon, let urlString = faviconMO.url, let url = URL(string: urlString) {
            ImageCache.shared.image(url, type: .square, callback: { (image) in
                if image == nil {
                    postAsyncToMain {
                        cell.imageView?.contentMode = .scaleAspectFit
                        cell.imageView?.sd_setImage(with: url, completed: { (img, err, type, url) in
                            if let img = img, let url = url {
                                ImageCache.shared.cache(img, url: url, type: .square, callback: nil)
                            }
                        })
                    }
                }
                else {
                    postAsyncToMain {
                        cell.imageView?.contentMode = .scaleAspectFit
                        cell.imageView?.image = image
                    }
                }
            })
        }
    }

    func tableView(_ tableView: UITableView, didSelectRowAtIndexPath indexPath: IndexPath) {
        let site = frc?.object(at: indexPath) as! History

        if let u = site.url, let url = URL(string: u) {
            homePanelDelegate?.homePanel(self, didSelectURL: url)
        }
        tableView.deselectRow(at: indexPath, animated: true)
    }

    // Minimum of 1 section
    func numberOfSectionsInTableView(_ tableView: UITableView) -> Int {
        let count = frc?.sections?.count ?? 0
        return count
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sections = frc?.sections else { return nil }
        return sections.indices ~= section ? sections[section].name : nil
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sections = frc?.sections else { return 0 }
        return sections.indices ~= section ? sections[section].numberOfObjects : 0
    }

    func tableView(_ tableView: UITableView, canEditRowAtIndexPath indexPath: IndexPath) -> Bool {
        return true
    }

    func tableView(_ tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: IndexPath) {
        if (editingStyle == UITableViewCellEditingStyle.delete) {
            if let obj = self.frc?.object(at: indexPath) as? History {
                let context = DataController.shared.mainThreadContext
                context.delete(obj)
                DataController.saveContext(context: context)
            }
        }
    }

    override func getLongPressUrl(forIndexPath indexPath: IndexPath) -> (URL?, [Int]?) {
        guard let obj = frc?.object(at: indexPath) as? History else { return (nil, nil) }
        return (obj.url != nil ? URL(string: obj.url!) : nil, nil)
    }
}

extension HistoryPanel : NSFetchedResultsControllerDelegate {
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        switch type {
        case .insert:
            let sectionIndexSet = IndexSet(integer: sectionIndex)
            self.tableView.insertSections(sectionIndexSet, with: .fade)
        case .delete:
            let sectionIndexSet = IndexSet(integer: sectionIndex)
            self.tableView.deleteSections(sectionIndexSet, with: .fade)
        default: break;
        }
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch (type) {
        case .insert:
            if let indexPath = newIndexPath {
                tableView.insertRows(at: [indexPath], with: .automatic)
            }
        case .delete:
            if let indexPath = indexPath {
                tableView.deleteRows(at: [indexPath], with: .automatic)
            }
        case .update:
            if let indexPath = indexPath, let cell = tableView.cellForRow(at: indexPath) {
                configureCell(cell, atIndexPath: indexPath)
            }
        case .move:
            if let indexPath = indexPath {
                tableView.deleteRows(at: [indexPath], with: .automatic)
            }

            if let newIndexPath = newIndexPath {
                tableView.insertRows(at: [newIndexPath], with: .automatic)
            }
        }
        updateEmptyPanelState()
    }
}
