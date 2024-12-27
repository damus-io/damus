//
//  AttachMediaUtility.swift
//  damus
//
//  Created by Swift on 2/17/23.
//

import SwiftUI
import UIKit
import CoreGraphics
import UniformTypeIdentifiers

enum ImageUploadResult {
    case success(String)
    case failed(Error?)
}

enum ImageUploadMediaType {
    case normal
    case profile_picture
}

protocol AttachMediaUtilityProtocol {
    static func create_upload_request(mediaToUpload: MediaUpload, mediaUploader: any MediaUploaderProtocol, mediaType: ImageUploadMediaType, progress: URLSessionTaskDelegate, keypair: Keypair?) async -> ImageUploadResult
}

class AttachMediaUtility {
    fileprivate static func create_upload_body(mediaData: Data, boundary: String, mediaUploader: any MediaUploaderProtocol, mediaToUpload: MediaUpload, mediaType: ImageUploadMediaType) -> Data {
        let mediaTypeFieldValue = mediaUploader.mediaTypeValue(for: mediaType)
        let mediaTypeFieldEntry: String?
        if let mediaTypeFieldValue {
            mediaTypeFieldEntry = "; \(mediaUploader.mediaTypeParam)=\(mediaTypeFieldValue)"
        }
        else {
            mediaTypeFieldEntry = nil
        }
        let body = NSMutableData();
        let contentType = mediaToUpload.mime_type
        body.appendString(string: "Content-Type: multipart/form-data; boundary=\(boundary)\r\n\r\n")
        body.appendString(string: "--\(boundary)\r\n")
        body.appendString(string: "Content-Disposition: form-data; name=\(mediaUploader.nameParam); filename=\(mediaToUpload.genericFileName)\(mediaTypeFieldEntry ?? "")\r\n")
        body.appendString(string: "Content-Type: \(contentType)\r\n\r\n")
        body.append(mediaData as Data)
        body.appendString(string: "\r\n")
        body.appendString(string: "--\(boundary)--\r\n")
        return body as Data
    }

    static func create_upload_request(mediaToUpload: MediaUpload, mediaUploader: any MediaUploaderProtocol, mediaType: ImageUploadMediaType, progress: URLSessionTaskDelegate, keypair: Keypair? = nil) async -> ImageUploadResult {
        var mediaData: Data?
        guard let url = URL(string: mediaUploader.postAPI) else {
            return .failed(nil)
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST";
        let boundary = "Boundary-\(UUID().description)"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        // If uploading to a media host that support NIP-98 authorization, add the header
        if mediaUploader.requiresNip98,
           let keypair,
            let method = request.httpMethod,
            let signature = create_nip98_signature(keypair: keypair, method: method, url: url) {

             request.setValue(signature, forHTTPHeaderField: "Authorization")
        }
        
        switch mediaToUpload {
        case .image(let url):
            do {
                mediaData = try Data(contentsOf: url)
            } catch {
                return .failed(error)
            }
        case .video(let url):
            do {
                mediaData = try Data(contentsOf: url)
            } catch {
                return .failed(error)
            }
        }

        guard let mediaData else {
            return .failed(nil)
        }

        request.httpBody = create_upload_body(mediaData: mediaData, boundary: boundary, mediaUploader: mediaUploader, mediaToUpload: mediaToUpload, mediaType: mediaType)
        
        do {
            let (data, _) = try await URLSession.shared.data(for: request, delegate: progress)

            guard let url = mediaUploader.getMediaURL(from: data) else {
                print("Upload failed getting media url")
                return .failed(nil)
            }
            
            return .success(url)
            
        } catch {
            return .failed(error)
        }
    }
}

extension NSMutableData {
    func appendString(string: String) {
        guard let data = string.data(using: String.Encoding.utf8, allowLossyConversion: true) else {
            return
        }
        append(data)
    }
}
