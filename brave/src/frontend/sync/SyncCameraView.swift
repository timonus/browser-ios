/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import AVFoundation

class SyncCameraView: UIView, AVCaptureMetadataOutputObjectsDelegate {
    var captureSession:AVCaptureSession?
    var videoPreviewLayer:AVCaptureVideoPreviewLayer?
    var cameraOverlayView: UIImageView!
    
    var scanCallback: ((_ data: String) -> Void)?
    var authorizedCallback: ((_ authorized: Bool) -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        cameraOverlayView = UIImageView(image: UIImage(named: "camera-overlay")?.withRenderingMode(.alwaysTemplate))
        cameraOverlayView.contentMode = .center
        cameraOverlayView.tintColor = UIColor.white
        addSubview(cameraOverlayView)
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func layoutSubviews() {
        if let vpl = videoPreviewLayer {
            vpl.frame = bounds
        }
        cameraOverlayView.frame = bounds
    }
    
    func startCapture() {
        let captureDevice = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)
        
        let input: AVCaptureDeviceInput?
        do {
            input = try AVCaptureDeviceInput(device: captureDevice) as AVCaptureDeviceInput
        }
        catch let error as NSError {
            debugPrint(error)
            return
        }
        
        captureSession = AVCaptureSession()
        captureSession?.addInput(input! as AVCaptureInput)
        
        let captureMetadataOutput = AVCaptureMetadataOutput()
        captureSession?.addOutput(captureMetadataOutput)
        
        captureMetadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
        captureMetadataOutput.metadataObjectTypes = [AVMetadataObjectTypeQRCode]
        
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer?.videoGravity = AVLayerVideoGravityResizeAspectFill
        videoPreviewLayer?.frame = layer.bounds
        layer.addSublayer(videoPreviewLayer!)
        
        captureSession?.startRunning()
        bringSubview(toFront: cameraOverlayView)
        
        if AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo) ==  AVAuthorizationStatus.authorized {
            if let callback = authorizedCallback {
                callback(true)
            }
        }
        else {
            AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo, completionHandler: { (granted :Bool) -> Void in
                if let callback = self.authorizedCallback {
                    callback(granted)
                }
            });
        }
    }
    
    func captureOutput(_ captureOutput: AVCaptureOutput!, didOutputMetadataObjects metadataObjects: [Any]!, from connection: AVCaptureConnection!) {
        
        // Check if the metadataObjects array is not nil and it contains at least one object.
        if metadataObjects == nil || metadataObjects.count == 0 {
            return
        }
        
        let metadataObj = metadataObjects[0] as! AVMetadataMachineReadableCodeObject
        if metadataObj.type == AVMetadataObjectTypeQRCode {
            if let callback = scanCallback {
                callback(metadataObj.stringValue)
            }
        }
    }
    
    func cameraOverlayError() {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        
        cameraOverlayView.tintColor = UIColor.red
        perform(#selector(cameraOverlayNormal), with: self, afterDelay: 1.0)
    }
    
    func cameraOverlaySucess() {
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        
        cameraOverlayView.tintColor = UIColor.green
        perform(#selector(cameraOverlayNormal), with: self, afterDelay: 1.0)
    }
    
    func cameraOverlayNormal() {
        cameraOverlayView.tintColor = UIColor.white
    }
}
