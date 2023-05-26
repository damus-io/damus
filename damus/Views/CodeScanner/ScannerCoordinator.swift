//
//  CodeScanner.swift
//  https://github.com/twostraws/CodeScanner
//
//  Created by Paul Hudson on 14/12/2021.
//  Copyright © 2021 Paul Hudson. All rights reserved.
//

import AVFoundation
import SwiftUI

extension CodeScannerView {
    @available(macCatalyst 14.0, *)
    public class ScannerCoordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        var parent: CodeScannerView
        var codesFound = Set<String>()
        var didFinishScanning = false
        var lastTime = Date(timeIntervalSince1970: 0)

        init(parent: CodeScannerView) {
            self.parent = parent
        }

        public func reset() {
            codesFound.removeAll()
            didFinishScanning = false
            lastTime = Date(timeIntervalSince1970: 0)
        }

        public func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
            if let metadataObject = metadataObjects.first {
                guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
                guard let stringValue = readableObject.stringValue else { return }
                guard didFinishScanning == false else { return }
                let result = ScanResult(string: stringValue, type: readableObject.type)

                switch parent.scanMode {
                case .once:
                    found(result)
                    // make sure we only trigger scan once per use
                    didFinishScanning = true

                case .oncePerCode:
                    if !codesFound.contains(stringValue) {
                        codesFound.insert(stringValue)
                        found(result)
                    }

                case .continuous:
                    if isPastScanInterval() {
                        found(result)
                    }
                }
            }
        }

        func isPastScanInterval() -> Bool {
            Date().timeIntervalSince(lastTime) >= parent.scanInterval
        }

        func found(_ result: ScanResult) {
            lastTime = Date()

            if parent.shouldVibrateOnSuccess {
                AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            }

            parent.completion(.success(result))
        }

        func didFail(reason: ScanError) {
            parent.completion(.failure(reason))
        }
    }
}
