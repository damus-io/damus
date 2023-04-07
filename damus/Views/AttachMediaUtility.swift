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

func create_upload_request(mediaToUpload: MediaUpload, mediaUploader: MediaUploader, progress: URLSessionTaskDelegate) async -> ImageUploadResult {
    var mediaData: Data?
    guard let url = URL(string: mediaUploader.postAPI) else {
        return .failed(nil)
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST";
    let boundary = "Boundary-\(UUID().description)"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    
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
        
        guard let responseString = String(data: data, encoding: String.Encoding(rawValue: String.Encoding.utf8.rawValue)) else {
            print("Upload failed getting response string")
            return .failed(nil)
        }
        
        guard let url = mediaUploader.getMediaURL(from: responseString, mediaIsImage: mediaToUpload.is_image) else {
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

enum MediaUploader: String, CaseIterable, Identifiable {
    var id: String { self.rawValue }
    case nostrBuild
    case nostrImg

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
            return "https://nostr.build/upload.php"
        case .nostrImg:
            return "https://nostrimg.com/api/upload"
        }
    }

    func getMediaURL(from responseString: String, mediaIsImage: Bool) -> String? {
        switch self {
        case .nostrBuild:
            guard let startIndex = responseString.range(of: "nostr.build_")?.lowerBound else {
                return nil
            }
            
            let stringContainingName = responseString[startIndex..<responseString.endIndex]
            guard let endIndex = stringContainingName.range(of: "<")?.lowerBound else {
                return nil
            }
            let nostrBuildImageName = responseString[startIndex..<endIndex]
            let nostrBuildURL = mediaIsImage ? "https://nostr.build/i/\(nostrBuildImageName)" : "https://nostr.build/av/\(nostrBuildImageName)"
            return nostrBuildURL
                
        case .nostrImg:
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
