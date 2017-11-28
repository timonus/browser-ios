/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Shared
import Photos
import Alamofire

private let log = Logger.browserLogger

private let ActionSheetTitleMaxLength = 120

extension BrowserViewController: ContextMenuHelperDelegate {
    func contextMenuHelper(_ contextMenuHelper: ContextMenuHelper, didLongPressElements elements: ContextMenuHelper.Elements, gestureRecognizer: UILongPressGestureRecognizer) {
        // locationInView can return (0, 0) when the long press is triggered in an invalid page
        // state (e.g., long pressing a link before the document changes, then releasing after a
        // different page loads).
        let touchPoint = gestureRecognizer.location(in: view)
        #if BRAVE
            if urlBar.inSearchMode {
                return
            }
            if touchPoint == CGPoint.zero && UIDevice.current.userInterfaceIdiom == UIUserInterfaceIdiom.pad {
                print("zero touchpoint for context menu: \(elements)")
                return
            }
        #endif
        showContextMenu(elements, touchPoint: touchPoint)
    }

    func showContextMenu(_ elements: ContextMenuHelper.Elements, touchPoint: CGPoint) {
        let touchSize = CGSize(width: 0, height: 16)

        let actionSheetController = UIAlertController(title: nil, message: nil, preferredStyle: UIAlertControllerStyle.actionSheet)
        var dialogTitle: String?
        actionSheetController.view.tag = BraveWebViewConstants.kContextMenuBlockNavigation

        if let url = elements.image {
            if dialogTitle == nil {
                dialogTitle = url.absoluteString
            }
            
            let saveImageAction = createSaveImageAction(from: url)
            actionSheetController.addAction(saveImageAction)
            
            let copyAction = createCopyImageAction(from: url)
            actionSheetController.addAction(copyAction)
        }
        
        if let imageUrl = elements.image, let currentTab = tabManager.selectedTab {
            let shareImageAction = createShareImageAction(from: imageUrl,
                                                          tab: currentTab,
                                                          origin: touchPoint,
                                                          size: touchSize)
            actionSheetController.addAction(shareImageAction)
        }
        
        if let url = elements.link, let currentTab = tabManager.selectedTab {
            dialogTitle = url.absoluteString.regexReplacePattern("^mailto:", with: "")
            let openNewTabAction = createOpenNewTabAction(from: url,
                                                          tab: currentTab,
                                                          using: actionSheetController)
            actionSheetController.addAction(openNewTabAction)

            if !currentTab.isPrivate {
                let openNewPrivateTabAction = createOpenNewPrivateTabAction(from: url)
                actionSheetController.addAction(openNewPrivateTabAction)
            }
        }

        if let url = elements.image {
            let openImageAction = createOpenImageAction(from: url)
            actionSheetController.addAction(openImageAction)
        }
        
        if let url = elements.link, let currentTab = tabManager.selectedTab {
            let copyAction = createCopyAction(from: url, title: dialogTitle)
            actionSheetController.addAction(copyAction)
            
            let shareAction = createShareLinkAction(from: url, tab: currentTab, origin: touchPoint, size: touchSize)
            actionSheetController.addAction(shareAction)
        }
        
        if let openAllBookmarksAction = createOpenAllBookmarksAction(using: elements) {
            actionSheetController.addAction(openAllBookmarksAction)
        }

        // If we're showing an arrow popup, set the anchor to the long press location.
        if let popoverPresentationController = actionSheetController.popoverPresentationController {
            popoverPresentationController.sourceView = view
            popoverPresentationController.sourceRect = CGRect(origin: touchPoint, size: touchSize)
            popoverPresentationController.permittedArrowDirections = .any
        }

        actionSheetController.title = dialogTitle?.ellipsize(maxLength: ActionSheetTitleMaxLength)
        let cancelAction = UIAlertAction(title: Strings.Cancel, style: UIAlertActionStyle.cancel, handler: nil)
        actionSheetController.addAction(cancelAction)
        self.present(actionSheetController, animated: true, completion: nil)
    }

