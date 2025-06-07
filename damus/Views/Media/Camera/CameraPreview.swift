//
//  CameraPreview.swift
//  damus
//
//  Created by Suhail Saqan on 8/5/23.
//

import UIKit
import AVFoundation
import SwiftUI

public struct CameraPreview: UIViewRepresentable {
    public class VideoPreviewView: UIView {
        public override class var layerClass: AnyClass {
            AVCaptureVideoPreviewLayer.self
        }

        var videoPreviewLayer: AVCaptureVideoPreviewLayer {
            return layer as! AVCaptureVideoPreviewLayer
        }

        let focusView: UIView = {
            let focusView = UIView(frame: CGRect(x: 0, y: 0, width: 30, height: 30))
            focusView.layer.borderColor = UIColor.white.cgColor
            focusView.layer.borderWidth = 1.5
            focusView.layer.cornerRadius = 15
            focusView.layer.opacity = 0
            focusView.backgroundColor = .clear
            return focusView
        }()

        @objc func focusAndExposeTap(gestureRecognizer: UITapGestureRecognizer) {
            let layerPoint = gestureRecognizer.location(in: gestureRecognizer.view)

            guard layerPoint.x >= 0 && layerPoint.x <= bounds.width &&
                    layerPoint.y >= 0 && layerPoint.y <= bounds.height else {
                return
            }

            let devicePoint = videoPreviewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)

            self.focusView.layer.frame = CGRect(origin: layerPoint, size: CGSize(width: 30, height: 30))

            NotificationCenter.default.post(.init(name: .init("UserDidRequestNewFocusPoint"), object: nil, userInfo: ["devicePoint": devicePoint] as [AnyHashable: Any]))

            UIView.animate(withDuration: 0.3, animations: {
                self.focusView.layer.opacity = 1
            }) { (completed) in
                if completed {
                    UIView.animate(withDuration: 0.3) {
                        self.focusView.layer.opacity = 0
                    }
                }
            }
        }

        public override func layoutSubviews() {
            super.layoutSubviews()

            videoPreviewLayer.videoGravity = .resizeAspectFill

            self.layer.addSublayer(focusView.layer)

            let gRecognizer = UITapGestureRecognizer(target: self, action: #selector(VideoPreviewView.focusAndExposeTap(gestureRecognizer:)))
            self.addGestureRecognizer(gRecognizer)
        }
    }

    public let session: AVCaptureSession

    public init(session: AVCaptureSession) {
        self.session = session
    }

    public func makeUIView(context: Context) -> VideoPreviewView {
        let viewFinder = VideoPreviewView()
        viewFinder.backgroundColor = .black
        viewFinder.videoPreviewLayer.cornerRadius = 20
        viewFinder.videoPreviewLayer.session = session
        viewFinder.videoPreviewLayer.connection?.videoOrientation = .portrait

        return viewFinder
    }

    public func updateUIView(_ uiView: VideoPreviewView, context: Context) {

    }
}

struct CameraPreview_Previews: PreviewProvider {
    static var previews: some View {
        CameraPreview(session: AVCaptureSession())
            .frame(height: 300)
    }
}
