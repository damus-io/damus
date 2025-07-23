//
//  CameraModel.swift
//  damus
//
//  Created by Suhail Saqan on 8/5/23.
//

import Foundation
import AVFoundation
import Combine

final class CameraModel: ObservableObject {
    private let service = CameraService()

    @Published var showAlertError = false

    @Published var isFlashOn = false

    @Published var willCapturePhoto = false

    @Published var isCameraButtonDisabled = false

    @Published var isPhotoProcessing = false

    @Published var isRecording = false

    @Published var captureMode: CameraMediaType = .image

    @Published public var mediaItems: [MediaItem] = []

    @Published var thumbnail: Thumbnail!

    var alertError: AlertError!

    var session: AVCaptureSession

    private var subscriptions = Set<AnyCancellable>()

    init() {
        self.session = service.session

        service.$shouldShowAlertView.sink { [weak self] (val) in
            self?.alertError = self?.service.alertError
            self?.showAlertError = val
        }
        .store(in: &self.subscriptions)

        service.$flashMode.sink { [weak self] (mode) in
            self?.isFlashOn = mode == .on
        }
        .store(in: &self.subscriptions)

        service.$willCapturePhoto.sink { [weak self] (val) in
            self?.willCapturePhoto = val
        }
        .store(in: &self.subscriptions)

        service.$isCameraButtonDisabled.sink { [weak self] (val) in
            self?.isCameraButtonDisabled = val
        }
        .store(in: &self.subscriptions)

        service.$isPhotoProcessing.sink { [weak self] (val) in
            self?.isPhotoProcessing = val
        }
        .store(in: &self.subscriptions)

        service.$isRecording.sink { [weak self] (val) in
            self?.isRecording = val
        }
        .store(in: &self.subscriptions)

        service.$captureMode.sink { [weak self] (mode) in
            self?.captureMode = mode
        }
        .store(in: &self.subscriptions)

        service.$mediaItems.sink { [weak self] (mode) in
            self?.mediaItems = mode
        }
        .store(in: &self.subscriptions)

        service.$thumbnail.sink { [weak self] (thumbnail) in
            guard let pic = thumbnail else { return }
            self?.thumbnail = pic
        }
        .store(in: &self.subscriptions)
    }

    func configure() {
        service.checkForPermissions()
        service.configure()
    }

    func stop() {
        service.stop()
    }

    func capturePhoto() {
        service.capturePhoto()
    }

    func startRecording() {
        service.startRecording()
    }

    func stopRecording() {
        service.stopRecording()
    }

    func flipCamera() {
        service.changeCamera()
    }

    func zoom(with factor: CGFloat) {
        service.set(zoom: factor)
    }

    func switchFlash() {
        service.flashMode = service.flashMode == .on ? .off : .on
    }
}
