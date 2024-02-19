//
//  ImagePicker.swift
//  damus
//
//  Created by Swift on 3/31/23.
//

import UIKit
import SwiftUI
import PhotosUI

struct ImagePicker: UIViewControllerRepresentable {

    @Environment(\.presentationMode)
    @Binding private var presentationMode

    @Binding var image_upload_confirm: Bool
    var imagesOnly: Bool = false
    let onMediaPicked: (MediaUpload) -> Void

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker

        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            if results.isEmpty {
                self.parent.presentationMode.dismiss()
            }
            
            for result in results {
                if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    result.itemProvider.loadObject(ofClass: UIImage.self) { (image, error) in
                        guard let image = image as? UIImage, error == nil else { return }
                        let fixedImage = image.fixOrientation()
                        
                        if let savedURL = self.saveImageToTemporaryFolder(image: fixedImage) {
                            self.parent.onMediaPicked(.image(savedURL))
                            self.parent.image_upload_confirm = true
                        }
                    }
                } else if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { (url, error) in
                        guard let url, error == nil else { return }

                        guard let url = self.saveVideoToTemporaryFolder(videoURL: url) else { return }
                        self.parent.onMediaPicked(.video(url))
                        self.parent.image_upload_confirm = true
                    }
                }
            }
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
        
        func saveVideoToTemporaryFolder(videoURL: URL) -> URL? {
            let temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            let fileExtension = videoURL.pathExtension
            let uniqueFileName = UUID().uuidString + (fileExtension.isEmpty ? "" : ".\(fileExtension)")
            let destinationURL = temporaryDirectoryURL.appendingPathComponent(uniqueFileName)
            
            do {
                try FileManager.default.copyItem(at: videoURL, to: destinationURL)
                return destinationURL
            } catch {
                print("Error copying file: \(error.localizedDescription)")
                return nil
            }
        }
    }
    
    func makeCoordinator() -> Coordinator {
            Coordinator(self)
        }
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = 1
        configuration.filter = imagesOnly ? .images : .any(of: [.images, .videos])
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator as any PHPickerViewControllerDelegate
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
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
