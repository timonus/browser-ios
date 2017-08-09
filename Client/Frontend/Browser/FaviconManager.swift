/* This Source Code Form is subject to the terms of the Mozilla Public
* License, v. 2.0. If a copy of the MPL was not distributed with this
* file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit
import Storage
import WebImage


class FaviconManager : BrowserHelper {
    let profile: Profile!
    weak var browser: Browser?

    init(browser: Browser, profile: Profile) {
        self.profile = profile
        self.browser = browser

        if let path = Bundle.main.path(forResource: "Favicons", ofType: "js") {
            if let source = try? NSString(contentsOfFile: path, encoding: String.Encoding.utf8.rawValue) as String {
                let userScript = WKUserScript(source: source, injectionTime: WKUserScriptInjectionTime.atDocumentEnd, forMainFrameOnly: true)
                browser.webView!.configuration.userContentController.addUserScript(userScript)
            }
        }
    }

    class func scriptMessageHandlerName() -> String? {
        return "faviconsMessageHandler"
    }

    func userContentController(_ userContentController: WKUserContentController, didReceiveScriptMessage message: WKScriptMessage) {
        let manager = SDWebImageManager.shared()
        guard let tab = browser else { return }
        tab.favicons.removeAll(keepingCapacity: false)

        // Result is in the form {'documentLocation' : document.location.href, 'http://icon url 1': "<type>", 'http://icon url 2': "<type" }
        guard let icons = message.body as? [String: String], let documentLocation = icons["documentLocation"] else { return }
        guard let currentUrl = URL(string: documentLocation) else { return }

        if documentLocation.contains(WebServer.sharedInstance.base) {
            return
        }

        let site = Site(url: documentLocation, title: "")
        var favicons = [Favicon]()
        for item in icons {
            if item.0 == "documentLocation" {
                continue
            }

            if let type = Int(item.1), let _ = URL(string: item.0), let iconType = IconType(rawValue: type) {
                let favicon = Favicon(url: item.0, date: Date(), type: iconType)
                favicons.append(favicon)
            }
        }


        let options = tab.isPrivate ? [SDWebImageOptions.lowPriority, SDWebImageOptions.cacheMemoryOnly] : [SDWebImageOptions.lowPriority]

        func downloadIcon(_ icon: Favicon) {
            if let iconUrl = URL(string: icon.url) {
                manager?.downloadImage(with: iconUrl, options: SDWebImageOptions(options), progress: nil, completed: { (img, err, cacheType, success, url) -> Void in
                    let fav = Favicon(url: url?.absoluteString ?? "",
                        date: NSDate() as Date,
                        type: icon.type)

                    let spotlight = tab.getHelper(SpotlightHelper.self)

                    if let img = img {
                        fav.width = Int(img.size.width)
                        fav.height = Int(img.size.height)
                    } else {
                        if favicons.count == 1 && favicons.first?.type == .guess {
                            // No favicon is indicated in the HTML
                            spotlight?.updateImage(forURL: url!)
                        }
                        downloadBestIcon()
                        return
                    }

                    if !tab.isPrivate {
                        FaviconMO.add(fav, forSiteUrl: currentUrl)
                        if tab.favicons.isEmpty {
                            spotlight?.updateImage(img, forURL: url!)
                        }
                    }
                    tab.favicons[currentUrl.normalizedHost ?? ""] = fav
                })
            }
        }

        func downloadBestIcon() {
            guard let best = getBestFavicon(favicons) else { return }
            favicons = favicons.filter { $0 != best }
            downloadIcon(best)
        }

        downloadBestIcon()
    }
}
