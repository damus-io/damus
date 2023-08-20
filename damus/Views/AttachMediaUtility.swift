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

fileprivate func create_upload_body(mediaData: Data, boundary: String, mediaUploader: MediaUploader, mediaToUpload: MediaUpload) -> Data {
        let body = NSMutableData();
        let contentType = mediaToUpload.is_image ? "image/jpg" : "video/mp4"
        body.appendString(string: "Content-Type: multipart/form-data; boundary=\(boundary)\r\n\r\n")
        body.appendString(string: "--\(boundary)\r\n")
        body.appendString(string: "Content-Disposition: form-data; name=\(mediaUploader.nameParam); filename=\(mediaToUpload.genericFileName)\r\n")
        body.appendString(string: "Content-Type: \(contentType)\r\n\r\n")
        body.append(mediaData as Data)
        body.appendString(string: "\r\n")
        body.appendString(string: "--\(boundary)--\r\n")
        return body as Data
    }

func create_upload_request(mediaToUpload: MediaUpload, mediaUploader: MediaUploader, progress: URLSessionTaskDelegate, keypair: Keypair? = nil) async -> ImageUploadResult {
    var mediaData: Data?
    guard let url = URL(string: mediaUploader.postAPI) else {
        return .failed(nil)
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST";
    let boundary = "Boundary-\(UUID().description)"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    
    // If uploading to a media host that support NIP-98 authorization, add the header
    if mediaUploader == .nostrBuild,
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

    request.httpBody = create_upload_body(mediaData: mediaData, boundary: boundary, mediaUploader: mediaUploader, mediaToUpload: mediaToUpload)
    
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

extension NSMutableData {
    func appendString(string: String) {
        guard let data = string.data(using: String.Encoding.utf8, allowLossyConversion: true) else {
            return
        }
        append(data)
    }
}

enum MediaUploader: String, CaseIterable, Identifiable, StringCodable {
    var id: String { self.rawValue }
    case nostrBuild
    case nostrImg
    
    init?(from string: String) {
        guard let mu = MediaUploader(rawValue: string) else {
            return nil
        }
        
        self = mu
    }
    
    func to_string() -> String {
        return rawValue
    }

    var nameParam: String {
        switch self {
        case .nostrBuild:
            return "\"fileToUpload\""
        case .nostrImg:
            return "\"image\""
        }
    }

    var supportsVideo: Bool {
        switch self {
        case .nostrBuild:
            return true
        case .nostrImg:
            return false
        }
    }

    struct Model: Identifiable, Hashable {
        var id: String { self.tag }
        var index: Int
        var tag: String
        var displayName : String
    }

    var model: Model {
        switch self {
        case .nostrBuild:
            return .init(index: -1, tag: "nostrBuild", displayName: "nostr.build")
        case .nostrImg:
            return .init(index: 0, tag: "nostrImg", displayName: "nostrimg.com")
        }
    }


    var postAPI: String {
        switch self {
        case .nostrBuild:
            return "https://nostr.build/api/v2/upload/files"
        case .nostrImg:
            return "https://nostrimg.com/api/upload"
        }
    }

    func getMediaURL(from data: Data) -> String? {
        switch self {
        case .nostrBuild:
            do {
                if let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any],
                   let status = jsonObject["status"] as? String {
                   
                    if status == "success", let dataArray = jsonObject["data"] as? [[String: Any]] {
                        
                        var urls: [String] = []

                        for dataDict in dataArray {
                            if let mainUrl = dataDict["url"] as? String {
                                urls.append(mainUrl)
                            }
                        }
                        
                        return urls.joined(separator: "\n")
                    } else if status == "error", let message = jsonObject["message"] as? String {
                        print("Upload Error: \(message)")
                        return nil
                    }
                }
            } catch {
                print("Failed JSONSerialization")
                return nil
            }
            return nil
        case .nostrImg:
            guard let responseString = String(data: data, encoding: String.Encoding(rawValue: String.Encoding.utf8.rawValue)) else {
                print("Upload failed getting response string")
                return nil
            }

            guard let startIndex = responseString.range(of: "https://i.nostrimg.com/")?.lowerBound else {
                    return nil
                }
            let stringContainingName = responseString[startIndex..<responseString.endIndex]
            guard let endIndex = stringContainingName.range(of: "\"")?.lowerBound else {
                return nil
            }
            let nostrBuildImageName = responseString[startIndex..<endIndex]
            let nostrBuildURL = "\(nostrBuildImageName)"
            return nostrBuildURL
        }
    }
}
