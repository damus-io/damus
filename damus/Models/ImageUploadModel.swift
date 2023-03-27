//
//  ImageUploadModel.swift
//  damus
//
//  Created by William Casarin on 2023-03-16.
//

import Foundation
import UIKit


enum MediaUpload {
    case image(UIImage)
    case video(URL)
    
    var is_image: Bool {
        guard case .image = self else {
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
