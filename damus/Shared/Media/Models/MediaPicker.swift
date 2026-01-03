//
//  ImagePicker.swift
//  damus
//
//  Created by Swift on 3/31/23.
//

import UIKit
import SwiftUI
import PhotosUI

enum MediaPickerEntry {
    case editPictureControl
    case postView
}

/// Represents an error that occurred during media selection or processing.
struct MediaPickerError {
    let message: String
    let itemIndex: Int?

    /// A user-friendly message describing what went wrong.
    var userMessage: String {
        if let index = itemIndex {
            return String(format: NSLocalizedString("Failed to process item %d: %@", comment: "Error processing specific media item"), index + 1, message)
        }
        return message
    }
}

struct MediaPicker: UIViewControllerRepresentable {

    @Environment(\.presentationMode)
    @Binding private var presentationMode
    let mediaPickerEntry: MediaPickerEntry

    let onMediaSelected: (() -> Void)?
    let onMediaPicked: (PreUploadedMedia) -> Void
    /// Called when one or more media items fail to process. The Int parameter is the count of failed items.
    let onError: ((Int) -> Void)?

    init(mediaPickerEntry: MediaPickerEntry, onMediaSelected: (() -> Void)? = nil, onError: ((Int) -> Void)? = nil, onMediaPicked: @escaping (PreUploadedMedia) -> Void) {
        self.mediaPickerEntry = mediaPickerEntry
        self.onMediaSelected = onMediaSelected
        self.onError = onError
        self.onMediaPicked = onMediaPicked
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        var parent: MediaPicker

        // properties used for returning medias in the same order as picking
        let dispatchGroup: DispatchGroup = DispatchGroup()
        var orderIds: [String] = []
        var orderMap: [String: PreUploadedMedia] = [:]
        var failedCount: Int = 0

        init(_ parent: MediaPicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            if results.isEmpty {
                Log.debug("Media picker dismissed with no selection", for: .image_uploading)
                self.parent.presentationMode.dismiss()
                return
            }

            Log.info("Media picker: %{public}d items selected", for: .image_uploading, results.count)

            // Reset state for new selection
            orderIds.removeAll()
            orderMap.removeAll()
            failedCount = 0

            for result in results {

                let orderId = result.assetIdentifier ?? UUID().uuidString
                orderIds.append(orderId)
                dispatchGroup.enter()

                if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    result.itemProvider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { (item, error) in
                        if let error = error {
                            Log.error("Failed to load image item: %{public}@", for: .image_uploading, error.localizedDescription)
                            self.recordFailure()
                            return
                        }
                        guard let url = item as? URL else {
                            Log.error("Image item is not a URL, type: %{public}@", for: .image_uploading, String(describing: type(of: item)))
                            self.recordFailure()
                            return
                        }

                        Log.debug("Loaded image: %{public}@", for: .image_uploading, url.lastPathComponent)

                        if(url.pathExtension == "gif") {
                            // GIFs do not natively support location metadata
                            // Load data directly to avoid JPEG conversion
                            _ = result.itemProvider.loadDataRepresentation(for: .gif, completionHandler: { imageData, error in
                                if let error = error {
                                    Log.error("Failed to load GIF data: %{public}@", for: .image_uploading, error.localizedDescription)
                                    self.recordFailure()
                                    return
                                }
                                guard let imageData else {
                                    Log.error("GIF data is nil", for: .image_uploading)
                                    self.recordFailure()
                                    return
                                }
                                let destinationURL = generateUniqueTemporaryMediaURL(fileExtension: "gif")
                                do {
                                    try imageData.write(to: destinationURL)
                                    Log.debug("GIF saved to temp: %{public}@", for: .image_uploading, destinationURL.lastPathComponent)
                                    Task {
                                        await self.chooseMedia(.processed_image(destinationURL), orderId: orderId)
                                    }
                                }
                                catch {
                                    Log.error("Failed to write GIF image data from Photo picker into a local copy", for: .image_uploading)
                                    self.recordFailure()
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
                            Log.debug("Loading camera image as UIImage", for: .image_uploading)
                            result.itemProvider.loadObject(ofClass: UIImage.self) { (image, error) in
                                if let error = error {
                                    Log.error("Failed to load UIImage: %{public}@", for: .image_uploading, error.localizedDescription)
                                    self.recordFailure()
                                    return
                                }
                                if let image = image as? UIImage {
                                    self.chooseMedia(.uiimage(image), orderId: orderId)
                                } else {
                                    Log.error("Loaded object is not a UIImage", for: .image_uploading)
                                    self.recordFailure()
                                }
                            }
                        }
                    }
                } else if result.itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                    Log.debug("Loading video file", for: .image_uploading)
                    result.itemProvider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { (url, error) in
                        if let error = error {
                            Log.error("Failed to load video: %{public}@", for: .image_uploading, error.localizedDescription)
                            self.recordFailure()
                            return
                        }
                        guard let url else {
                            Log.error("Video URL is nil", for: .image_uploading)
                            self.recordFailure()
                            return
                        }

                        Log.debug("Loaded video: %{public}@", for: .image_uploading, url.lastPathComponent)
                        self.attemptAcquireResourceAndChooseMedia(
                            url: url,
                            fallback: processVideo,
                            unprocessedEnum: {.unprocessed_video($0)},
                            processedEnum: {.processed_video($0)}, orderId: orderId
                        )
                    }
                } else {
                    Log.error("Unknown media type in picker result", for: .image_uploading)
                    self.recordFailure()
                }
            }

            dispatchGroup.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                Log.info("Media picker complete: %{public}d ready, %{public}d failed", for: .image_uploading, self.orderMap.count, self.failedCount)

                // Notify about failures if any occurred
                if self.failedCount > 0 {
                    self.parent.onError?(self.failedCount)
                }

                // Deliver successfully processed media
                for id in self.orderIds {
                    if let media = self.orderMap[id] {
                        self.parent.onMediaPicked(media)
                    }
                }
            }
        }

        /// Records a media processing failure and leaves the dispatch group.
        /// Uses main queue to synchronize access to failedCount from multiple background callbacks.
        private func recordFailure() {
            DispatchQueue.main.async {
                self.failedCount += 1
                self.dispatchGroup.leave()
            }
        }

        /// Stores successfully processed media and leaves the dispatch group.
        /// Uses main queue to synchronize access to orderMap from multiple background callbacks.
        private func chooseMedia(_ media: PreUploadedMedia, orderId: String) {
            DispatchQueue.main.async {
                self.parent.onMediaSelected?()
                self.orderMap[orderId] = media
                self.dispatchGroup.leave()
            }
        }

        /// Attempts to access a security-scoped resource and processes the media.
        ///
        /// If direct access is granted, uses the URL as-is. Otherwise, copies to a
        /// non-security-scoped location using the fallback processor.
        private func attemptAcquireResourceAndChooseMedia(url: URL, fallback: (URL) -> URL?, unprocessedEnum: (URL) -> PreUploadedMedia, processedEnum: (URL) -> PreUploadedMedia, orderId: String) {
            if url.startAccessingSecurityScopedResource() {
                // Have permission from system to use url out of scope
                Log.debug("Acquired security scoped resource access: %{public}@", for: .image_uploading, url.lastPathComponent)
                self.chooseMedia(unprocessedEnum(url), orderId: orderId)
            } else {
                // Need to copy URL to non-security scoped location
                Log.debug("Security scoped access denied, processing with fallback: %{public}@", for: .image_uploading, url.lastPathComponent)
                guard let newUrl = fallback(url) else {
                    Log.error("Fallback processing failed for: %{public}@", for: .image_uploading, url.lastPathComponent)
                    self.recordFailure()
                    return
                }
                Log.debug("Fallback processing succeeded: %{public}@", for: .image_uploading, newUrl.lastPathComponent)
                self.chooseMedia(processedEnum(newUrl), orderId: orderId)
            }
        }

    }
        
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration(photoLibrary: .shared())
        switch mediaPickerEntry {
        case .postView:
            configuration.selectionLimit = 0 // allows multiple media selection
            configuration.filter = .any(of: [.images, .videos])
            configuration.selection = .ordered // images are returned in the order they were selected + numbered badge displayed
        case .editPictureControl:
            configuration.selectionLimit = 1 // allows one media selection
            configuration.filter = .images // allows image only
        }
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator as any PHPickerViewControllerDelegate
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {
    }
}
