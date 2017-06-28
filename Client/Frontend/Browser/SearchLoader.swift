/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared
import Storage
import XCGLogger
import Deferred

private let log = Logger.browserLogger

private let URLBeforePathRegex = try! NSRegularExpression(pattern: "^https?://([^/]+)/", options: [])

// TODO: Swift currently requires that classes extending generic classes must also be generic.
// This is a workaround until that requirement is fixed.
typealias SearchLoader = _SearchLoader<AnyObject, AnyObject>

/**
 * Shared data source for the SearchViewController and the URLBar domain completion.
 * Since both of these use the same SQL query, we can perform the query once and dispatch the results.
 */
class _SearchLoader<UnusedA, UnusedB>: Loader<[Site], SearchViewController> {
    fileprivate let profile: Profile
    fileprivate let urlBar: URLBarView
    fileprivate var inProgress: Cancellable? = nil

    init(profile: Profile, urlBar: URLBarView) {
        self.profile = profile
        self.urlBar = urlBar
        super.init()
    }

    fileprivate lazy var topDomains: [String] = {
        let filePath = Bundle.main.path(forResource: "topdomains", ofType: "txt")
        return try! String(contentsOfFile: filePath!).components(separatedBy: "\n")
    }()

    // TODO: This is not a proper frecency query, it just gets sites from the past week
    fileprivate func getSitesByFrecency(_ containing: String? = nil) -> Deferred<[Site]> {
        let result = Deferred<[Site]>()

        let context = DataController.shared.workerContext()
        context.perform {
            
            let history: [WebsitePresentable] = History.frecencyQuery(context, containing: containing)
            let bookmarks: [WebsitePresentable] = Bookmark.frecencyQuery(context: context, containing: containing)
            
            // History must come before bookmarks, since later items replace existing ones, and want bookmarks to replace history entries
            let uniqueSites = Set<Site>( (history + bookmarks).map { Site(url: $0.url ?? "", title: $0.title ?? "", bookmarked: $0 is Bookmark) } )
            result.fill(Array(uniqueSites))
        }
        return result
    }

    var query: String = "" {
        didSet {
            if query.isEmpty {
                self.load([Site]())
                return
            }

            if let inProgress = inProgress {
                inProgress.cancel()
                self.inProgress = nil
            }

            let deferred = getSitesByFrecency(query)
            inProgress = deferred as? Cancellable

            deferred.uponQueue(DispatchQueue.main) { result in
                self.inProgress = nil

                // First, see if the query matches any URLs from the user's search history.
                self.load(result)
                for site in result {
                    if let completion = self.completionForURL(site.url) {
                        self.urlBar.setAutocompleteSuggestion(completion)
                        return
                    }
                }

                // If there are no search history matches, try matching one of the Alexa top domains.
                for domain in self.topDomains {
                    if let completion = self.completionForDomain(domain) {
                        self.urlBar.setAutocompleteSuggestion(completion)
                        return
                    }
                }
            }

        }
    }

    fileprivate func completionForURL(_ url: String) -> String? {
        // Extract the pre-path substring from the URL. This should be more efficient than parsing via
        // NSURL since we need to only look at the beginning of the string.
        // Note that we won't match non-HTTP(S) URLs.
        guard let match = URLBeforePathRegex.firstMatch(in: url, options: NSRegularExpression.MatchingOptions(), range: NSRange(location: 0, length: url.characters.count)) else {
            return nil
        }

        // If the pre-path component (including the scheme) starts with the query, just use it as is.
        let prePathURL = (url as NSString).substring(with: match.rangeAt(0))
        if prePathURL.startsWith(query) {
            return prePathURL
        }

        // Otherwise, find and use any matching domain.
        // To simplify the search, prepend a ".", and search the string for ".query".
        // For example, for http://en.m.wikipedia.org, domainWithDotPrefix will be ".en.m.wikipedia.org".
        // This allows us to use the "." as a separator, so we can match "en", "m", "wikipedia", and "org",
        let domain = (url as NSString).substring(with: match.rangeAt(1))
        return completionForDomain(domain)
    }

    fileprivate func completionForDomain(_ domain: String) -> String? {
        let domainWithDotPrefix: String = ".\(domain)"
        if let range = domainWithDotPrefix.range(of: ".\(query)", options: NSString.CompareOptions.caseInsensitive, range: nil, locale: nil) {
            // We don't actually want to match the top-level domain ("com", "org", etc.) by itself, so
            // so make sure the result includes at least one ".".
            
            // TODO: Fix
            let matchedDomain: String = "" // domainWithDotPrefix.substring(from: index(range.lowerBound, 1))
            if matchedDomain.contains(".") {
                return matchedDomain + "/"
            }
        }

        return nil
    }
}
