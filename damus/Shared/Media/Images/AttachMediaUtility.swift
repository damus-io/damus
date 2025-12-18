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

    // MARK: - Blossom Upload

    /// Handles upload via Blossom protocol (BUD-02).
    ///
    /// Blossom uses a different approach than NIP-96 uploaders:
    /// - PUT request with raw binary body (not multipart form-data)
    /// - Kind 24242 authorization (not NIP-98)
    /// - Server URL from user settings (not hardcoded)
    ///
    /// For large files (videos), uses streaming upload to avoid memory issues.
    fileprivate static func uploadViaBlossom(
        mediaToUpload: MediaUpload,
        keypair: Keypair?,
        progress: URLSessionTaskDelegate
    ) async -> ImageUploadResult {
        // Get Blossom server URL from settings
        guard let settings = UserSettingsStore.shared,
              let serverURLString = settings.manualBlossomServerUrl,
              !serverURLString.isEmpty,
              let serverURL = BlossomServerURL(serverURLString) else {
            print("Blossom upload failed: No server configured")
            return .failed(BlossomError.noServerConfigured)
        }

        // Need keypair for Blossom auth
        guard let keypair = keypair,
              let fullKeypair = keypair.to_full() else {
            print("Blossom upload failed: No private key for signing")
            return .failed(BlossomError.authenticationFailed)
        }

        // Use BlossomUploader to perform the upload
        // The uploader handles streaming for large files automatically
        let uploader = BlossomUploader()
        let result = await uploader.upload(
            fileURL: mediaToUpload.localURL,
            mimeType: mediaToUpload.mime_type,
            to: serverURL,
            keypair: fullKeypair.to_keypair(),
            progressDelegate: progress
        )

        switch result {
        case .success(let blobDescriptor):
            // Trigger background mirroring to backup servers (BUD-04)
            // This is fire-and-forget - doesn't block the upload response
            triggerBackgroundMirroring(
                blobDescriptor: blobDescriptor,
                settings: settings,
                keypair: fullKeypair.to_keypair()
            )
            return .success(blobDescriptor.url)

        case .failed(let error):
            print("Blossom upload failed: \(error)")
            return .failed(error)
        }
    }

    /// Triggers background mirroring to configured backup servers.
    /// Only runs if mirroring is enabled and mirror servers are configured.
    private static func triggerBackgroundMirroring(
        blobDescriptor: BlossomBlobDescriptor,
        settings: UserSettingsStore,
        keypair: Keypair
    ) {
        guard settings.blossomMirrorEnabled else { return }

        let mirrorServerURLs = settings.blossomMirrorServers.compactMap { BlossomServerURL($0) }
        guard !mirrorServerURLs.isEmpty else { return }

        BlossomUploader.mirrorToServersInBackground(
            sourceURL: blobDescriptor.url,
            sha256Hex: blobDescriptor.sha256,
            targetServers: mirrorServerURLs,
            keypair: keypair
        )
    }

    // MARK: - NIP-96 Upload Body

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
        // Route to Blossom uploader for Blossom protocol (BUD-02)
        if let uploader = mediaUploader as? MediaUploader, uploader == .blossom {
            return await uploadViaBlossom(mediaToUpload: mediaToUpload, keypair: keypair, progress: progress)
        }

        // NIP-96 upload flow for other uploaders (nostr.build, nostrcheck, etc.)
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
