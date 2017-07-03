/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared
private let log = Logger.browserLogger

extension BrowserViewController: WKCompatNavigationDelegate {

    func webViewDidStartProvisionalNavigation(_ webView: UIWebView, url: URL?) {
        #if !BRAVE
            if tabManager.selectedTab?.webView !== webView {
                return
            }
        #else
            // remove the open in overlay view if it is present
            removeOpenInView()
        #endif
        updateFindInPageVisibility(false)

        // If we are going to navigate to a new page, hide the reader mode button. Unless we
        // are going to a about:reader page. Then we keep it on screen: it will change status
        // (orange color) as soon as the page has loaded.
        if let url = tabManager.tabForWebView(webView)?.url {
            if !ReaderModeUtils.isReaderModeURL(url) {
                urlBar.updateReaderModeState(ReaderModeState.Unavailable)
                hideReaderModeBar(animated: false)
            }

        }
    }

    // Recognize an Apple Maps URL. This will trigger the native app. But only if a search query is present. Otherwise
    // it could just be a visit to a regular page on maps.apple.com.
    fileprivate func isAppleMapsURL(_ url: URL) -> Bool {
        if url.scheme == "http" || url.scheme == "https" {
            if url.host == "maps.apple.com" && url.query != nil {
                return true
            }
        }
        return false
    }

    // Recognize a iTunes Store URL. These all trigger the native apps. Note that appstore.com and phobos.apple.com
    // used to be in this list. I have removed them because they now redirect to itunes.apple.com. If we special case
    // them then iOS will actually first open Safari, which then redirects to the app store. This works but it will
    // leave a 'Back to Safari' button in the status bar, which we do not want.
    fileprivate func isStoreURL(_ url: URL) -> Bool {
        if url.scheme == "http" || url.scheme == "https" {
            if url.host == "itunes.apple.com" {
                return true
            }
        }
        return false
    }

    // This is the place where we decide what to do with a new navigation action. There are a number of special schemes
    // and http(s) urls that need to be handled in a different way. All the logic for that is inside this delegate
    // method.
    func webViewDecidePolicyForNavigationAction(_ webView: UIWebView, url: URL?, shouldLoad: inout Bool) {
        guard let url = url else { return }
        // Fixes 1261457 - Rich text editor fails because requests to about:blank are blocked
        if url.scheme == "about" && (url as NSURL).resourceSpecifier == "blank" {
            return
        }

        // First special case are some schemes that are about Calling. We prompt the user to confirm this action. This
        // gives us the exact same behaviour as Safari. The only thing we do not do is nicely format the phone number,
        // instead we present it as it was put in the URL.

        if url.scheme == "tel" || url.scheme == "facetime" || url.scheme == "facetime-audio" {
            if let phoneNumber = (url as NSURL).resourceSpecifier?.removingPercentEncoding {
                let alert = UIAlertController(title: phoneNumber, message: nil, preferredStyle: UIAlertControllerStyle.alert)
                alert.addAction(UIAlertAction(title: Strings.Cancel, style: UIAlertActionStyle.cancel, handler: nil))
                alert.addAction(UIAlertAction(title: Strings.Call, style: UIAlertActionStyle.default, handler: { (action: UIAlertAction!) in
                    UIApplication.shared.openURL(url)
                }))
                present(alert, animated: true, completion: nil)
            }
            shouldLoad = false
            return
        }

        // Second special case are a set of URLs that look like regular http links, but should be handed over to iOS
        // instead of being loaded in the webview. Note that there is no point in calling canOpenURL() here, because
        // iOS will always say yes. TODO Is this the same as isWhitelisted?

        if isAppleMapsURL(url) {
            UIApplication.shared.openURL(url)
            shouldLoad = false
            return
        }


        if let tab = tabManager.selectedTab, isStoreURL(url) {
            struct StaticTag {
                static let tag = (UUID() as NSUUID).hash
            }
            let hasOneAlready = tab.bars.contains(where: { $0.tag == StaticTag.tag })
            if hasOneAlready ?? false {
                return
            }

            let siteName = tab.displayURL?.hostWithGenericSubdomainPrefixRemoved() ?? "this site"
            // TODO: not sure why snack bar fully left-aligns, looks better with a bit of space from left
            let msg = NSAttributedString(string: "  " + String(format: Strings.AllowOpenITunes_template, siteName))

            let snackBar = TimerSnackBar(attrText: msg,
                                         img: nil,
                                         buttons: [
                                            SnackButton(title: "Open", accessibilityIdentifier: "", callback: { bar in
                                                self.tabManager.selectedTab?.removeSnackbar(bar)
                                                UIApplication.shared.openURL(url)
                                            }),
                                            SnackButton(title: "Not now", accessibilityIdentifier: "", callback: { bar in
                                                self.tabManager.selectedTab?.removeSnackbar(bar)
                                            })
                ])
            snackBar.tag = StaticTag.tag
            tabManager.selectedTab?.addSnackbar(snackBar)
            return
        }


        // This is the normal case, opening a http or https url, which we handle by loading them in this WKWebView. We
        // always allow this.
        if url.scheme == "http" || url.scheme == "https" {
            #if !BRAVE
                if navigationAction.navigationType == .LinkActivated {
                    resetSpoofedUserAgentIfRequired(webView, newURL: url)
                } else if navigationAction.navigationType == .BackForward {
                    restoreSpoofedUserAgentIfRequired(webView, newRequest: navigationAction.request)
                }
            #endif
            return
        }

        // Default to calling openURL(). What this does depends on the iOS version. On iOS 8, it will just work without
        // prompting. On iOS9, depending on the scheme, iOS will prompt: "Firefox" wants to open "Twitter". It will ask
        // every time. There is no way around this prompt. (TODO Confirm this is true by adding them to the Info.plist)

        UIApplication.shared.openURL(url)
        shouldLoad = false
    }

