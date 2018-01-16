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

struct FavoritesTileDecorator {
    let url: URL
    let normalizedHost: String
    let cell: ThumbnailCell

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

    init(url: URL, cell: ThumbnailCell) {
        self.url = url
        self.cell = cell
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
            break
        }
    }

    private func setDefaultTile() {
        cell.imageView.image = FaviconFetcher.defaultFavicon
    }

    private func extractDomainURL(_ url: String) -> String {
        return URL(string: url)?.normalizedHost ?? url
    }
}
