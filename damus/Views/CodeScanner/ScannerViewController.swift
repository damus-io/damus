//
//  CodeScanner.swift
//  https://github.com/twostraws/CodeScanner
//
//  Created by Paul Hudson on 14/12/2021.
//  Copyright © 2021 Paul Hudson. All rights reserved.
//

import AVFoundation
import UIKit

extension CodeScannerView {
    
    @available(macCatalyst 14.0, *)
    public class ScannerViewController: UIViewController, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        
        var delegate: ScannerCoordinator?
        private let showViewfinder: Bool
        
        private var isGalleryShowing: Bool = false {
            didSet {
                // Update binding
                if delegate?.parent.isGalleryPresented.wrappedValue != isGalleryShowing {
                    delegate?.parent.isGalleryPresented.wrappedValue = isGalleryShowing
                }
            }
        }

        public init(showViewfinder: Bool = false) {
            self.showViewfinder = showViewfinder
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            self.showViewfinder = false
            super.init(coder: coder)
        }
        
        func openGallery() {
            isGalleryShowing = true
            let imagePicker = UIImagePickerController()
            imagePicker.delegate = self
            present(imagePicker, animated: true, completion: nil)
        }
        
        @objc func openGalleryFromButton(_ sender: UIButton) {
            openGallery()
        }

        public func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            isGalleryShowing = false
            
