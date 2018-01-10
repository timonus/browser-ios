/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Storage
import CoreData

class FavouritesDataSource: NSObject, UICollectionViewDataSource {
    var frc: NSFetchedResultsController<NSFetchRequestResult>?
    weak var collectionView: UICollectionView?

    override init() {
        super.init()

        guard let topSitesFolder = Bookmark.getTopSitesFolder() else { return }
        frc = Bookmark.frc(parentFolder: topSitesFolder)
        frc?.delegate = self

        do {
            try frc?.performFetch()
        } catch {
            print("Favorites fetch error")
        }
    }

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return frc?.fetchedObjects?.count ?? 0
    }

    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "Thumbnail", for: indexPath) as! ThumbnailCell
        return configureCell(cell: cell, at: indexPath)

    }

    fileprivate func downloadFaviconsAndUpdateForUrl(_ url: URL, indexPath: IndexPath) {
        weak var weakSelf = self
        FaviconFetcher.getForURL(url).uponQueue(DispatchQueue.main) { result in
            guard let favicons = result.successValue, favicons.count > 0, let foundIconUrl = favicons.first?.url.asURL, let cell = weakSelf?.collectionView?.cellForItem(at: indexPath) as? ThumbnailCell else { return }
            weakSelf?.setCellImage(cell, iconUrl: foundIconUrl, cacheWithUrl: url)
        }
    }

    fileprivate func setCellImage(_ cell: ThumbnailCell, iconUrl: URL, cacheWithUrl: URL) {
        weak var weakSelf = self
        ImageCache.shared.image(cacheWithUrl, type: .square, callback: { (image) in
            if image != nil {
                postAsyncToMain {
                    cell.imageView.image = image
                }
            }
            else {
                postAsyncToMain {
                    cell.imageView.sd_setImage(with: iconUrl, completed: { (img, err, type, url) in
                        guard let img = img else {
                            // avoid recheck to find an icon when none can be found, hack skips FaviconFetch
                            ImageCache.shared.cache(FaviconFetcher.defaultFavicon, url: cacheWithUrl, type: .square, callback: nil)
                            weakSelf?.setDefaultThumbnailBackgroundForCell(cell)
                            return
                        }
                        ImageCache.shared.cache(img, url: cacheWithUrl, type: .square, callback: nil)
                    })
                }
            }
        })
    }

    fileprivate func setDefaultThumbnailBackgroundForCell(_ cell: ThumbnailCell) {
        cell.imageView.image = FaviconFetcher.defaultFavicon
    }

    fileprivate func extractDomainURL(_ url: String) -> String {
        return URL(string: url)?.normalizedHost ?? url
    }

    fileprivate func configureCell(cell: ThumbnailCell, at indexPath: IndexPath) -> UICollectionViewCell {
        guard let fav = frc?.object(at: indexPath) as? Bookmark else { return UICollectionViewCell() }

        cell.textLabel.text = fav.displayTitle ?? fav.url
        cell.accessibilityLabel = cell.textLabel.text

        guard let urlString = fav.url, let url = URL(string: urlString), let normalizedHost = url.normalizedHost else {
            print("url fetch error")
            return UICollectionViewCell()
        }

        guard let collection = collectionView else { return UICollectionViewCell() }


        let suggestedSites = SuggestedSites.asArray()

        let isCommonWebsite = suggestedSites.filter { site in
            extractDomainURL(site.url) == normalizedHost
            }.first

        // TODO: make it prettier
        if let website = isCommonWebsite {
            cell.imageView.backgroundColor = website.backgroundColor
            cell.imageView.contentMode = .scaleAspectFit
            cell.imageView.layer.minificationFilter = kCAFilterTrilinear
            cell.showBorder(!PrivateBrowsing.singleton.isOn)

            guard let iconUrl = website.wordmark.url.asURL,
                let host = iconUrl.host else {
                    self.setDefaultThumbnailBackgroundForCell(cell)
                    return cell
            }

            if iconUrl.scheme == "asset" {
                if let image = UIImage(named: host) {
                    // Images from assets folder.
                    UIGraphicsBeginImageContextWithOptions(image.size, false, 0)
                    image.draw(in: CGRect(origin: CGPoint(x: 3, y: 6), size: CGSize(width: image.size.width - 6, height: image.size.height - 6)))
                    let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
                    UIGraphicsEndImageContext()
                    cell.imageView.image = scaledImage
                }

            }
            else {
                setDefaultThumbnailBackgroundForCell(cell)
                setCellImage(cell, iconUrl: iconUrl, cacheWithUrl: iconUrl)
            }
        } else {
            if ImageCache.shared.hasImage(url, type: .square) {
                ImageCache.shared.image(url, type: .square, callback: { (image) in
                    postAsyncToMain {
                        cell.imageView.image = image
                    }
                })
            }
            else {
                downloadFaviconsAndUpdateForUrl(url, indexPath: indexPath)
            }
        }

        cell.updateLayoutForCollectionViewSize(collection.bounds.size, traitCollection: collection.traitCollection, forSuggestedSite: false)
        return cell
    }
}

extension FavouritesDataSource: NSFetchedResultsControllerDelegate {

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {

        switch type {
        case .insert:
            if let indexPath = indexPath {
                collectionView?.insertItems(at: [indexPath])
            }
            break
        case .delete:
            if let indexPath = indexPath {
                collectionView?.deleteItems(at: [indexPath])
            }
            break
        case .update:
            if let indexPath = indexPath, let cell = collectionView?.cellForItem(at: indexPath) as? ThumbnailCell {
                _ = configureCell(cell: cell, at: indexPath)
            }
            if let newIndexPath = newIndexPath, let cell = collectionView?.cellForItem(at: newIndexPath) as? ThumbnailCell {
                _ = configureCell(cell: cell, at: newIndexPath)
            }
            break
        case .move:
            break
        }
    }
}
