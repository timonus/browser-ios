/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation

class LegacyBackForwardListItem {

    var URL: Foundation.URL {
        didSet {
            checkForLocalWebserver()
        }
    }
    var initialURL: Foundation.URL
    var title:String = "" {
        didSet {
            checkForLocalWebserver()
        }
    }

    fileprivate func checkForLocalWebserver()  {
        if AboutUtils.isAboutURL(URL) && !title.isEmpty {
            title = ""
        }
    }

    init(url: Foundation.URL) {
        URL = url
        // In order to mimic the built-in API somewhat, the initial url is stripped of mobile site
        // parts of the host (mobile.nytimes.com -> initial url is nytimes.com). The initial url
        // is the pre-page-forwarding url
        let normal = url.scheme ?? "http" + "://" + (url.normalizedHostAndPath ?? url.absoluteString)
        initialURL = Foundation.URL(string: normal) ?? url
    }
}

extension LegacyBackForwardListItem: Equatable {}
func == (lhs: LegacyBackForwardListItem, rhs: LegacyBackForwardListItem) -> Bool {
    return lhs.URL.absoluteString == rhs.URL.absoluteString;
}


class WebViewBackForwardList {

    var currentIndex: Int = 0
    var backForwardList: [LegacyBackForwardListItem] = []
    weak var webView: BraveWebView?
    var cachedHistoryStringLength = 0
    var cachedHistoryStringPositionOfCurrentMarker = -1

    init(webView: BraveWebView) {
        self.webView = webView
    }


    fileprivate func isSpecial(_ _url: URL?) -> Bool {
        guard let url = _url else { return false }
        #if !TEST
            return url.absoluteString.range(of: WebServer.sharedInstance.base) != nil
        #else
            return false
        #endif
    }

    func update() {
        let currIndicator = ">>> "
        guard let obj = webView?.value(forKeyPath: "documentView.webView.backForwardList") else { return }
        let history = (obj as AnyObject).description ?? ""
        let nsHistory = history as! NSString
        
        if cachedHistoryStringLength > 0 && cachedHistoryStringLength == nsHistory.length &&
            cachedHistoryStringPositionOfCurrentMarker > -1 &&
            nsHistory.substring(with: NSMakeRange(cachedHistoryStringPositionOfCurrentMarker, currIndicator.characters.count)) == currIndicator {
            // the history is unchanged (based on this guesstimate)
            return
        }

        cachedHistoryStringLength = nsHistory.length

        backForwardList = []

        let regex = try! NSRegularExpression(pattern:"\\d+\\) +<WebHistoryItem.+> (http.+) ", options: [])
        let result = regex.matches(in: history, options: [], range: NSMakeRange(0, (history.characters.count)))
        var i = 0
        var foundCurrent = false
        for match in result {
            var extractedUrl = nsHistory.substring(with: match.rangeAt(1))
            let parts = extractedUrl.components(separatedBy: " ")
            if parts.count > 1 {
                extractedUrl = parts[0]
            }
            guard let url = URL(string: extractedUrl) else { continue }
            let item = LegacyBackForwardListItem(url: url)
            backForwardList.append(item)

            let rangeStart = match.range.location - currIndicator.characters.count
            if rangeStart > -1 && nsHistory.substring(with: NSMakeRange(rangeStart, currIndicator.characters.count)) == currIndicator {
                currentIndex = i
                foundCurrent = true
                cachedHistoryStringPositionOfCurrentMarker = rangeStart
            }
            i += 1
        }
        if !foundCurrent {
            currentIndex = 0
        }
    }

    var currentItem: LegacyBackForwardListItem? {
        get {
            guard let item = itemAtIndex(currentIndex) else {
                if let url = webView?.URL {
                    let item = LegacyBackForwardListItem(url: url as URL)
                    return item
                } else {
                    return nil
                }
            }
            return item

        }}

    var backItem: LegacyBackForwardListItem? {
        get {
            return itemAtIndex(currentIndex - 1)
        }}

    var forwardItem: LegacyBackForwardListItem? {
        get {
            return itemAtIndex(currentIndex + 1)
        }}

    func itemAtIndex(_ index: Int) -> LegacyBackForwardListItem? {
        if (backForwardList.count == 0 ||
            index > backForwardList.count - 1 ||
            index < 0) {
            return nil
        }
        return backForwardList[index]
    }

    var backList: [LegacyBackForwardListItem] {
        get {
            return (currentIndex > 0 && backForwardList.count > 0) ? Array(backForwardList[0..<currentIndex]) : []
        }}

    var forwardList: [LegacyBackForwardListItem] {
        get {
            return (currentIndex + 1 < backForwardList.count  && backForwardList.count > 0) ?
                Array(backForwardList[(currentIndex + 1)..<backForwardList.count]) : []
        }}
}
