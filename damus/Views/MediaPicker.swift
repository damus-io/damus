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
        var parent: MediaPicker
        
        let dispatchGroup: DispatchGroup = DispatchGroup()
        var orderIds: [String] = []
        var orderMap: [String: PreUploadedMedia] = [:]

        init(_ parent: MediaPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            if results.isEmpty {
                self.parent.presentationMode.dismiss()
            }
            
            for result in results {
                
                let orderId = result.assetIdentifier ?? UUID().uuidString
                orderIds.append(orderId)
                dispatchGroup.enter()
                
                if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    result.itemProvider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { (item, error) in
                        guard let url = item as? URL else { return }
                        
                        if(url.pathExtension == "gif") {
                            // GIFs do not natively support location metadata (See https://superuser.com/a/556320 and https://www.w3.org/Graphics/GIF/spec-gif89a.txt)
                            // It is better to avoid any GPS data processing at all, as it can cause the image to be converted to JPEG.
                            // Therefore, we should load the file directtly and deliver it as "already processed".
                            
                            // Load the data for the GIF image
                            // - Don't load it as an UIImage since that can only get exported into JPEG/PNG
                            // - Don't load it as a file representation because it gets deleted before the upload can occur
                            _ = result.itemProvider.loadDataRepresentation(for: .gif, completionHandler: { imageData, error in
                                guard let imageData else { return }
                                let destinationURL = generateUniqueTemporaryMediaURL(fileExtension: "gif")
                                do {
                                    try imageData.write(to: destinationURL)
                                    Task {
                                        await self.chooseMedia(.processed_image(destinationURL), orderId: orderId)
                                    }
                                }
                                catch {
                                    Log.error("Failed to write GIF image data from Photo picker into a local copy", for: .image_uploading)
                                }
                            })
                        }
                        else if canGetSourceTypeFromUrl(url: url) {
                            // Media was not taken from camera
                            self.attemptAcquireResourceAndChooseMedia(
                                url: url,
                                fallback: processImage,
                                unprocessedEnum: {.unprocessed_image($0)},
                                processedEnum: {.processed_image($0)},
                                orderId: orderId)
                        } else {
                            // Media was taken from camera
                            result.itemProvider.loadObject(ofClass: UIImage.self) { (image, error) in
                                if let image = image as? UIImage, error == nil {
                                    self.chooseMedia(.uiimage(image), orderId: orderId)
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
                            processedEnum: {.processed_video($0)}, orderId: orderId
                        )
                    }
                }
            }
            
            dispatchGroup.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                var arrMedia: [PreUploadedMedia] = []
                for id in self.orderIds {
                    if let media = self.orderMap[id] {
                        arrMedia.append(media)
                        self.parent.onMediaPicked(media)
                    }
                }
            }
        }
        
        
        private func chooseMedia(_ media: PreUploadedMedia, orderId: String) {
            self.parent.image_upload_confirm = true
            self.orderMap[orderId] = media
            self.dispatchGroup.leave()
        }
        
        private func attemptAcquireResourceAndChooseMedia(url: URL, fallback: (URL) -> URL?, unprocessedEnum: (URL) -> PreUploadedMedia, processedEnum: (URL) -> PreUploadedMedia, orderId: String) {
            if url.startAccessingSecurityScopedResource() {
                // Have permission from system to use url out of scope
                print("Acquired permission to security scoped resource")
                self.chooseMedia(unprocessedEnum(url), orderId: orderId)
            } else {
                // Need to copy URL to non-security scoped location
                guard let newUrl = fallback(url) else { return }
                self.chooseMedia(processedEnum(newUrl), orderId: orderId)
            }
        }

    }
        
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        configuration.selectionLimit = 0 // Allows multiple media selection
        configuration.filter = imagesOnly ? .images : .any(of: [.images, .videos])
        configuration.selection = .ordered // images are returned in the order they were selected + numbered badge displayed
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator as any PHPickerViewControllerDelegate
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
    }
}
