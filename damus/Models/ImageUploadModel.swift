//
//  ImageUploadModel.swift
//  damus
//
//  Created by William Casarin on 2023-03-16.
//

import Foundation
import UIKit


class ImageUploadModel: NSObject, URLSessionTaskDelegate, ObservableObject {
    @Published var progress: Double? = nil
    
    func start(img: UIImage, uploader: ImageUploader) async -> ImageUploadResult {
        return await create_image_upload_request(imageToUpload: img, imageUploader: uploader, progress: self)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        DispatchQueue.main.async {
            self.progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
            
            if self.progress! >= 1.0 {
                self.progress = nil
            }
        }
    }
}
