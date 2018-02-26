/* This Source Code Form is subject to the terms of the Mozilla Public License, v. 2.0. If a copy of the MPL was not distributed with this file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import AVFoundation
import Shared

class SyncCameraView: UIView, AVCaptureMetadataOutputObjectsDelegate {
    var captureSession:AVCaptureSession?
    var videoPreviewLayer:AVCaptureVideoPreviewLayer?
    var cameraOverlayView: UIImageView!
    private lazy var cameraAccessButton: RoundInterfaceButton = {
        let button = self.createCameraButton()
        button.setTitle(Strings.GrantCameraAccess, for: .normal)
        button.addTarget(self, action: #selector(SEL_cameraAccess), for: .touchUpInside)
        return button
    }()

    private lazy var openSettingsButton: RoundInterfaceButton = {
        let button = self.createCameraButton()
        button.setTitle(Strings.Open_Settings, for: .normal)
        button.addTarget(self, action: #selector(openSettings), for: .touchUpInside)
        return button
    }()
    
    var scanCallback: ((_ data: String) -> Void)?
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        
        cameraOverlayView = UIImageView(image: UIImage(named: "camera-overlay")?.withRenderingMode(.alwaysTemplate))
        cameraOverlayView.contentMode = .center
        cameraOverlayView.tintColor = UIColor.white
        addSubview(cameraOverlayView)
        addSubview(cameraAccessButton)
        addSubview(openSettingsButton)

        [cameraAccessButton, openSettingsButton].forEach { button in
            button.snp.makeConstraints { make in
                make.centerX.equalTo(cameraOverlayView)
                make.centerY.equalTo(cameraOverlayView)
                make.width.equalTo(150)
                make.height.equalTo(40)
            }
        }

        switch AVCaptureDevice.authorizationStatus(forMediaType: AVMediaTypeVideo) {
        case .authorized:
            cameraAccessButton.isHidden = true
            openSettingsButton.isHidden = true
            startCapture()
        case .denied:
            cameraAccessButton.isHidden = true
            openSettingsButton.isHidden = false
        default:
            cameraAccessButton.isHidden = false
            openSettingsButton.isHidden = true
        }
    }

    fileprivate func createCameraButton() -> RoundInterfaceButton {
        let button = RoundInterfaceButton(type: .roundedRect)
        button.titleLabel?.font = UIFont.systemFont(ofSize: 14, weight: UIFontWeightBold)
        button.setTitleColor(UIColor.white, for: .normal)
        button.backgroundColor = UIColor.clear
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.4).cgColor
        button.layer.borderWidth = 1.5

        return button
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
    
    func SEL_cameraAccess() {
        startCapture()
    }

    func openSettings() {
        UIApplication.shared.open(URL(string:UIApplicationOpenSettingsURLString)!)
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

        AVCaptureDevice.requestAccess(forMediaType: AVMediaTypeVideo, completionHandler: { (granted :Bool) -> Void in
            postAsyncToMain {
                self.cameraAccessButton.isHidden = true
                if granted {
                    self.openSettingsButton.isHidden = true
                } else {
                    self.openSettingsButton.isHidden = false
                    self.bringSubview(toFront: self.openSettingsButton)
                }
            }
        })
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