    private func createShareImageAction(from url: URL, tab: Browser?, origin: CGPoint, size: CGSize) -> UIAlertAction {
        return UIAlertAction(title: Strings.Share_Image, style: UIAlertActionStyle.default) {
            [weak self] action in
            guard let browserController = self else { return }
            browserController.getImage(url) {
                image in
                let controller = UIActivityViewController(activityItems: [image], applicationActivities: nil)
                browserController.presentActivityViewController(controller: controller,
                                                                tab: tab,
                                                                sourceView: browserController.view,
                                                                sourceRect: CGRect(origin: origin, size: size),
                                                                arrowDirection: .any)
            }
        }
    }
    
    private func createSaveImageAction(from url: URL) -> UIAlertAction {
        let photoAuthorizeStatus = PHPhotoLibrary.authorizationStatus()
        let saveImageTitle = Strings.Save_Image
        return UIAlertAction(title: saveImageTitle, style: UIAlertActionStyle.default) { (action: UIAlertAction) -> Void in
            if photoAuthorizeStatus == PHAuthorizationStatus.authorized || photoAuthorizeStatus == PHAuthorizationStatus.notDetermined {
                self.getImage(url) { UIImageWriteToSavedPhotosAlbum($0, nil, nil, nil) }
            } else {
                let accessDenied = UIAlertController(title: Strings.Brave_would_like_to_access_your_photos, message: Strings.This_allows_you_to_save_the_image_to_your_CameraRoll, preferredStyle: UIAlertControllerStyle.alert)
                let dismissAction = UIAlertAction(title: Strings.Cancel, style: UIAlertActionStyle.default, handler: nil)
                accessDenied.addAction(dismissAction)
                let settingsAction = UIAlertAction(title: Strings.Open_Settings, style: UIAlertActionStyle.default ) { (action: UIAlertAction!) -> Void in
                    UIApplication.shared.openURL(NSURL(string: UIApplicationOpenSettingsURLString)! as URL)
                }
                accessDenied.addAction(settingsAction)
                self.present(accessDenied, animated: true, completion: nil)
            }
        }
    }
    
    private func createCopyImageAction(from url: URL) -> UIAlertAction {
        let copyImageTitle = Strings.Copy_Image
        return UIAlertAction(title: copyImageTitle, style: UIAlertActionStyle.default) { (action: UIAlertAction) -> Void in
            // put the actual image on the clipboard
            // do this asynchronously just in case we're in a low bandwidth situation
            let pasteboard = UIPasteboard.general
            pasteboard.url = url
            let changeCount = pasteboard.changeCount
            let application = UIApplication.shared
            var taskId: UIBackgroundTaskIdentifier = 0
            taskId = application.beginBackgroundTask (expirationHandler: { _ in
                application.endBackgroundTask(taskId)
            })
            
            Alamofire.request(url)
                .validate(statusCode: 200..<300)
                .response { response in
                    // Only set the image onto the pasteboard if the pasteboard hasn't changed since
                    // fetching the image; otherwise, in low-bandwidth situations,
                    // we might be overwriting something that the user has subsequently added.
                    if changeCount == pasteboard.changeCount, let imageData = response.data, response.error == nil {
                        pasteboard.addImageWithData(imageData, forURL: url)
                    }
                    
                    application.endBackgroundTask(taskId)
            }
        }
    }
    
    private func createOpenNewTabAction(from url: URL, tab: Browser, using alertController: UIAlertController) -> UIAlertAction {
        let newTabTitle = Strings.Open_In_Background_Tab
        return UIAlertAction(title: newTabTitle, style: UIAlertActionStyle.default) {
            [weak alertController] (action: UIAlertAction) in
            alertController?.view.tag = 0 // BRAVE: clear this to allow navigation
            if self.tabManager.tabCount == 1 { getApp().browserViewController.scrollController.showToolbars(animated: true)}
            _ = self.tabManager.addTab(NSURLRequest(url: url) as URLRequest, index: self.tabManager.currentIndex?.advanced(by: 1))
        }
    }
    