            if let qrcodeImg = info[.originalImage] as? UIImage {
                let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])!
                let ciImage = CIImage(image:qrcodeImg)!
                var qrCodeLink = ""

                let features = detector.features(in: ciImage)

                for feature in features as! [CIQRCodeFeature] {
                    qrCodeLink += feature.messageString!
                }

                if qrCodeLink == "" {
                    delegate?.didFail(reason: .badOutput)
                } else {
                    let result = ScanResult(string: qrCodeLink, type: .qr)
                    delegate?.found(result)
                }
            } else {
                print("Something went wrong")
            }

            dismiss(animated: true, completion: nil)
        }
        
        public func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            isGalleryShowing = false
        }

        #if targetEnvironment(simulator)
        override public func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = true

            let label = UILabel()
            label.translatesAutoresizingMaskIntoConstraints = false
            label.numberOfLines = 0
            label.text = "You're running in the simulator, which means the camera isn't available. Tap anywhere to send back some simulated data."
            label.textAlignment = .center

            let button = UIButton()
            button.translatesAutoresizingMaskIntoConstraints = false
            button.setTitle("Select a custom image", for: .normal)
            button.setTitleColor(UIColor.systemBlue, for: .normal)
            button.setTitleColor(UIColor.gray, for: .highlighted)
            button.addTarget(self, action: #selector(openGalleryFromButton), for: .touchUpInside)

            let stackView = UIStackView()
            stackView.translatesAutoresizingMaskIntoConstraints = false
            stackView.axis = .vertical
            stackView.spacing = 50
            stackView.addArrangedSubview(label)
            stackView.addArrangedSubview(button)

            view.addSubview(stackView)

            NSLayoutConstraint.activate([
                button.heightAnchor.constraint(equalToConstant: 50),
                stackView.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
                stackView.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
                stackView.centerYAnchor.constraint(equalTo: view.centerYAnchor)
            ])
        }

        override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let simulatedData = delegate?.parent.simulatedData else {
                print("Simulated Data Not Provided!")
                return
            }

            // Send back their simulated data, as if it was one of the types they were scanning for
            let result = ScanResult(string: simulatedData, type: delegate?.parent.codeTypes.first ?? .qr)
            delegate?.found(result)
        }
        
        #else
        
        var captureSession: AVCaptureSession!
        var previewLayer: AVCaptureVideoPreviewLayer!
        let fallbackVideoCaptureDevice = AVCaptureDevice.default(for: .video)

        private lazy var viewFinder: UIImageView? = {
            guard let image = UIImage(named: "viewfinder", in: .main, with: nil) else {
                return nil
            }

            let imageView = UIImageView(image: image)
            imageView.translatesAutoresizingMaskIntoConstraints = false
            return imageView
        }()

        override public func viewDidLoad() {
            super.viewDidLoad()

            NotificationCenter.default.addObserver(self,
                                                   selector: #selector(updateOrientation),
                                                   name: Notification.Name("UIDeviceOrientationDidChangeNotification"),
                                                   object: nil)

            view.backgroundColor = UIColor.black
            captureSession = AVCaptureSession()

            guard let videoCaptureDevice = delegate?.parent.videoCaptureDevice ?? fallbackVideoCaptureDevice else {
                return
            }

            let videoInput: AVCaptureDeviceInput

            do {
                videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
            } catch {
                delegate?.didFail(reason: .initError(error))
                return
            }

            if (captureSession.canAddInput(videoInput)) {
                captureSession.addInput(videoInput)
            } else {
                delegate?.didFail(reason: .badInput)
                return
            }

            let metadataOutput = AVCaptureMetadataOutput()

            if (captureSession.canAddOutput(metadataOutput)) {
                captureSession.addOutput(metadataOutput)

                metadataOutput.setMetadataObjectsDelegate(delegate, queue: DispatchQueue.main)
                metadataOutput.metadataObjectTypes = delegate?.parent.codeTypes
            } else {
                delegate?.didFail(reason: .badOutput)
                return
            }
        }

        override public func viewWillLayoutSubviews() {
            previewLayer?.frame = view.layer.bounds
        }

        @objc func updateOrientation() {
            guard let orientation = view.window?.windowScene?.interfaceOrientation else { return }
            guard let connection = captureSession.connections.last, connection.isVideoOrientationSupported else { return }
            connection.videoOrientation = AVCaptureVideoOrientation(rawValue: orientation.rawValue) ?? .portrait
        }

        override public func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            updateOrientation()
        }

        override public func viewWillAppear(_ animated: Bool) {
            super.viewWillAppear(animated)

            if previewLayer == nil {
                previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            }

            previewLayer.frame = view.layer.bounds
            previewLayer.videoGravity = .resizeAspectFill
            view.layer.addSublayer(previewLayer)
            addviewfinder()

            delegate?.reset()

            if (captureSession?.isRunning == false) {
                DispatchQueue.global(qos: .userInitiated).async {
                    self.captureSession.startRunning()
                }
            }
        }

        private func addviewfinder() {
            guard showViewfinder, let imageView = viewFinder else { return }

            view.addSubview(imageView)

            NSLayoutConstraint.activate([
                imageView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
                imageView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
                imageView.widthAnchor.constraint(equalToConstant: 200),
                imageView.heightAnchor.constraint(equalToConstant: 200),
            ])
        }

        override public func viewDidDisappear(_ animated: Bool) {
            super.viewDidDisappear(animated)

            if (captureSession?.isRunning == true) {
                DispatchQueue.global(qos: .userInitiated).async {
                    self.captureSession.stopRunning()
                }
            }

            NotificationCenter.default.removeObserver(self)
        }

        override public var prefersStatusBarHidden: Bool {
            true
        }

        override public var supportedInterfaceOrientations: UIInterfaceOrientationMask {
            .all
        }

        /** Touch the screen for autofocus */
        public override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard touches.first?.view == view,
                  let touchPoint = touches.first,
                  let device = delegate?.parent.videoCaptureDevice ?? fallbackVideoCaptureDevice
            else { return }

            let videoView = view
            let screenSize = videoView!.bounds.size
            let xPoint = touchPoint.location(in: videoView).y / screenSize.height
            let yPoint = 1.0 - touchPoint.location(in: videoView).x / screenSize.width
            let focusPoint = CGPoint(x: xPoint, y: yPoint)

            do {
                try device.lockForConfiguration()
            } catch {
                return
            }

            // Focus to the correct point, make continiuous focus and exposure so the point stays sharp when moving the device closer
            device.focusPointOfInterest = focusPoint
            device.focusMode = .continuousAutoFocus
            device.exposurePointOfInterest = focusPoint
            device.exposureMode = AVCaptureDevice.ExposureMode.continuousAutoExposure
            device.unlockForConfiguration()
        }
        
        #endif
        
        func updateViewController(isTorchOn: Bool, isGalleryPresented: Bool) {
            if let backCamera = AVCaptureDevice.default(for: AVMediaType.video),
               backCamera.hasTorch
            {
                try? backCamera.lockForConfiguration()
                backCamera.torchMode = isTorchOn ? .on : .off
                backCamera.unlockForConfiguration()
            }
            
            if isGalleryPresented && !isGalleryShowing {
                openGallery()
            }
        }
        
    }
}
