//
//  AttachMediaUtility.swift
//  damus
//
//  Created by Swift on 2/17/23.
//

import SwiftUI

extension PostView {
    func myImageUploadRequest(imageToUpload: UIImage, imageUploader: ImageUploader) {
        let myUrl = NSURL(string: imageUploader.postAPI);
        let request = NSMutableURLRequest(url:myUrl! as URL);
        request.httpMethod = "POST";
        let boundary = generateBoundaryString()
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let imageData = imageToUpload.jpegData(compressionQuality: 1)
        if imageData == nil  {
            return
        }
        request.httpBody = createBodyWithParameters(imageDataKey: imageData! as NSData, boundary: boundary, imageUploader: imageUploader) as Data

        let task = URLSession.shared.dataTask(with: request as URLRequest) {
            data, response, error in
            if error != nil {
                print("error=\(error!)")
                return
            }

            let responseString = String(data: data!, encoding: String.Encoding(rawValue: String.Encoding.utf8.rawValue))
            print("response data = \(responseString!)")

            let uploadedImageURL = NSMutableAttributedString(string: imageUploader.getImageURL(from: responseString), attributes: [NSAttributedString.Key.font: UIFont.systemFont(ofSize: 18.0), NSAttributedString.Key.foregroundColor: UIColor.label])
            let combinedAttributedString = NSMutableAttributedString()
            combinedAttributedString.append(post)
            combinedAttributedString.append(uploadedImageURL)
            post = combinedAttributedString
        }
        task.resume()
    }

    func createBodyWithParameters(imageDataKey: NSData, boundary: String, imageUploader: ImageUploader) -> NSData {
        let body = NSMutableData();
        let contentType = "image/jpg"
        body.appendString(string: "Content-Type: multipart/form-data; boundary=\(boundary)\r\n\r\n")
        body.appendString(string: "--\(boundary)\r\n")
        body.appendString(string: "Content-Disposition: form-data; name=\(imageUploader.nameParam); filename=\"damus_generic_filename.jpg\"\r\n")
        body.appendString(string: "Content-Type: \(contentType)\r\n\r\n")
        body.append(imageDataKey as Data)
        body.appendString(string: "\r\n")
        body.appendString(string: "--\(boundary)--\r\n")
        return body
    }

    func generateBoundaryString() -> String {
        return "Boundary-\(NSUUID().uuidString)"

    }

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
        let data = string.data(using: String.Encoding.utf8, allowLossyConversion: true)
        append(data!)
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

    func getImageURL(from responseString: String?) -> String {
        switch self {
        case .nostrBuild:
            if let startIndex = responseString?.range(of: "nostr.build_")?.lowerBound,
               let stringContainingName = responseString?[startIndex..<responseString!.endIndex],
               let endIndex = stringContainingName.range(of: "<")?.lowerBound,
               let nostrBuildImageName = responseString?[startIndex..<endIndex] {
                let nostrBuildURL = "https://nostr.build/i/\(nostrBuildImageName)"
                return nostrBuildURL
            } else {
                return ""
            }
        case .nostrImg:
            if let startIndex = responseString?.range(of: "https://i.nostrimg.com/")?.lowerBound,
               let stringContainingName = responseString?[startIndex..<responseString!.endIndex],
               let endIndex = stringContainingName.range(of: "\"")?.lowerBound,
               let nostrBuildImageName = responseString?[startIndex..<endIndex] {
                let nostrBuildURL = "\(nostrBuildImageName)"
                return nostrBuildURL
            } else {
                return ""
            }

        }
    }
}
