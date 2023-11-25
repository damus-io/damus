//
//  MediaUploader.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-24.
//

import Foundation

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
