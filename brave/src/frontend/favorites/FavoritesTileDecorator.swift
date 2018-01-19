/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import UIKit
import Storage
import Shared

private let log = Logger.browserLogger

enum FavoritesTileType {
    /// Predefinied tile color and custom icon, used for most popular websites.
    case preset
    /// Just a favicon, no background color.
    case faviconOnly
    /// A globe icon, no background color.
    case defaultTile
}

class FavoritesTileDecorator {
    let url: URL
    let normalizedHost: String
    let cell: ThumbnailCell
    let indexPath: IndexPath
    weak var collection: UICollectionView?

    /// Returns SuggestedSite for given tile or nil if no suggested sites found.
    var commonWebsite: SuggestedSite? {
        let suggestedSites = SuggestedSites.asArray()

        return suggestedSites.filter { site in
            extractDomainURL(site.url) == normalizedHost
            }.first
    }

    var tileType: FavoritesTileType {
        if commonWebsite != nil {
            return .preset
        } else if ImageCache.shared.hasImage(url, type: .square) {
            return .faviconOnly
        } else {
            return .defaultTile
        }
    }

    init(url: URL, cell: ThumbnailCell, indexPath: IndexPath) {
        self.url = url
        self.cell = cell
        self.indexPath = indexPath
        normalizedHost = url.normalizedHost ?? ""
    }

    func decorateTile() {
        switch tileType {
        case .preset:
            guard let website = commonWebsite, let iconUrl = website.wordmark.url.asURL, let host = iconUrl.host,
                iconUrl.scheme == "asset", let image = UIImage(named: host) else {
                    // FIXME: Split it into separate guard clauses to give more specific error logs in case something is missing?
                    log.warning("website, iconUrl, host, or image is nil, using default tile")
                    setDefaultTile()
                    return
            }

            cell.imageView.backgroundColor = website.backgroundColor
            cell.imageView.contentMode = .scaleAspectFit
            cell.imageView.layer.minificationFilter = kCAFilterTrilinear
            cell.showBorder(!PrivateBrowsing.singleton.isOn)

            UIGraphicsBeginImageContextWithOptions(image.size, false, 0)
            image.draw(in: CGRect(origin: CGPoint(x: 3, y: 6), size: CGSize(width: image.size.width - 6, height: image.size.height - 6)))
            let scaledImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            cell.imageView.image = scaledImage
            break
        case .faviconOnly:
            ImageCache.shared.image(url, type: .square, callback: { (image) in
                postAsyncToMain {
                    self.cell.imageView.image = image
                }
            })
            break
        case .defaultTile:
            setDefaultTile()

            // attempt to resolove domain problem
            let context = DataController.shared.mainThreadContext
            if let domain = Domain.getOrCreateForUrl(url, context: context), let faviconMO = domain.favicon, let urlString = faviconMO.url, let iconUrl = URL(string: urlString) {
                postAsyncToMain {
                    self.setCellImage(self.cell, iconUrl: iconUrl, cacheWithUrl: self.url)
                }
            }
            else {
                // last resort - download the icon
                downloadFaviconsAndUpdateForUrl(url, indexPath: indexPath)
            }
            break
        }
    }

    private func setDefaultTile() {
        cell.imageView.image = FaviconFetcher.defaultFavicon
    }

    fileprivate func setCellImage(_ cell: ThumbnailCell, iconUrl: URL, cacheWithUrl: URL) {
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
                            // avoid retrying to find an icon when none can be found, hack skips FaviconFetch
                            ImageCache.shared.cache(FaviconFetcher.defaultFavicon, url: cacheWithUrl, type: .square, callback: nil)
                            cell.imageView.image = FaviconFetcher.defaultFavicon
                            return
                        }
                        ImageCache.shared.cache(img, url: cacheWithUrl, type: .square, callback: nil)
                    })
                }
            }
        })
    }

    fileprivate func downloadFaviconsAndUpdateForUrl(_ url: URL, indexPath: IndexPath) {
        weak var weakSelf = self
        FaviconFetcher.getForURL(url).uponQueue(DispatchQueue.main) { result in
            guard let favicons = result.successValue, favicons.count > 0, let foundIconUrl = favicons.first?.url.asURL,
                let cell = weakSelf?.collection?.cellForItem(at: indexPath) as? ThumbnailCell else { return }
            self.setCellImage(cell, iconUrl: foundIconUrl, cacheWithUrl: url)
        }
    }

    private func extractDomainURL(_ url: String) -> String {
        return URL(string: url)?.normalizedHost ?? url
    }
}
