//
//  ImagePicker.swift
//  damus
//
//  Created by Swift on 3/31/23.
//

import UIKit
import SwiftUI

struct ImagePicker: UIViewControllerRepresentable {

    @Environment(\.presentationMode)
    private var presentationMode

    let sourceType: UIImagePickerController.SourceType
    let pubkey: String
    @Binding var image_upload_confirm: Bool
    var imagesOnly: Bool = false
    let onImagePicked: (URL) -> Void
    let onVideoPicked: (URL) -> Void

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        @Binding private var presentationMode: PresentationMode
        private let sourceType: UIImagePickerController.SourceType
        private let onImagePicked: (URL) -> Void
        private let onVideoPicked: (URL) -> Void
        @Binding var image_upload_confirm: Bool

        init(presentationMode: Binding<PresentationMode>,
             sourceType: UIImagePickerController.SourceType,
             onImagePicked: @escaping (URL) -> Void,
             onVideoPicked: @escaping (URL) -> Void,
             image_upload_confirm: Binding<Bool>) {
            _presentationMode = presentationMode
            self.sourceType = sourceType
            self.onImagePicked = onImagePicked
            self.onVideoPicked = onVideoPicked
            self._image_upload_confirm = image_upload_confirm
        }
        
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let videoURL = info[UIImagePickerController.InfoKey.mediaURL] as? URL {
                // Handle the selected video
                onVideoPicked(videoURL)
            } else if let imageURL = info[UIImagePickerController.InfoKey.imageURL] as? URL {
                // Handle the selected image
                onImagePicked(imageURL)
            } else if let cameraImage = info[UIImagePickerController.InfoKey.originalImage] as? UIImage {
                let orientedImage = cameraImage.fixOrientation()
                if let imageURL = saveImageToTemporaryFolder(image: orientedImage, imageType: "jpeg") {
                    onImagePicked(imageURL)
                }
            } else if let editedImage = info[UIImagePickerController.InfoKey.editedImage] as? UIImage {
                let orientedImage = editedImage.fixOrientation()
                if let editedImageURL = saveImageToTemporaryFolder(image: orientedImage, imageType: "jpeg") {
                    onImagePicked(editedImageURL)
                }
            }
            image_upload_confirm = true
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            presentationMode.dismiss()
        }
        
        func saveImageToTemporaryFolder(image: UIImage, imageType: String = "png") -> URL? {
            // Convert UIImage to Data
            let imageData: Data?
            if imageType.lowercased() == "jpeg" {
                imageData = image.jpegData(compressionQuality: 1.0)
            } else {
                imageData = image.pngData()
            }
            
            guard let data = imageData else {
                print("Failed to convert UIImage to Data.")
                return nil
            }
            
            // Generate a temporary URL with a unique filename
            let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let uniqueImageName = "\(UUID().uuidString).\(imageType)"
            let temporaryImageURL = temporaryDirectoryURL.appendingPathComponent(uniqueImageName)
            
            // Save the image data to the temporary URL
            do {
                try data.write(to: temporaryImageURL)
                return temporaryImageURL
            } catch {
                print("Error saving image data to temporary URL: \(error.localizedDescription)")
                return nil
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
        return Coordinator(presentationMode: presentationMode,
                           sourceType: sourceType,
                           onImagePicked: { url in
            // Handle the selected image URL
            onImagePicked(url)
        },
                           onVideoPicked: { videoURL in
            // Handle the selected video URL
            onVideoPicked(videoURL)
        }, image_upload_confirm: $image_upload_confirm)
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        let mediaUploader = get_media_uploader(pubkey)
        picker.mediaTypes = ["public.image", "com.compuserve.gif"]
        if mediaUploader.supportsVideo && !imagesOnly {
            picker.mediaTypes.append("public.movie")
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController,
                                context: UIViewControllerRepresentableContext<ImagePicker>) {

    }
}

extension UIImage {
    func fixOrientation() -> UIImage {
        guard imageOrientation != .up else { return self }
        
        UIGraphicsBeginImageContextWithOptions(size, false, scale)
        draw(in: CGRect(origin: .zero, size: size))
        let normalizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        return normalizedImage ?? self
    }
}
