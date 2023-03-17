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

fileprivate func create_upload_body(imageDataKey: Data, boundary: String, imageUploader: ImageUploader) -> Data {
        let body = NSMutableData();
        let contentType = "image/jpg"
        body.appendString(string: "Content-Type: multipart/form-data; boundary=\(boundary)\r\n\r\n")
        body.appendString(string: "--\(boundary)\r\n")
        body.appendString(string: "Content-Disposition: form-data; name=\(imageUploader.nameParam); filename=\"damus_generic_filename.jpg\"\r\n")
        body.appendString(string: "Content-Type: \(contentType)\r\n\r\n")
        body.append(imageDataKey as Data)
        body.appendString(string: "\r\n")
        body.appendString(string: "--\(boundary)--\r\n")
        return body as Data
    }


func create_image_upload_request(imageToUpload: UIImage, imageUploader: ImageUploader, progress: URLSessionTaskDelegate) async -> ImageUploadResult {
    
    guard let url = URL(string: imageUploader.postAPI) else {
        return .failed(nil)
    }
    
    var request = URLRequest(url: url)
    request.httpMethod = "POST";
    let boundary = "Boundary-\(UUID().description)"
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    
    // otherwise convert to jpg
    guard let jpegData = imageToUpload.jpegData(compressionQuality: 0.8) else {
        // somehow failed, just return original
        return .failed(nil)
    }
    
    request.httpBody = create_upload_body(imageDataKey: jpegData, boundary: boundary, imageUploader: imageUploader)
    
    do {
        let (data, _) = try await URLSession.shared.data(for: request, delegate: progress)
        
        guard let responseString = String(data: data, encoding: String.Encoding(rawValue: String.Encoding.utf8.rawValue)) else {
            print("Upload failed getting response string")
            return .failed(nil)
        }
        
        guard let url = imageUploader.getImageURL(from: responseString) else {
            print("Upload failed getting image url")
            return .failed(nil)
        }
        
        return .success(url)
        
    } catch {
        return .failed(error)
    }
    
}

extension PostView {
    struct ImagePicker: UIViewControllerRepresentable {

        @Environment(\.presentationMode)
        private var presentationMode

        let sourceType: UIImagePickerController.SourceType
        let onImagePicked: (UIImage) -> Void

        final class Coordinator: NSObject,
                                 UINavigationControllerDelegate,
                                 UIImagePickerControllerDelegate {

            @Binding
            private var presentationMode: PresentationMode
            private let sourceType: UIImagePickerController.SourceType
            private let onImagePicked: (UIImage) -> Void

            init(presentationMode: Binding<PresentationMode>,
                 sourceType: UIImagePickerController.SourceType,
                 onImagePicked: @escaping (UIImage) -> Void) {
                _presentationMode = presentationMode
                self.sourceType = sourceType
                self.onImagePicked = onImagePicked
            }

            func imagePickerController(_ picker: UIImagePickerController,
                                       didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
                let uiImage = info[UIImagePickerController.InfoKey.originalImage] as! UIImage
                onImagePicked(uiImage)
                presentationMode.dismiss()

            }

            func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
                presentationMode.dismiss()
            }

        }

        func makeCoordinator() -> Coordinator {
            return Coordinator(presentationMode: presentationMode,
                               sourceType: sourceType,
                               onImagePicked: onImagePicked)
        }

        func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>) -> UIImagePickerController {
            let picker = UIImagePickerController()
            picker.sourceType = sourceType
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_ uiViewController: UIImagePickerController,
                                    context: UIViewControllerRepresentableContext<ImagePicker>) {

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

enum ImageUploader: String, CaseIterable, Identifiable {
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

    var displayImageUploaderName: String {
        switch self {
        case .nostrBuild:
            return "NostrBuild"
        case .nostrImg:
            return "NostrImg"
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
            return .init(index: -1, tag: "nostrBuild", displayName: NSLocalizedString("NostrBuild", comment: "Dropdown option label for system default for NostrBuild image uploader."))
        case .nostrImg:
            return .init(index: 0, tag: "nostrImg", displayName: NSLocalizedString("NostrImg", comment: "Dropdown option label for system default for NostrImg image uploader."))
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

    func getImageURL(from responseString: String) -> String? {
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
            let nostrBuildURL = "https://nostr.build/i/\(nostrBuildImageName)"
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
