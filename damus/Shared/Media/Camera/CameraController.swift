//
//  CameraController.swift
//  damus
//
//  Created by KernelKind on 2/15/24.
//

import UIKit
import SwiftUI

struct CameraController: UIViewControllerRepresentable {
    
    @Environment(\.presentationMode)
    @Binding private var presentationMode

    let uploader: any MediaUploaderProtocol
    var imagesOnly: Bool = false
    var mode: Mode
    
    enum Mode {
        case save_to_library(when_done: () -> Void)
        case handle_image(handler: (UIImage) -> Void)
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraController
        
        init(_ parent: CameraController) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            switch parent.mode {
            case .save_to_library(when_done: let done):
                if !parent.imagesOnly, let videoURL = info[UIImagePickerController.InfoKey.mediaURL] as? URL {
                    // Handle the selected video
                    UISaveVideoAtPathToSavedPhotosAlbum(videoURL.relativePath, nil, nil, nil)
                } else if let cameraImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
                    let orientedImage = cameraImage.fixOrientation()
                    UIImageWriteToSavedPhotosAlbum(orientedImage, nil, nil, nil)
                } else if let editedImage = info[UIImagePickerController.InfoKey.editedImage] as? UIImage {
                    let orientedImage = editedImage.fixOrientation()
                    UIImageWriteToSavedPhotosAlbum(orientedImage, nil, nil, nil)
                }
                done()
            case .handle_image(handler: let handler):
                if let cameraImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
                    let orientedImage = cameraImage.fixOrientation()
                    handler(orientedImage)
                } else if let editedImage = info[UIImagePickerController.InfoKey.editedImage] as? UIImage {
                    let orientedImage = editedImage.fixOrientation()
                    handler(orientedImage)
                }
            }
            
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.presentationMode.dismiss()
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(self)
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<CameraController>) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.mediaTypes = ["public.image", "com.compuserve.gif"]
        if uploader.supportsVideo && !imagesOnly {
            picker.mediaTypes.append("public.movie")
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController,
                                context: UIViewControllerRepresentableContext<CameraController>) {

    }
}
