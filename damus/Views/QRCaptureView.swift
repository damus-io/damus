//
//  QRCaptureView.swift
//  damus
//
//  Created by hazeycode on 21/02/2023.
//

import SwiftUI
import UIKit
import AVFoundation

private var delegate = QrCaptureDelegate()

struct QRCaptureView: View {
    let onCapture: (String) -> Void
    
    @Environment(\.dismiss) var dismiss
    @Environment(\.presentationMode) var presentationMode
    @State var torchOn = false
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            QrCaptureViewRepresentable()
                .capture(onCapture)
                .torchLight(isOn: torchOn)
            
            HStack{
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                        .font(.subheadline)
                        .padding(.top, 20)
                        .padding(.leading, 20)
                }
                Spacer()
                Button(action: {
                    torchOn.toggle()
                }, label: {
                    Image(systemName: torchOn ? "lightbulb.fill" : "lightbulb.slash")
                        .foregroundColor(Color.white)
                        .font(.subheadline)
                        .padding(.top, 20)
                        .padding(.trailing, 20)
                        .background(Color.clear)
                })
            }
        }
        .modifier(SwipeToDismissModifier(minDistance: nil, onDismiss: {
            presentationMode.wrappedValue.dismiss()
        }))
    }
}

struct QrCaptureViewRepresentable: UIViewRepresentable {
    
    typealias UIViewType = CameraPreview
    
    private let session = AVCaptureSession()
    private let metadataOutput = AVCaptureMetadataOutput()
    
    func capture(_ onCapture: @escaping (String) -> Void) -> QrCaptureViewRepresentable {
        delegate.onCapture = onCapture
        return self
    }
    
    func torchLight(isOn: Bool) -> QrCaptureViewRepresentable {
        if let backCamera = AVCaptureDevice.default(for: AVMediaType.video) {
            if backCamera.hasTorch {
                try? backCamera.lockForConfiguration()
                if isOn {
                    backCamera.torchMode = .on
                } else {
                    backCamera.torchMode = .off
                }
                backCamera.unlockForConfiguration()
            }
        }
        return self
    }
    
    func makeUIView(context: UIViewRepresentableContext<QrCaptureViewRepresentable>) -> QrCaptureViewRepresentable.UIViewType {
        let cameraView = CameraPreview(session: session)
        
        #if targetEnvironment(simulator)
        cameraView.createSimulatorView()
        #else
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        cameraView.layer.addSublayer(previewLayer)
        cameraView.previewLayer = previewLayer
        if AVCaptureDevice.authorizationStatus(for: .video) != .authorized {
            AVCaptureDevice.requestAccess(for: .video) { _ in }
        }
        if let backCamera = AVCaptureDevice.default(for: AVMediaType.video) {
            if let input = try? AVCaptureDeviceInput(device: backCamera) {
                session.addInput(input)
                session.addOutput(metadataOutput)
                metadataOutput.metadataObjectTypes = [
                    AVMetadataObject.ObjectType.qr
                ]
                metadataOutput.setMetadataObjectsDelegate(delegate, queue: DispatchQueue.main)
                DispatchQueue.global(qos: .background).async {
                    session.startRunning()
                }
            }
        }
        #endif
        
        return cameraView
    }
    
    func dismantleUIView(_ uiView: CameraPreview, coordinator: ()) {
        uiView.session.stopRunning()
    }
    
    func updateUIView(_ uiView: CameraPreview, context: UIViewRepresentableContext<QrCaptureViewRepresentable>) {
    }
}

class CameraPreview: UIView {
        
    var previewLayer: AVCaptureVideoPreviewLayer?
    var session = AVCaptureSession()
    
    init(session: AVCaptureSession) {
        super.init(frame: .zero)
        self.session = session
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    func createSimulatorView(){
        self.backgroundColor = UIColor.black
        let gesture = UITapGestureRecognizer(target: self, action: #selector(onTap))
        self.addGestureRecognizer(gesture)
    }
    
    @objc func onTap() {
        delegate.onCapture("npub1h77jdhr42sx9a697prc0ltepjx5scclr0nsxvsfdyhx055gyuucq8gytje")
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        #if !targetEnvironment(simulator)
            previewLayer?.frame = self.bounds
        #endif
    }
}

class QrCaptureDelegate: NSObject, AVCaptureMetadataOutputObjectsDelegate {
    
    var onCapture: (String) -> Void = { _  in }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            self.onCapture(stringValue)
        }
    }
}

struct QRCaptureView_Previews: PreviewProvider {
    static var previews: some View {
        QRCaptureView(onCapture: { code in })
    }
}
