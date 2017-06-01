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
            if touchPoint == CGPointZero && UIDevice.currentDevice().userInterfaceIdiom == UIUserInterfaceIdiom.Pad {
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

        if let url = elements.link, let currentTab = tabManager.selectedTab {
            dialogTitle = url.absoluteString.regexReplacePattern("^mailto:", with: "")
            let isPrivate = currentTab.isPrivate
            let newTabTitle = Strings.Open_In_Background_Tab
            let openNewTabAction =  UIAlertAction(title: newTabTitle, style: UIAlertActionStyle.Default) { (action: UIAlertAction) in
                actionSheetController.view.tag = 0 // BRAVE: clear this to allow navigation
                self.scrollController.showToolbars(animated: !self.scrollController.toolbarsShowing, completion: { _ in
                    self.tabManager.addTab(NSURLRequest(URL: url))
                })
            }
            actionSheetController.addAction(openNewTabAction)

            if !isPrivate {
                // Only show this option if not in private mode, otherwise, new tab just opens in private mode (since that is the current mode)
                let openNewPrivateTabTitle = Strings.Open_In_New_Private_Tab
                let openNewPrivateTabAction =  UIAlertAction(title: openNewPrivateTabTitle, style: UIAlertActionStyle.Default) { (action: UIAlertAction) in
                    self.scrollController.showToolbars(animated: !self.scrollController.toolbarsShowing, completion: { _ in
                        self.switchBrowsingMode(toPrivate: true, request: URLRequest(URL: url))
                    })
                }
                actionSheetController.addAction(openNewPrivateTabAction)
            }

            let copyTitle = Strings.Copy_Link
            let copyAction = UIAlertAction(title: copyTitle, style: UIAlertActionStyle.Default) { (action: UIAlertAction) -> Void in
                let pasteBoard = UIPasteboard.generalPasteboard()
                if let dialogTitle = dialogTitle, let url = NSURL(string: dialogTitle) {
                    pasteBoard.URL = url
                }
            }
            actionSheetController.addAction(copyAction)

            let shareTitle = Strings.Share_Link
            let shareAction = UIAlertAction(title: shareTitle, style: UIAlertActionStyle.Default) { _ in
                self.presentActivityViewController(url, tab: currentTab, sourceView: self.view, sourceRect: CGRect(origin: touchPoint, size: touchSize), arrowDirection: .Any)
            }
            actionSheetController.addAction(shareAction)
        }

        if let url = elements.image {
            if dialogTitle == nil {
                dialogTitle = url.absoluteString
            }
            let openImageTitle = Strings.Open_Image_In_Background_Tab
            let openImageAction = UIAlertAction(title: openImageTitle, style: UIAlertActionStyle.Default) { (action: UIAlertAction) in
                self.scrollController.showToolbars(animated: !self.scrollController.toolbarsShowing, completion: { _ in
                    self.tabManager.addTab(URLRequest(URL: url))
                })
            }
            actionSheetController.addAction(openImageAction)

            let photoAuthorizeStatus = PHPhotoLibrary.authorizationStatus()
            let saveImageTitle = Strings.Save_Image
            let saveImageAction = UIAlertAction(title: saveImageTitle, style: UIAlertActionStyle.Default) { (action: UIAlertAction) -> Void in
                if photoAuthorizeStatus == PHAuthorizationStatus.Authorized || photoAuthorizeStatus == PHAuthorizationStatus.NotDetermined {
                    self.getImage(url) { UIImageWriteToSavedPhotosAlbum($0, nil, nil, nil) }
                } else {
                    let accessDenied = UIAlertController(title: Strings.Brave_would_like_to_access_your_photos, message: Strings.This_allows_you_to_save_the_image_to_your_CameraRoll, preferredStyle: UIAlertControllerStyle.Alert)
                    let dismissAction = UIAlertAction(title: Strings.Cancel, style: UIAlertActionStyle.Default, handler: nil)
                    accessDenied.addAction(dismissAction)
                    let settingsAction = UIAlertAction(title: Strings.Open_Settings, style: UIAlertActionStyle.Default ) { (action: UIAlertAction!) -> Void in
                        UIApplication.sharedApplication().openURL(NSURL(string: UIApplicationOpenSettingsURLString)!)
                    }
                    accessDenied.addAction(settingsAction)
                    self.presentViewController(accessDenied, animated: true, completion: nil)
                }
            }
            actionSheetController.addAction(saveImageAction)

            let copyImageTitle = Strings.Copy_Image
            let copyAction = UIAlertAction(title: copyImageTitle, style: UIAlertActionStyle.Default) { (action: UIAlertAction) -> Void in
                // put the actual image on the clipboard
                // do this asynchronously just in case we're in a low bandwidth situation
                let pasteboard = UIPasteboard.generalPasteboard()
                pasteboard.URL = url
                let changeCount = pasteboard.changeCount
                let application = UIApplication.sharedApplication()
                var taskId: UIBackgroundTaskIdentifier = 0
                taskId = application.beginBackgroundTaskWithExpirationHandler { _ in
                    application.endBackgroundTask(taskId)
                }

                Alamofire.request(.GET, url)
                    .validate(statusCode: 200..<300)
                    .response { responseRequest, responseResponse, responseData, responseError in
                        // Only set the image onto the pasteboard if the pasteboard hasn't changed since
                        // fetching the image; otherwise, in low-bandwidth situations,
                        // we might be overwriting something that the user has subsequently added.
                        if changeCount == pasteboard.changeCount, let imageData = responseData, responseError == nil {
                            pasteboard.addImageWithData(imageData, forURL: url)
                        }

                        application.endBackgroundTask(taskId)
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
        let cancelAction = UIAlertAction(title: Strings.Cancel, style: UIAlertActionStyle.Cancel, handler: nil)
        actionSheetController.addAction(cancelAction)
        self.present(actionSheetController, animated: true, completion: nil)
    }

    fileprivate func getImage(_ url: URL, success: @escaping (UIImage) -> ()) {
        Alamofire.request(.GET, url)
            .validate(statusCode: 200..<300)
            .response { _, _, data, _ in
                if let data = data,
                    let image = UIImage.dataIsGIF(data) ? UIImage.imageFromGIFDataThreadSafe(data) : UIImage.imageFromDataThreadSafe(data) {
                    success(image)
                }
        }
    }
}
