//
//  ImageHost.swift
//  damus
//
//  Created by Michael Hall on 01/04/23.
//

import Foundation
import UIKit

enum ImageHost: String, CaseIterable, Identifiable {
    var id: String { self.rawValue }
    
    struct Model: Identifiable, Hashable {
        var id: String { self.tag }
        var tag: String
        var displayName : String
        var uploadLink : String
        var clientId : String?
    }
    
// TODO: implement nostr.build
//    case nostr_build
    case nostrimg
    
    var model: Model {
        switch self {
// TODO: implement nostr.build
//        case .nostr_build:
//            return .init(tag: "nostr_build", displayName: NSLocalizedString("nostr.build", comment: "Dropdown option label for image host Nostr.Build."),
//                         uploadLink: "https://nostr.build/api/upload", clientId: "")
        case .nostrimg:
            return .init(tag: "nostrimg", displayName: NSLocalizedString("nostrimg.com", comment: "Dropdown option label for image host Nostrimg."),
                         uploadLink: "https://nostrimg.com/api/upload", clientId: "401e1e2049ba44114a5f59e60315eb0fb0fd12beee1f08deb8bde773995b896e")
        }
    }
    
    static var allModels: [Model] {
        return Self.allCases.map { $0.model }
    }
    
    func uploadImage(image_data: Data, completion: @escaping (Result<URL, Error>) -> Void) {
        switch self {
// TODO: implement nostr.build
//        case .nostr_build:
//
//            return
            
        case .nostrimg:
            // Make API call to Nostrimg to upload image
            let url = URL(string: self.model.uploadLink)

            // generate boundary string using a unique per-app string
            let boundary = UUID().uuidString

            let session = URLSession.shared

            // Set the URLRequest to POST and to the specified URL
            var urlRequest = URLRequest(url: url!)
            urlRequest.httpMethod = "POST"
            
            // Set the Authorization header with the Client-ID
            urlRequest.setValue("Client-ID \(self.model.clientId!)", forHTTPHeaderField: "Authorization")

            // Set Content-Type Header to multipart/form-data, this is equivalent to submitting form data with file upload in a web browser
            // And the boundary is also set here
            urlRequest.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            
            
            var bodyData = Data()
            // Add the image data to the raw http request data
            bodyData.append("\r\n--\(boundary)\r\n".data(using: .utf8)!)
            bodyData.append("Content-Disposition: form-data; name=\"\("image")\"; filename=\"\("image." + image_data.mimeType.split(separator: "/")[1])\"\r\n".data(using: .utf8)!)
            bodyData.append("Content-Type: \(image_data.mimeType)\r\n\r\n".data(using: .utf8)!)
            bodyData.append(image_data)
            bodyData.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            
            
            // Send a POST request to the URL, with the data we created earlier
            var result: Result<URL, Error>!
            session.uploadTask(with: urlRequest, from: bodyData, completionHandler: { responseData, response, error in
                if error == nil {
                    do {
                        let jsonData = try JSONSerialization.jsonObject(with: responseData!, options: .allowFragments)
                        if let json = jsonData as? [String: Any] {
                            if let image_url = json["imageUrl"] as? String {
                                result = .success(URL(string: image_url)!)
                            } else {
                                result = .failure(ImageHostError.imageURLError)
                            }
                        } else {
                            result = .failure(ImageHostError.jsonParseError)
                        }
                    } catch {
                        result = .failure(error)
                    }
                    completion(result)
                }
            }).resume()
            return
        }
    }
}

enum ImageHostError: Error {
    case jsonParseError
    case imageURLError
}
