//
//  PhotoCaptureProcessor.swift
//  damus
//
//  Created by Suhail Saqan on 8/5/23.
//

import Foundation
import Photos

class PhotoCaptureProcessor: NSObject {
    private(set) var requestedPhotoSettings: AVCapturePhotoSettings
    private(set) var photoOutput: AVCapturePhotoOutput?

    lazy var context = CIContext()
    var photoData: Data?
    private var maxPhotoProcessingTime: CMTime?

    private let willCapturePhotoAnimation: () -> Void
    private let completionHandler: (PhotoCaptureProcessor) -> Void
    private let photoProcessingHandler: (Bool) -> Void

    init(with requestedPhotoSettings: AVCapturePhotoSettings,
         photoOutput: AVCapturePhotoOutput?,
         willCapturePhotoAnimation: @escaping () -> Void,
         completionHandler: @escaping (PhotoCaptureProcessor) -> Void,
         photoProcessingHandler: @escaping (Bool) -> Void) {
        self.requestedPhotoSettings = requestedPhotoSettings
        self.willCapturePhotoAnimation = willCapturePhotoAnimation
        self.completionHandler = completionHandler
        self.photoProcessingHandler = photoProcessingHandler
        self.photoOutput = photoOutput
    }

    func capturePhoto(settings: AVCapturePhotoSettings) {
        if let photoOutput = self.photoOutput {
            photoOutput.capturePhoto(with: settings, delegate: self)
        }
    }
}

extension PhotoCaptureProcessor: AVCapturePhotoCaptureDelegate {
    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        maxPhotoProcessingTime = resolvedSettings.photoProcessingTimeRange.start + resolvedSettings.photoProcessingTimeRange.duration
    }

    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        DispatchQueue.main.async {
            self.willCapturePhotoAnimation()
        }

        guard let maxPhotoProcessingTime = maxPhotoProcessingTime else {
            return
        }

        DispatchQueue.main.async {
            self.photoProcessingHandler(true)
        }

        let oneSecond = CMTime(seconds: 2, preferredTimescale: 1)
        if maxPhotoProcessingTime > oneSecond {
            DispatchQueue.main.async {
                self.photoProcessingHandler(true)
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        DispatchQueue.main.async {
            self.photoProcessingHandler(false)
        }

        if let error = error {
            print("Error capturing photo: \(error)")
        } else {
            photoData = photo.fileDataRepresentation()

        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error)")
            return
        }

        DispatchQueue.main.async {
            self.completionHandler(self)
        }
    }
}
