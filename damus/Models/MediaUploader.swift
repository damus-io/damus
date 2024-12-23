//
//  MediaUploader.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-24.
//

import Foundation

protocol MediaUploaderProtocol: Identifiable {    
    var nameParam: String { get }
    var mediaTypeParam: String { get }
    var supportsVideo: Bool { get }
    var requiresNip98: Bool { get }
    var postAPI: String { get }
    
    func getMediaURL(from data: Data) -> String?
    func mediaTypeValue(for mediaType: ImageUploadMediaType) -> String?
}

enum MediaUploader: String, CaseIterable, MediaUploaderProtocol, StringCodable {
    var id: String { self.rawValue }
    case nostrBuild
    case nostrcheck
    
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
        default:
            return "\"file\""
        }
    }
    
    var mediaTypeParam: String {
        return "media_type"
    }
    
    func mediaTypeValue(for mediaType: ImageUploadMediaType) -> String? {
        switch mediaType {
        case .normal:
            return nil
        case .profile_picture:
            return "avatar"
        }
    }
    
    var supportsVideo: Bool {
        switch self {
        case .nostrBuild:
            return true
        case .nostrcheck:
            return true
        }
    }
    
    var requiresNip98: Bool {
        switch self {
        case .nostrBuild:
            return true
        case .nostrcheck:
            return true
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
        case .nostrcheck:
            return .init(index: 0, tag: "nostrcheck", displayName: "nostrcheck.me")
        }
    }
    
    var postAPI: String {
        switch self {
        case .nostrBuild:
            return "https://nostr.build/api/v2/nip96/upload"
        case .nostrcheck:
            return "https://nostrcheck.me/api/v2/media"
        }
    }
    
    func getMediaURL(from data: Data) -> String? {
        do {
            if let jsonObject = try JSONSerialization.jsonObject(with: data, options: .allowFragments) as? [String: Any],
               let status = jsonObject["status"] as? String {
                
                if status == "success", let nip94Event = jsonObject["nip94_event"] as? [String: Any] {
                    
                    if let tags = nip94Event["tags"] as? [[String]] {
                        for tagArray in tags {
                            if tagArray.count > 1, tagArray[0] == "url" {
                                return tagArray[1]
                            }
                        }
                    }
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
    }
}
