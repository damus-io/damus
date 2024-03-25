//
//  ImageUploadModel.swift
//  damus
//
//  Created by William Casarin on 2023-03-16.
//

import Foundation
import UIKit

enum PreUploadedMedia {
    case uiimage(UIImage)
    case processed_image(URL)
    case unprocessed_image(URL)
    case processed_video(URL)
    case unprocessed_video(URL)
}

enum MediaUpload {
    case image(URL)
    case video(URL)

    var genericFileName: String {
        "damus_generic_filename.\(file_extension)"
    }

    var file_extension: String {
        switch self {
        case .image(let url):
            return url.pathExtension
        case .video(let url):
            return url.pathExtension
        }
    }

    var localURL: URL {
        switch self {
        case .image(let url):
            return url
        case .video(let url):
            return url
        }
    }
    
    var is_image: Bool {
        if case .image = self {
            return true
        }
        
        return false
    }
}

class ImageUploadModel: NSObject, URLSessionTaskDelegate, ObservableObject {
    @Published var progress: Double? = nil
    @Published var currentImagesUploaded: Int = 0
    @Published var totalImagesToUpload: Int = 0
    private var completedUploads: Int = 0
    
    func start(media: MediaUpload, uploader: MediaUploader, keypair: Keypair? = nil) async -> ImageUploadResult {
        DispatchQueue.main.async {
            self.totalImagesToUpload += 1
        }
        let res = await create_upload_request(mediaToUpload: media, mediaUploader: uploader, progress: self, keypair: keypair)
        return res
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        DispatchQueue.main.async {
            self.progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        }
    }
    
    func didFinishUpload() {
        DispatchQueue.main.async {
            self.completedUploads += 1
            self.currentImagesUploaded = self.completedUploads
        }
    }
    
    func resetProgress() {
        DispatchQueue.main.async {
            self.progress = nil
            self.currentImagesUploaded = 0
            self.totalImagesToUpload = 0
            self.completedUploads = 0
        }
    }
}
