//
//  CameraService.swift
//  Campus
//
//  Created by Suhail Saqan on 8/5/23.
//

import Foundation
import Combine
import AVFoundation
import Photos
import UIKit

public struct Thumbnail: Identifiable, Equatable {
    public var id: String
    public var type: CameraMediaType
    public var url: URL

    public init(id: String = UUID().uuidString, type: CameraMediaType, url: URL) {
        self.id = id
        self.type = type
        self.url = url
    }

    public var thumbnailImage: UIImage? {
        switch type {
        case .image:
            return ImageResizer(targetWidth: 100).resize(at: url)
        case .video:
            return generateVideoThumbnail(for: url)
        }
    }
}

public struct AlertError {
    public var title: String = ""
    public var message: String = ""
    public var primaryButtonTitle = "Accept"
    public var secondaryButtonTitle: String?
    public var primaryAction: (() -> ())?
    public var secondaryAction: (() -> ())?

    public init(title: String = "", message: String = "", primaryButtonTitle: String = "Accept", secondaryButtonTitle: String? = nil, primaryAction: (() -> ())? = nil, secondaryAction: (() -> ())? = nil) {
        self.title = title
        self.message = message
        self.primaryAction = primaryAction
        self.primaryButtonTitle = primaryButtonTitle
        self.secondaryAction = secondaryAction
    }
}

func generateVideoThumbnail(for videoURL: URL) -> UIImage? {
    let asset = AVAsset(url: videoURL)
    let imageGenerator = AVAssetImageGenerator(asset: asset)
    imageGenerator.appliesPreferredTrackTransform = true

    do {
        let cgImage = try imageGenerator.copyCGImage(at: .zero, actualTime: nil)
        return UIImage(cgImage: cgImage)
    } catch {
        print("Error generating thumbnail: \(error)")
        return nil
    }
}

public enum CameraMediaType {
    case image
    case video
}

public struct MediaItem {
    let url: URL
    let type: CameraMediaType
}

public class CameraService: NSObject, Identifiable {
    public let session = AVCaptureSession()

    public var isSessionRunning = false
    public var isConfigured = false
    var setupResult: SessionSetupResult = .success

    public var alertError: AlertError = AlertError()

    @Published public var flashMode: AVCaptureDevice.FlashMode = .off
    @Published public var shouldShowAlertView = false
    @Published public var isPhotoProcessing = false
    @Published public var captureMode: CameraMediaType = .image
    @Published public var isRecording: Bool = false

    @Published public var willCapturePhoto = false
    @Published public var isCameraButtonDisabled = false
    @Published public var isCameraUnavailable = false
    @Published public var thumbnail: Thumbnail?
    @Published public var mediaItems: [MediaItem] = []

    public let sessionQueue = DispatchQueue(label: "io.damus.camera")

    @objc dynamic public var videoDeviceInput: AVCaptureDeviceInput!
    @objc dynamic public var audioDeviceInput: AVCaptureDeviceInput!

