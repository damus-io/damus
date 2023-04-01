//
//  ImageUploadModel.swift
//  damus
//
//  Created by William Casarin on 2023-03-16.
//

import Foundation
import UIKit


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
    
    var is_image: Bool {
        if case .image = self {
            return true
        }
        
        return false
    }
}

class ImageUploadModel: NSObject, URLSessionTaskDelegate, ObservableObject {
    @Published var progress: Double? = nil
    
    func start(media: MediaUpload, uploader: MediaUploader) async -> ImageUploadResult {
        let res = await create_upload_request(mediaToUpload: media, mediaUploader: uploader, progress: self)
        DispatchQueue.main.async {
            self.progress = nil
        }
        return res
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        DispatchQueue.main.async {
            self.progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        }
    }
}
