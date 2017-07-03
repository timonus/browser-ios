/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import WebKit
import SnapKit

import Shared

import XCGLogger

private let log = Logger.browserLogger

struct OpenInViewUX {
    static let ViewHeight: CGFloat = 40.0
    static let TextFont = UIFont.systemFont(ofSize: 16)
    static let TextColor = UIColor(red: 74.0/255.0, green: 144.0/255.0, blue: 226.0/255.0, alpha: 1.0)
    static let TextOffset = -15
    static let OpenInString = Strings.Open_in
}

enum FileType : String {
    case PDF = "pdf"
}

protocol OpenInHelper {
    var openInView: OpenInView { get }
    static func canOpen(_ url: URL) -> Bool
    func open()
}

struct OpenInHelperFactory {
    static func helperForURL(_ url: URL) -> OpenInHelper? {
        if OpenPdfInHelper.canOpen(url) {
            return OpenPdfInHelper(url: url)
        }

        return nil
    }
}

class OpenPdfInHelper: NSObject, OpenInHelper, UIDocumentInteractionControllerDelegate {
    fileprivate var url: URL
    fileprivate var docController: UIDocumentInteractionController? = nil
    fileprivate var openInURL: URL?

    lazy var openInView: OpenInView = getOpenInView(self)()

    init(url: URL) {
        self.url = url
        super.init()
    }

    deinit {
        guard let url = openInURL else { return }
        let fileManager = FileManager.default
        do {
            try fileManager.removeItem(at: url)
        } catch {
            log.error("failed to delete file at \(url): \(error)")
        }
    }
    
    static func canOpen(_ url: URL) -> Bool {
        // May need to filter empty strings
        let pathExtension = url.pathExtension
        return pathExtension == FileType.PDF.rawValue && UIApplication.shared.canOpenURL(URL(string: "itms-books:")!)
    }

    func getOpenInView() -> OpenInView {
        let overlayView = OpenInView()

        overlayView.openInButton.addTarget(self, action: #selector(OpenPdfInHelper.open), for: .touchUpInside)
        return overlayView
    }

    func createDocumentControllerForURL(_ url: URL) {
        docController = UIDocumentInteractionController(url: url)
        docController?.delegate = self
        self.openInURL = url
    }

    func createLocalCopyOfPDF() {
        let lastPathComponent = url.lastPathComponent
        if docController == nil{
            // if we already have a URL but no document controller, just create the document controller
            if let url = openInURL {
                createDocumentControllerForURL(url)
                return
            }
            let contentsOfFile = try? Data(contentsOf: url)
            let dirPath = URL(string: NSTemporaryDirectory())!.appendingPathComponent("pdfs")
            let filePath = dirPath.appendingPathComponent(lastPathComponent)
            let fileManager = FileManager.default
            do {
                try fileManager.createDirectory(atPath: dirPath.absoluteString, withIntermediateDirectories: true, attributes: nil)
                if fileManager.createFile(atPath: filePath.absoluteString, contents: contentsOfFile, attributes: nil) {
                    let openInURL = URL(fileURLWithPath: filePath.absoluteString)
                    createDocumentControllerForURL(openInURL)
                } else {
                    log.error("Unable to create local version of PDF file at \(filePath)")
                }
            } catch {
                log.error("Error on creating directory at \(dirPath)")
            }
        }
    }

    func open() {
        createLocalCopyOfPDF()
        guard let _parentView = self.openInView.superview, let docController = self.docController else { log.error("view doesn't have a superview so can't open anything"); return }
        // iBooks should be installed by default on all devices we care about, so regardless of whether or not there are other pdf-capable
        // apps on this device, if we can open in iBooks we can open this PDF
        // simulators do not have iBooks so the open in view will not work on the simulator
        if UIApplication.shared.canOpenURL(URL(string: "itms-books:")!) {
            log.info("iBooks installed: attempting to open pdf")
            docController.presentOpenInMenu(from: CGRect.zero, in: _parentView, animated: true)
        } else {
            log.info("iBooks is not installed")
        }
    }
}

class OpenInView: UIView {
    let openInButton = UIButton()

    init() {
        super.init(frame: CGRect.zero)
        openInButton.setTitleColor(OpenInViewUX.TextColor, for: .normal)
        openInButton.setTitle(OpenInViewUX.OpenInString, for: UIControlState.normal)
        openInButton.titleLabel?.font = OpenInViewUX.TextFont
        openInButton.sizeToFit()
        self.addSubview(openInButton)
        openInButton.snp_makeConstraints { make in
            make.centerY.equalTo(self)
            make.height.equalTo(self)
            make.trailing.equalTo(self).offset(OpenInViewUX.TextOffset)
        }
        self.backgroundColor = UIColor.white
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
