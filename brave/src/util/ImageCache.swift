/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import FastImageCache
import CoreGraphics

class ImageEntity: NSObject, FICEntity {
    var uuid: String?
    var url: URL?
    
    required init(url: URL) {
        super.init()
        self.url = url
    }
    
    var fic_UUID: String {
        get {
            if uuid == nil, let urlString = self.url?.absoluteString {
                let uuidBytes = FICUUIDBytesFromMD5HashOfString(urlString.lowercased())
                uuid = FICStringWithUUIDBytes(uuidBytes)
            }
            return uuid ?? UUID().uuidString
        }
    }
    
    var fic_sourceImageUUID: String {
        get {
            return uuid ?? UUID().uuidString
        }
    }
    
    func fic_sourceImageURL(withFormatName formatName: String) -> URL? {
        return url
    }
    
    func fic_drawingBlock(for image: UIImage, withFormatName formatName: String) -> FICEntityImageDrawingBlock? {
        let drawingBlock: FICEntityImageDrawingBlock = { (context, contextSize) in
            let contextBounds: CGRect = CGRect(x: 0, y: 0, width: contextSize.width, height: contextSize.height)
            context.clear(contextBounds)
            //context.interpolationQuality = .medium
            UIGraphicsPushContext(context)
            image.draw(in: contextBounds)
            UIGraphicsPopContext()
        }
        return drawingBlock
    }
}

class ImageCache: NSObject, FICImageCacheDelegate {
    static let shared = ImageCache()
    
    fileprivate let ImageFormatFrameDevice = "com.brave.imageFormatFrameDevice"
    fileprivate let ImageFormatFrameDeviceFull = "com.brave.imageFormatFrameDevicePortrait"
    
    fileprivate var bitmapCache: FICImageCache!
    
    override init() {
        super.init()
        
        var size = CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        
        // FIC will clear all images if size changes. Doing this forces always portrait sizing.
        if UIApplication.shared.statusBarOrientation != .portrait {
            size = CGSize(width: size.height, height: size.width)
        }
        
        let imageFormat = FICImageFormat()
        imageFormat.name = ImageFormatFrameDeviceFull
        imageFormat.family = ImageFormatFrameDevice
        imageFormat.style = .style32BitBGRA
        imageFormat.imageSize = size
        imageFormat.maximumCount = 1000
        imageFormat.devices = UIDevice.current.userInterfaceIdiom == .phone ? .phone : .pad
        imageFormat.protectionMode = .none
        
        bitmapCache = FICImageCache(nameSpace: "com.brave.images")
        bitmapCache.delegate = self
        bitmapCache.setFormats([imageFormat])
    }
    
    func cache(_ image: UIImage, url: URL, callback: (()->Void)?) {
        let entity = ImageEntity(url: url)
        let format = ImageFormatFrameDeviceFull
        if bitmapCache.imageExists(for: entity, withFormatName: format) {
            bitmapCache.deleteImage(for: entity, withFormatName: format)
        }
        bitmapCache.setImage(image, for: entity, withFormatName: format, completionBlock: { (cachedEntity, format, cachedImage) in
            callback?()
        })
        
    }
    
    func image(_ url: URL, callback: @escaping (_ image: UIImage?)->Void) {
        let entity = ImageEntity(url: url)
        let format = ImageFormatFrameDeviceFull
        bitmapCache.retrieveImage(for: entity, withFormatName: format) { (cachedEntity, format, cachedImage) in
            callback(cachedImage)
        }
    }
    
    func remove(_ url: URL) {
        let entity = ImageEntity(url: url)
        let format = ImageFormatFrameDeviceFull
        if bitmapCache.imageExists(for: entity, withFormatName: format) {
            bitmapCache.deleteImage(for: entity, withFormatName: format)
        }
    }
    
    func imageCache(_ imageCache: FICImageCache, errorDidOccurWithMessage errorMessage: String) {
        debugPrint("ImageCache Error: \(errorMessage)")
    }
}