    func webViewDidFinishNavigation(_ webView: UIWebView, url: URL?) {
        // BraveWebView handles this
    }

    func addOpenInViewIfNeccessary(_ url: URL?) {
        guard let url = url, let openInHelper = OpenInHelperFactory.helperForURL(url) else { return }
        let view = openInHelper.openInView
        webViewContainerToolbar.addSubview(view)
        webViewContainerToolbar.snp_updateConstraints { make in
            make.height.equalTo(OpenInViewUX.ViewHeight)
        }
        view.snp_makeConstraints { make in
            make.edges.equalTo(webViewContainerToolbar)
        }

        self.openInHelper = openInHelper
    }

    func removeOpenInView() {
        guard let _ = self.openInHelper else { return }
        webViewContainerToolbar.subviews.forEach { $0.removeFromSuperview() }

        webViewContainerToolbar.snp_updateConstraints { make in
            make.height.equalTo(0)
        }

        self.openInHelper = nil
    }

    func updateProfileForLocationChange(_ tab: Browser) {
        guard let title = tab.title, let historyUrl = tab.displayURL else { return }
        if tab.isPrivate {
            return
        }

        History.add(title, url: historyUrl)
        //history.setTopSitesNeedsInvalidation()
    }


    func webViewDidFailNavigation(_ webView: UIWebView, withError error: NSError) {
        // Ignore the "Frame load interrupted" error that is triggered when we cancel a request
        // to open an external application and hand it over to UIApplication.openURL(). The result
        // will be that we switch to the external app, for example the app store, while keeping the
        // original web page in the tab instead of replacing it with an error page.
        if error.domain == "WebKitErrorDomain" && error.code == 102 {
            return
        }

        if error.code == Int(CFNetworkErrors.cfurlErrorCancelled.rawValue) {
            if let tab = tabManager.tabForWebView(webView), tab === tabManager.selectedTab {
                urlBar.currentURL = tab.displayURL
            }
            return
        }

        if let url = error.userInfo[NSURLErrorFailingURLErrorKey] as? URL {
            ErrorPageHelper().showPage(error, forUrl: url, inWebView: webView)
        }
    }

}
