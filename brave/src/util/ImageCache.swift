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
    fileprivate let ImageFormatFrameDeviceLandscape = "com.brave.imageFormatFrameDeviceLandscape"
    fileprivate let ImageFormatFrameDevicePortrait = "com.brave.imageFormatFrameDevicePortrait"
    
    fileprivate var bitmapCache: FICImageCache!
    
    override init() {
        super.init()
        
        let size = CGSize(width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height)
        var portrait = CGSize.zero
        var landscape = CGSize.zero
        
        // Realize this logic is a bit strange. Need to get image size for two states. Flips when alternate.
        if UIApplication.shared.statusBarOrientation == .portrait {
            portrait = size
            landscape = CGSize(width: size.height, height: size.width)
        }
        else {
            portrait = CGSize(width: size.height, height: size.width)
            landscape = size
        }
        
        let imageFormatLandscape = FICImageFormat()
        imageFormatLandscape.name = ImageFormatFrameDeviceLandscape
        imageFormatLandscape.family = ImageFormatFrameDevice
        imageFormatLandscape.style = .style32BitBGRA
        imageFormatLandscape.imageSize = landscape
        imageFormatLandscape.maximumCount = 1000
        imageFormatLandscape.devices = UIDevice.current.userInterfaceIdiom == .phone ? .phone : .pad
        imageFormatLandscape.protectionMode = .none
        
        let imageFormatPortrait = FICImageFormat()
        imageFormatPortrait.name = ImageFormatFrameDevicePortrait
        imageFormatPortrait.family = ImageFormatFrameDevice
        imageFormatPortrait.style = .style32BitBGRA
        imageFormatPortrait.imageSize = portrait
        imageFormatPortrait.maximumCount = 1000
        imageFormatPortrait.devices = UIDevice.current.userInterfaceIdiom == .phone ? .phone : .pad
        imageFormatPortrait.protectionMode = .none
        
        bitmapCache = FICImageCache(nameSpace: "com.brave.images")
        bitmapCache.delegate = self
        bitmapCache.setFormats([imageFormatLandscape, imageFormatPortrait])
    }
    
    func cache(_ image: UIImage, url: URL, callback: (()->Void)?) {
        let entity = ImageEntity(url: url)
        let format = UIApplication.shared.statusBarOrientation == .portrait ? ImageFormatFrameDevicePortrait : ImageFormatFrameDeviceLandscape
        if !bitmapCache.imageExists(for: entity, withFormatName: format) {
            bitmapCache.setImage(image, for: entity, withFormatName: format, completionBlock: { (cachedEntity, format, cachedImage) in
                callback?()
            })
        }
    }
    
    func image(_ url: URL, callback: @escaping (_ image: UIImage?)->Void) {
        let entity = ImageEntity(url: url)
        let format = UIApplication.shared.statusBarOrientation == .portrait ? ImageFormatFrameDevicePortrait : ImageFormatFrameDeviceLandscape
        bitmapCache.retrieveImage(for: entity, withFormatName: format) { (cachedEntity, format, cachedImage) in
            callback(cachedImage)
        }
    }
    
    func imageCache(_ imageCache: FICImageCache, errorDidOccurWithMessage errorMessage: String) {
        debugPrint("ImageCache Error: \(errorMessage)")
    }
}
