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
            
            let photoAuthorizeStatus = PHPhotoLibrary.authorizationStatus()
            let saveImageTitle = Strings.Save_Image
            let saveImageAction = UIAlertAction(title: saveImageTitle, style: UIAlertActionStyle.default) { (action: UIAlertAction) -> Void in
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
            actionSheetController.addAction(saveImageAction)
            
            let copyImageTitle = Strings.Copy_Image
            let copyAction = UIAlertAction(title: copyImageTitle, style: UIAlertActionStyle.default) { (action: UIAlertAction) -> Void in
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
            actionSheetController.addAction(copyAction)
        }
        
        if let url = elements.link, let currentTab = tabManager.selectedTab {
            dialogTitle = url.absoluteString.regexReplacePattern("^mailto:", with: "")
            let isPrivate = currentTab.isPrivate
            let newTabTitle = Strings.Open_In_Background_Tab
            let openNewTabAction =  UIAlertAction(title: newTabTitle, style: UIAlertActionStyle.default) { (action: UIAlertAction) in
                actionSheetController.view.tag = 0 // BRAVE: clear this to allow navigation
                debugPrint(String(describing: self.tabManager.currentIndex?.advanced(by: 1)))
                _ = self.tabManager.addTab(NSURLRequest(url: url) as URLRequest, index: self.tabManager.currentIndex?.advanced(by: 1))
            }
            actionSheetController.addAction(openNewTabAction)

            if !isPrivate {
                // Only show this option if not in private mode, otherwise, new tab just opens in private mode (since that is the current mode)
                let openNewPrivateTabTitle = Strings.Open_In_New_Private_Tab
                let openNewPrivateTabAction =  UIAlertAction(title: openNewPrivateTabTitle, style: UIAlertActionStyle.default) { (action: UIAlertAction) in
                    self.switchBrowsingMode(toPrivate: true, request: URLRequest(url: url))
                }
                actionSheetController.addAction(openNewPrivateTabAction)
            }
        }

        if let url = elements.image {
            let openImageTitle = Strings.Open_Image_In_Background_Tab
            let openImageAction = UIAlertAction(title: openImageTitle, style: UIAlertActionStyle.default) { (action: UIAlertAction) in
                _ = self.tabManager.addTab(URLRequest(url: url), index: self.tabManager.currentIndex?.advanced(by: 1))
            }
            actionSheetController.addAction(openImageAction)
        }
        
        if let url = elements.link, let currentTab = tabManager.selectedTab {
            let copyTitle = Strings.Copy_Link
            let copyAction = UIAlertAction(title: copyTitle, style: UIAlertActionStyle.default) { (action: UIAlertAction) -> Void in
                let pasteBoard = UIPasteboard.general
                if let dialogTitle = dialogTitle, let url = URL(string: dialogTitle) {
                    pasteBoard.url = url
                }
            }
            actionSheetController.addAction(copyAction)
            
            let shareTitle = Strings.Share_Link
            let shareAction = UIAlertAction(title: shareTitle, style: UIAlertActionStyle.default) { _ in
                self.presentActivityViewController(url, tab: currentTab, sourceView: self.view, sourceRect: CGRect(origin: touchPoint, size: touchSize), arrowDirection: .any)
            }
            actionSheetController.addAction(shareAction)
        }
        
        if let folder = elements.folder, let bookmarks = Bookmark.getChildren(forFolderUUID: folder, context: DataController.shared.mainThreadContext) {
            let openTitle = String(format: Strings.Open_All_Bookmarks, bookmarks.count)
            let copyAction = UIAlertAction(title: openTitle, style: UIAlertActionStyle.default) { (action: UIAlertAction) -> Void in
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
                            getApp().tabManager.addTab(request, zombie: true, id: tabID, createWebview: false)
                        }
                    }
                    DataController.saveContext(context: context)
                }
            }
            actionSheetController.addAction(copyAction)
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