    public let videoDeviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .builtInDualCamera, .builtInTrueDepthCamera], mediaType: .video, position: .unspecified)

    public let photoOutput = AVCapturePhotoOutput()

    public let movieOutput = AVCaptureMovieFileOutput()

    var videoCaptureProcessor: VideoCaptureProcessor?
    var photoCaptureProcessor: PhotoCaptureProcessor?

    public var keyValueObservations = [NSKeyValueObservation]()

    override public init() {
        super.init()

        DispatchQueue.main.async {
            self.isCameraButtonDisabled = true
            self.isCameraUnavailable = true
        }
    }

    enum SessionSetupResult {
        case success
        case notAuthorized
        case configurationFailed
    }

    public func configure() {
        if !self.isSessionRunning && !self.isConfigured {
            sessionQueue.async {
                self.configureSession()
            }
        }
    }

    public func checkForPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            break
        case .notDetermined:
            sessionQueue.suspend()
            AVCaptureDevice.requestAccess(for: .video, completionHandler: { granted in
                if !granted {
                    self.setupResult = .notAuthorized
                }
                self.sessionQueue.resume()
            })

        default:
            setupResult = .notAuthorized

            DispatchQueue.main.async {
                self.alertError = AlertError(title: "Camera Access", message: "Damus needs camera and microphone access. Enable in settings.", primaryButtonTitle: "Go to settings", secondaryButtonTitle: nil, primaryAction: {
                        this_app.open(URL(string: UIApplication.openSettingsURLString)!,
                                                  options: [:], completionHandler: nil)

                }, secondaryAction: nil)
                self.shouldShowAlertView = true
                self.isCameraUnavailable = true
                self.isCameraButtonDisabled = true
            }
        }
    }

    private func configureSession() {
        if setupResult != .success {
            return
        }

        session.beginConfiguration()

        session.sessionPreset = .high

        // Add video input.
        do {
            var defaultVideoDevice: AVCaptureDevice?

            if let backCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
                // If a rear dual camera is not available, default to the rear wide angle camera.
                defaultVideoDevice = backCameraDevice
            } else if let frontCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
                // If the rear wide angle camera isn't available, default to the front wide angle camera.
                defaultVideoDevice = frontCameraDevice
            }

            guard let videoDevice = defaultVideoDevice else {
                print("Default video device is unavailable.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }

            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)

            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
            } else {
                print("Couldn't add video device input to the session.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }

            let audioDevice = AVCaptureDevice.default(for: .audio)
            let audioDeviceInput = try AVCaptureDeviceInput(device: audioDevice!)

            if session.canAddInput(audioDeviceInput) {
                session.addInput(audioDeviceInput)
                self.audioDeviceInput = audioDeviceInput
            } else {
                print("Couldn't add audio device input to the session.")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }

            // Add video output
            if session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            } else {
                print("Could not add movie output to the session")
                setupResult = .configurationFailed
                session.commitConfiguration()
                return
            }
        } catch {
            print("Couldn't create video device input: \(error)")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }

        // Add the photo output.
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)

            photoOutput.maxPhotoQualityPrioritization = .quality

        } else {
            print("Could not add photo output to the session")
            setupResult = .configurationFailed
            session.commitConfiguration()
            return
        }

        session.commitConfiguration()
        self.isConfigured = true

        self.start()
    }

    private func resumeInterruptedSession() {
        sessionQueue.async {
            self.session.startRunning()
            self.isSessionRunning = self.session.isRunning
            if !self.session.isRunning {
                DispatchQueue.main.async {
                    self.alertError = AlertError(title: "Camera Error", message: "Unable to resume camera", primaryButtonTitle: "Accept", secondaryButtonTitle: nil, primaryAction: nil, secondaryAction: nil)
                    self.shouldShowAlertView = true
                    self.isCameraUnavailable = true
                    self.isCameraButtonDisabled = true
                }
            } else {
                DispatchQueue.main.async {
                    self.isCameraUnavailable = false
                    self.isCameraButtonDisabled = false
                }
            }
        }
    }

    public func changeCamera() {
        DispatchQueue.main.async {
            self.isCameraButtonDisabled = true
        }

        sessionQueue.async {
            let currentVideoDevice = self.videoDeviceInput.device
            let currentPosition = currentVideoDevice.position

            let preferredPosition: AVCaptureDevice.Position
            let preferredDeviceType: AVCaptureDevice.DeviceType

            switch currentPosition {
            case .unspecified, .front:
                preferredPosition = .back
                preferredDeviceType = .builtInWideAngleCamera

            case .back:
                preferredPosition = .front
                preferredDeviceType = .builtInWideAngleCamera

            @unknown default:
                print("Unknown capture position. Defaulting to back, dual-camera.")
                preferredPosition = .back
                preferredDeviceType = .builtInWideAngleCamera
            }
            let devices = self.videoDeviceDiscoverySession.devices
            var newVideoDevice: AVCaptureDevice? = nil

            if let device = devices.first(where: { $0.position == preferredPosition && $0.deviceType == preferredDeviceType }) {
                newVideoDevice = device
            } else if let device = devices.first(where: { $0.position == preferredPosition }) {
                newVideoDevice = device
            }

            if let videoDevice = newVideoDevice {
                do {
                    let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)

                    self.session.beginConfiguration()

                    self.session.removeInput(self.videoDeviceInput)

                    if self.session.canAddInput(videoDeviceInput) {
                        NotificationCenter.default.removeObserver(self, name: .AVCaptureDeviceSubjectAreaDidChange, object: currentVideoDevice)
                        NotificationCenter.default.addObserver(self, selector: #selector(self.subjectAreaDidChange), name: .AVCaptureDeviceSubjectAreaDidChange, object: videoDeviceInput.device)

                        self.session.addInput(videoDeviceInput)
                        self.videoDeviceInput = videoDeviceInput
                    } else {
                        self.session.addInput(self.videoDeviceInput)
                    }

                    if let connection = self.photoOutput.connection(with: .video) {
                        if connection.isVideoStabilizationSupported {
                            connection.preferredVideoStabilizationMode = .auto
                        }
                    }

                    self.photoOutput.maxPhotoQualityPrioritization = .quality

                    self.session.commitConfiguration()
                } catch {
                    print("Error occurred while creating video device input: \(error)")
                }
            }

            DispatchQueue.main.async {
                self.isCameraButtonDisabled = false
            }
        }
    }

    public func focus(with focusMode: AVCaptureDevice.FocusMode, exposureMode: AVCaptureDevice.ExposureMode, at devicePoint: CGPoint, monitorSubjectAreaChange: Bool) {
        sessionQueue.async {
            guard let device = self.videoDeviceInput?.device else { return }
            do {
                try device.lockForConfiguration()

                if device.isFocusPointOfInterestSupported && device.isFocusModeSupported(focusMode) {
                    device.focusPointOfInterest = devicePoint
                    device.focusMode = focusMode
                }

                if device.isExposurePointOfInterestSupported && device.isExposureModeSupported(exposureMode) {
                    device.exposurePointOfInterest = devicePoint
                    device.exposureMode = exposureMode
                }

                device.isSubjectAreaChangeMonitoringEnabled = monitorSubjectAreaChange
                device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        }
    }


    public func focus(at focusPoint: CGPoint) {
        let device = self.videoDeviceInput.device
        do {
            try device.lockForConfiguration()
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = focusPoint
                device.exposurePointOfInterest = focusPoint
                device.exposureMode = .continuousAutoExposure
                device.focusMode = .continuousAutoFocus
                device.unlockForConfiguration()
            }
        }
        catch {
            print(error.localizedDescription)
        }
    }

    @objc public func stop(completion: (() -> ())? = nil) {
        sessionQueue.async {
            if self.isSessionRunning {
                if self.setupResult == .success {
                    self.session.stopRunning()
                    self.isSessionRunning = self.session.isRunning
                    print("CAMERA STOPPED")
                    self.removeObservers()

                    if !self.session.isRunning {
                        DispatchQueue.main.async {
                            self.isCameraButtonDisabled = true
                            self.isCameraUnavailable = true
                            completion?()
                        }
                    }
                }
            }
        }
    }

    @objc public func start() {
        sessionQueue.async {
            if !self.isSessionRunning && self.isConfigured {
                switch self.setupResult {
                case .success:
                    self.addObservers()
                    self.session.startRunning()
                    print("CAMERA RUNNING")
                    self.isSessionRunning = self.session.isRunning

                    if self.session.isRunning {
                        DispatchQueue.main.async {
                            self.isCameraButtonDisabled = false
                            self.isCameraUnavailable = false
                        }
                    }

                case .notAuthorized:
                    print("Application not authorized to use camera")
                    DispatchQueue.main.async {
                        self.isCameraButtonDisabled = true
                        self.isCameraUnavailable = true
                    }

                case .configurationFailed:
                    DispatchQueue.main.async {
                        self.alertError = AlertError(title: "Camera Error", message: "Camera configuration failed. Either your device camera is not available or other application is using it", primaryButtonTitle: "Accept", secondaryButtonTitle: nil, primaryAction: nil, secondaryAction: nil)
                        self.shouldShowAlertView = true
                        self.isCameraButtonDisabled = true
                        self.isCameraUnavailable = true
                    }
                }
            }
        }
    }

    public func set(zoom: CGFloat) {
        let factor = zoom < 1 ? 1 : zoom
        let device = self.videoDeviceInput.device

        do {
            try device.lockForConfiguration()
            device.videoZoomFactor = factor
            device.unlockForConfiguration()
        }
        catch {
            print(error.localizedDescription)
        }
    }

    public func capturePhoto() {
        if self.setupResult != .configurationFailed {
            let videoPreviewLayerOrientation: AVCaptureVideoOrientation = .portrait
            self.isCameraButtonDisabled = true

            sessionQueue.async {
                if let photoOutputConnection = self.photoOutput.connection(with: .video) {
                    photoOutputConnection.videoOrientation = videoPreviewLayerOrientation
                }
                var photoSettings = AVCapturePhotoSettings()

                // Capture HEIF photos when supported. Enable according to user settings and high-resolution photos.
                if (self.photoOutput.availablePhotoCodecTypes.contains(.hevc)) {
                    photoSettings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
                }

                if self.videoDeviceInput.device.isFlashAvailable {
                    photoSettings.flashMode = self.flashMode
                }

                if !photoSettings.__availablePreviewPhotoPixelFormatTypes.isEmpty {
                    photoSettings.previewPhotoFormat = [kCVPixelBufferPixelFormatTypeKey as String: photoSettings.__availablePreviewPhotoPixelFormatTypes.first!]
                }

                photoSettings.photoQualityPrioritization = .speed

                if self.photoCaptureProcessor == nil {
                    self.photoCaptureProcessor = PhotoCaptureProcessor(with: photoSettings, photoOutput: self.photoOutput, willCapturePhotoAnimation: {
                        DispatchQueue.main.async {
                            self.willCapturePhoto.toggle()
                            self.willCapturePhoto.toggle()
                        }
                    }, completionHandler: { (photoCaptureProcessor) in
                        if let data = photoCaptureProcessor.photoData {
                            let url = self.savePhoto(data: data)
                            if let unwrappedURL = url {
                                self.thumbnail = Thumbnail(type: .image, url: unwrappedURL)
                            }
                        } else {
                            print("Data for photo not found")
                        }

                        self.isCameraButtonDisabled = false
                    }, photoProcessingHandler: { animate in
                        self.isPhotoProcessing = animate
                    })
                }

                self.photoCaptureProcessor?.capturePhoto(settings: photoSettings)
            }
        }
    }

    public func startRecording() {
        if self.setupResult != .configurationFailed {
            let videoPreviewLayerOrientation: AVCaptureVideoOrientation = .portrait
            self.isCameraButtonDisabled = true

            sessionQueue.async {
                if let videoOutputConnection = self.movieOutput.connection(with: .video) {
                    videoOutputConnection.videoOrientation = videoPreviewLayerOrientation

                    var videoSettings = [String: Any]()

                    if self.movieOutput.availableVideoCodecTypes.contains(.hevc) == true {
                        videoSettings[AVVideoCodecKey] = AVVideoCodecType.hevc
                        self.movieOutput.setOutputSettings(videoSettings, for: videoOutputConnection)
                    }
                }

                if self.videoCaptureProcessor == nil {
                    self.videoCaptureProcessor = VideoCaptureProcessor(movieOutput: self.movieOutput, beginHandler: {
                        self.isRecording = true
                    }, completionHandler: { (videoCaptureProcessor, outputFileURL) in
                        self.isCameraButtonDisabled = false
                        self.captureMode = .image

                        self.mediaItems.append(MediaItem(url: outputFileURL, type: .video))
                        self.thumbnail = Thumbnail(type: .video, url: outputFileURL)
                    }, videoProcessingHandler: { animate in
                        self.isPhotoProcessing = animate
                    })
                }

                self.videoCaptureProcessor?.startCapture(session: self.session)
            }
        }
    }

    func stopRecording() {
        if let videoCaptureProcessor = self.videoCaptureProcessor {
            isRecording = false
            videoCaptureProcessor.stopCapture()
        }
    }

    func savePhoto(imageType: String = "jpeg", data: Data) -> URL?  {
        guard let uiImage = UIImage(data: data) else {
            print("Error converting media data to UIImage")
            return nil
        }

        guard let compressedData = uiImage.jpegData(compressionQuality: 0.8) else {
            print("Error converting UIImage to JPEG data")
            return nil
        }

        let temporaryDirectory = NSTemporaryDirectory()
        let tempFileName = "\(UUID().uuidString).\(imageType)"
        let tempFileURL = URL(fileURLWithPath: temporaryDirectory).appendingPathComponent(tempFileName)

        do {
            try compressedData.write(to: tempFileURL)
            self.mediaItems.append(MediaItem(url: tempFileURL, type: .image))
            return tempFileURL
        } catch {
            print("Error saving image data to temporary URL: \(error.localizedDescription)")
        }
        return nil
    }

    private func addObservers() {
        let systemPressureStateObservation = observe(\.videoDeviceInput.device.systemPressureState, options: .new) { _, change in
            guard let systemPressureState = change.newValue else { return }
            self.setRecommendedFrameRateRangeForPressureState(systemPressureState: systemPressureState)
        }
        keyValueObservations.append(systemPressureStateObservation)

//        NotificationCenter.default.addObserver(self, selector: #selector(self.onOrientationChange), name: UIDevice.orientationDidChangeNotification, object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(subjectAreaDidChange),
                                               name: .AVCaptureDeviceSubjectAreaDidChange,
                                               object: videoDeviceInput.device)

        NotificationCenter.default.addObserver(self, selector: #selector(uiRequestedNewFocusArea), name: .init(rawValue: "UserDidRequestNewFocusPoint"), object: nil)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionRuntimeError),
                                               name: .AVCaptureSessionRuntimeError,
                                               object: session)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionWasInterrupted),
                                               name: .AVCaptureSessionWasInterrupted,
                                               object: session)

        NotificationCenter.default.addObserver(self,
                                               selector: #selector(sessionInterruptionEnded),
                                               name: .AVCaptureSessionInterruptionEnded,
                                               object: session)
    }

    private func removeObservers() {
        NotificationCenter.default.removeObserver(self)

        for keyValueObservation in keyValueObservations {
            keyValueObservation.invalidate()
        }
        keyValueObservations.removeAll()
    }

    @objc private func uiRequestedNewFocusArea(notification: NSNotification) {
        guard let userInfo = notification.userInfo as? [String: Any], let devicePoint = userInfo["devicePoint"] as? CGPoint else { return }
        self.focus(at: devicePoint)
    }

    @objc
    private func subjectAreaDidChange(notification: NSNotification) {
        let devicePoint = CGPoint(x: 0.5, y: 0.5)
        focus(with: .continuousAutoFocus, exposureMode: .continuousAutoExposure, at: devicePoint, monitorSubjectAreaChange: false)
    }

    @objc
    private func sessionRuntimeError(notification: NSNotification) {
        guard let error = notification.userInfo?[AVCaptureSessionErrorKey] as? AVError else { return }

        print("Capture session runtime error: \(error)")

        if error.code == .mediaServicesWereReset {
            sessionQueue.async {
                if self.isSessionRunning {
                    self.session.startRunning()
                    self.isSessionRunning = self.session.isRunning
                }
            }
        }
    }

    private func setRecommendedFrameRateRangeForPressureState(systemPressureState: AVCaptureDevice.SystemPressureState) {
        let pressureLevel = systemPressureState.level
        if pressureLevel == .serious || pressureLevel == .critical {
            do {
                try self.videoDeviceInput.device.lockForConfiguration()
                print("WARNING: Reached elevated system pressure level: \(pressureLevel). Throttling frame rate.")
                self.videoDeviceInput.device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: 20)
                self.videoDeviceInput.device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: 15)
                self.videoDeviceInput.device.unlockForConfiguration()
            } catch {
                print("Could not lock device for configuration: \(error)")
            }
        } else if pressureLevel == .shutdown {
            print("Session stopped running due to shutdown system pressure level.")
        }
    }

    @objc
    private func sessionWasInterrupted(notification: NSNotification) {
        DispatchQueue.main.async {
            self.isCameraUnavailable = true
        }

        if let userInfoValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as AnyObject?,
            let reasonIntegerValue = userInfoValue.integerValue,
            let reason = AVCaptureSession.InterruptionReason(rawValue: reasonIntegerValue) {
            print("Capture session was interrupted with reason \(reason)")

            if reason == .audioDeviceInUseByAnotherClient || reason == .videoDeviceInUseByAnotherClient {
                print("Session stopped running due to video devies in use by another client.")
            } else if reason == .videoDeviceNotAvailableWithMultipleForegroundApps {
                print("Session stopped running due to video devies is not available with multiple foreground apps.")
            } else if reason == .videoDeviceNotAvailableDueToSystemPressure {
                print("Session stopped running due to shutdown system pressure level.")
            }
        }
    }

    @objc
    private func sessionInterruptionEnded(notification: NSNotification) {
        print("Capture session interruption ended")
        DispatchQueue.main.async {
            self.isCameraUnavailable = false
        }
    }
}
