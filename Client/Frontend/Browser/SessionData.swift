/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

import Shared
import Storage

class SessionData: NSObject, NSCoding {
    let currentPage: Int
    let urls: [URL]
    let lastUsedTime: Timestamp
    var currentTitle: String = ""
    var currentFavicon: Favicon?

    var jsonDictionary: [String: Any] {
        return [
            "currentPage": String(self.currentPage),
            "lastUsedTime": String(self.lastUsedTime),
            "urls": urls.map { $0.absoluteString }
        ]
    }
    
    // This is not a fully direct mapping, but rather an attempt to reconcile data differences, primarily used for tab restoration
    var savedTabData: SavedTab {
        // (id: String, title: String, url: String, isSelected: Bool, order: Int16, screenshot: UIImage?, history: [String], historyIndex: Int16)
        let urlStrings = urls.map { $0.absoluteString }
        let currentURL = urlStrings[currentPage] ?? ""
        return ("InvalidId", currentTitle, currentURL, false, -1, nil, urlStrings, Int16(currentPage))
    }

    /**
        Creates a new SessionData object representing a serialized tab.

        - parameter currentPage:     The active page index. Must be in the range of (-N, 0],
                                where 1-N is the first page in history, and 0 is the last.
        - parameter urls:            The sequence of URLs in this tab's session history.
        - parameter lastUsedTime:    The last time this tab was modified.
    **/
    init(currentPage: Int, currentTitle: String?, currentFavicon: Favicon?, urls: [URL], lastUsedTime: Timestamp) {
        self.currentPage = currentPage
        self.urls = urls
        self.lastUsedTime = lastUsedTime
        self.currentTitle = currentTitle ?? ""
        self.currentFavicon = currentFavicon

        assert(urls.count > 0, "Session has at least one entry")
        assert(currentPage > -urls.count && currentPage <= 0, "Session index is valid")
    }

    required init?(coder: NSCoder) {
        self.currentPage = coder.decodeObject(forKey: "currentPage") as? Int ?? 0
        self.urls = coder.decodeObject(forKey: "urls") as? [URL] ?? []
        self.lastUsedTime = UInt64(coder.decodeInt64(forKey: "lastUsedTime")) ?? Date.now()
        self.currentTitle = coder.decodeObject(forKey: "currentTitle") as? String ?? ""
        self.currentFavicon = coder.decodeObject(forKey: "currentFavicon") as? Favicon
    }

    func encode(with coder: NSCoder) {
        coder.encode(currentPage, forKey: "currentPage")
        coder.encode(urls, forKey: "urls")
        coder.encode(Int64(lastUsedTime), forKey: "lastUsedTime")
        coder.encode(currentTitle, forKey: "currentTitle")
        coder.encode(currentFavicon, forKey: "currentFavicon")
    }
}
