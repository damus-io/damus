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

/// Result of an image/video upload operation.
///
/// Contains either the uploaded media URL on success, or an `UploadError`
/// with specific details about what went wrong on failure.
enum ImageUploadResult {
    case success(String)
    case failed(UploadError)
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

    /// Creates and executes an upload request for the given media.
    ///
    /// This method handles the complete upload flow:
    /// 1. Validates the upload API URL
    /// 2. Reads media data from disk
    /// 3. Constructs a multipart form-data request
    /// 4. Adds NIP-98 authentication if required
    /// 5. Executes the upload with progress tracking
    /// 6. Parses the server response for the uploaded URL
    ///
    /// - Parameters:
    ///   - mediaToUpload: The media file to upload (image or video)
    ///   - mediaUploader: The upload service configuration
    ///   - mediaType: Whether this is a normal upload or profile picture
    ///   - progress: Delegate for tracking upload progress
    ///   - keypair: Optional keypair for NIP-98 authentication
    /// - Returns: Upload result with the media URL on success, or typed error on failure
    static func create_upload_request(mediaToUpload: MediaUpload, mediaUploader: any MediaUploaderProtocol, mediaType: ImageUploadMediaType, progress: URLSessionTaskDelegate, keypair: Keypair? = nil) async -> ImageUploadResult {
        var mediaData: Data?

        guard let url = URL(string: mediaUploader.postAPI) else {
            return .failed(.invalidAPIURL)
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
                return .failed(.fileReadError(underlying: error))
            }
        case .video(let url):
            do {
                mediaData = try Data(contentsOf: url)
            } catch {
                return .failed(.fileReadError(underlying: error))
            }
        }

        guard let mediaData else {
            return .failed(.noMediaData)
        }

        request.httpBody = create_upload_body(mediaData: mediaData, boundary: boundary, mediaUploader: mediaUploader, mediaToUpload: mediaToUpload, mediaType: mediaType)

        do {
            let (data, _) = try await URLSession.shared.data(for: request, delegate: progress)

            switch mediaUploader.getMediaURL(from: data) {
            case .success(let url):
                return .success(url)
            case .failure(let error):
                return .failed(error)
            }

        } catch {
            return .failed(.networkError(underlying: error))
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
