//
//  ImagePicker.swift
//  damus
//
//  Created by Swift on 3/31/23.
//

import UIKit
import SwiftUI
import PhotosUI

struct MediaPicker: UIViewControllerRepresentable {

    @Environment(\.presentationMode)
    @Binding private var presentationMode

    @Binding var image_upload_confirm: Bool
    var imagesOnly: Bool = false
    let onMediaPicked: (PreUploadedMedia) -> Void
    

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: MediaPicker

        init(_ parent: MediaPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            if results.isEmpty {
                self.parent.presentationMode.dismiss()
            }
            
            for result in results {
                if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    result.itemProvider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { (item, error) in
                        guard let url = item as? URL else { return }
                        
                        if canGetSourceTypeFromUrl(url: url) {
                            // Media was not taken from camera
                            self.attemptAcquireResourceAndChooseMedia(
                                url: url,
                                fallback: processImage,
                                unprocessedEnum: {.unprocessed_image($0)},
                                processedEnum: {.processed_image($0)}
                            )
                        } else {
                            // Media was taken from camera
                            result.itemProvider.loadObject(ofClass: UIImage.self) { (image, error) in
                                if let image = image as? UIImage, error == nil {
                                    self.chooseMedia(.uiimage(image))
                                }
                            }
                        }
                    }
                } else if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { (url, error) in
                        guard let url, error == nil else { return }

                        self.attemptAcquireResourceAndChooseMedia(
                            url: url,
                            fallback: processVideo,
                            unprocessedEnum: {.unprocessed_video($0)},
                            processedEnum: {.processed_video($0)}
                        )
                    }
                }
            }
        }
        
        private func chooseMedia(_ media: PreUploadedMedia) {
            self.parent.onMediaPicked(media)
            self.parent.image_upload_confirm = true
        }
        
        private func attemptAcquireResourceAndChooseMedia(url: URL, fallback: (URL) -> URL?, unprocessedEnum: (URL) -> PreUploadedMedia, processedEnum: (URL) -> PreUploadedMedia) {
            if url.startAccessingSecurityScopedResource() {
                // Have permission from system to use url out of scope
                print("Acquired permission to security scoped resource")
                self.chooseMedia(unprocessedEnum(url))
            } else {
                // Need to copy URL to non-security scoped location
                guard let newUrl = fallback(url) else { return }
                self.chooseMedia(processedEnum(newUrl))
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