    private func createOpenNewPrivateTabAction(from url: URL) -> UIAlertAction {
        let openNewPrivateTabTitle = Strings.Open_In_New_Private_Tab
        return UIAlertAction(title: openNewPrivateTabTitle, style: UIAlertActionStyle.default) { (action: UIAlertAction) in
            self.switchBrowsingMode(toPrivate: true, request: URLRequest(url: url))
        }
    }
    
    private func createOpenImageAction(from url: URL) -> UIAlertAction {
        let openImageTitle = Strings.Open_Image_In_Background_Tab
        return UIAlertAction(title: openImageTitle, style: UIAlertActionStyle.default) {
            (action: UIAlertAction) in
            if self.tabManager.tabCount == 1 { getApp().browserViewController.scrollController.showToolbars(animated: true)}
            _ = self.tabManager.addTab(URLRequest(url: url), index:
                self.tabManager.currentIndex?.advanced(by: 1))
        }
    }
    
    private func createCopyAction(from url: URL, title: String?) -> UIAlertAction {
        let copyTitle = Strings.Copy_Link
        return UIAlertAction(title: copyTitle, style: UIAlertActionStyle.default) { (action: UIAlertAction) -> Void in
            let pasteBoard = UIPasteboard.general
            if let dialogTitle = title, let url = URL(string: dialogTitle) {
                pasteBoard.url = url
            }
        }
    }
    
    private func createShareLinkAction(from url: URL, tab: Browser, origin: CGPoint, size: CGSize) -> UIAlertAction {
        var tab: Browser? = tab
        let shareTitle = Strings.Share_Link
        return UIAlertAction(title: shareTitle, style: UIAlertActionStyle.default) { _ in
            if url != tab?.url {
                // If user selects to share url from long-press (not current page), no tab data should be appended to the share action
                // (e.g. tab url, tab title)
                tab = nil
            }
            
            self.presentActivityViewController(url, tab: tab, sourceView: self.view, sourceRect: CGRect(origin: origin, size: size), arrowDirection: .any)
        }
    }
    
    private func createOpenAllBookmarksAction(using elements: ContextMenuHelper.Elements) -> UIAlertAction? {
        guard let folder = elements.folder, let bookmarks = Bookmark.getChildren(forFolderUUID: folder, ignoreFolders: true, context: DataController.shared.mainThreadContext) else {
            return nil
        }
        let openTitle = String(format: Strings.Open_All_Bookmarks, bookmarks.count)
        return UIAlertAction(title: openTitle, style: UIAlertActionStyle.default) { (action: UIAlertAction) -> Void in
            let context = DataController.shared.workerContext
            context.perform {
                for bookmark in bookmarks {
                    guard let urlString = bookmark.url else { continue }
                    guard let url = URL(string: urlString) else { continue }
                    guard let tabID = TabMO.freshTab().syncUUID else { continue }
                    let data = SavedTab(id: tabID, title: urlString, url: url.absoluteString, isSelected: false, order: -1, screenshot: nil, history: [url.absoluteString], historyIndex: 0)
                    TabMO.add(data)
                    
                    postAsyncToMain {
                        let request = URLRequest(url: url)
                        getApp().tabManager.addTab(request, zombie: true, id: tabID, createWebview: (bookmarks.count == 1))
                    }
                }
                DataController.saveContext(context: context)
            }
        }
    }
    
    fileprivate func getImage(_ url: URL, success: @escaping (UIImage) -> ()) {
        Alamofire.request(url)
            .validate(statusCode: 200..<300)
            .response { response in
                if let data = response.data,
                    let image = UIImage.dataIsGIF(data) ? UIImage.imageFromGIFDataThreadSafe(data) : UIImage.imageFromDataThreadSafe(data) {
                    success(image)
                }
        }
    }
}
