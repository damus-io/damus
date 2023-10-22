//
//  VideoCaptureProcessor.swift
//  damus
//
//  Created by Suhail Saqan on 8/5/23.
//

import Foundation
import AVFoundation
import Photos

class VideoCaptureProcessor: NSObject {
    private(set) var movieOutput: AVCaptureMovieFileOutput?

    private let beginHandler: () -> Void
    private let completionHandler: (VideoCaptureProcessor, URL) -> Void
    private let videoProcessingHandler: (Bool) -> Void
    private var session: AVCaptureSession?

    init(movieOutput: AVCaptureMovieFileOutput?,
         beginHandler: @escaping () -> Void,
         completionHandler: @escaping (VideoCaptureProcessor, URL) -> Void,
         videoProcessingHandler: @escaping (Bool) -> Void) {
        self.beginHandler = beginHandler
        self.completionHandler = completionHandler
        self.videoProcessingHandler = videoProcessingHandler
        self.movieOutput = movieOutput
    }

    func startCapture(session: AVCaptureSession) {
        if let movieOutput = self.movieOutput, session.isRunning {
            let outputFileURL = uniqueOutputFileURL()
            movieOutput.startRecording(to: outputFileURL, recordingDelegate: self)
        }
    }

    func stopCapture() {
        if let movieOutput = self.movieOutput {
            if movieOutput.isRecording {
                movieOutput.stopRecording()
            }
        }
    }

    private func uniqueOutputFileURL() -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + ".mov"
        return tempDirectory.appendingPathComponent(fileName)
    }
}

extension VideoCaptureProcessor: AVCaptureFileOutputRecordingDelegate {

    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async {
            self.beginHandler()
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, willFinishRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        DispatchQueue.main.async {
            self.videoProcessingHandler(true)
        }
    }

    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Error capturing video: \(error)")
            return
        }

        DispatchQueue.main.async {
            self.completionHandler(self, outputFileURL)
            self.videoProcessingHandler(false)
        }
    }
}
