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
    
    var mime_type: String {
        switch self.file_extension {
            case "jpg", "jpeg":
                return "image/jpg"
            case "png":
                return "image/png"
            case "gif":
                return "image/gif"
            case "tiff", "tif":
                return "image/tiff"
            case "mp4":
                return "video/mp4"
            case "ogg":
                return "video/ogg"
            case "webm":
                return "video/webm"
            default:
                switch self {
                    case .image:
                        return "image/jpg"
                    case .video:
                        return "video/mp4"
                }
        }
    }
}

protocol ImageUploadModelProtocol {
    init()
    
    func start(media: MediaUpload, uploader: any MediaUploaderProtocol, mediaType: ImageUploadMediaType, keypair: Keypair?) async -> ImageUploadResult
}

class ImageUploadModel: NSObject, URLSessionTaskDelegate, ObservableObject, ImageUploadModelProtocol {
    @Published var progress: Double? = nil
    
    override required init() { }
    
    func start(media: MediaUpload, uploader: any MediaUploaderProtocol, mediaType: ImageUploadMediaType, keypair: Keypair? = nil) async -> ImageUploadResult {
        let res = await AttachMediaUtility.create_upload_request(mediaToUpload: media, mediaUploader: uploader, mediaType: mediaType, progress: self, keypair: keypair)
                
        switch res {
        case .success(_):
            DispatchQueue.main.async {
                self.progress = nil
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        case .failed(_):
            DispatchQueue.main.async {
                self.progress = nil
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }

        return res
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        DispatchQueue.main.async {
            self.progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        }
    }
}
