//
//  AttachMediaUtility.swift
//  damus
//
//  Created by Swift on 2/17/23.
//

import SwiftUI

func myImageUploadRequest(imageToUpload: UIImage, completion: @escaping (String) -> ()) {
    let myUrl = NSURL(string: "https://nostr.build/upload.php");
    let request = NSMutableURLRequest(url:myUrl! as URL);
    request.httpMethod = "POST";
    let boundary = generateBoundaryString()
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    let imageData = imageToUpload.jpegData(compressionQuality: 1)
    if imageData == nil  {
        return
    }
    request.httpBody = createBodyWithParameters(imageDataKey: imageData! as NSData, boundary: boundary) as Data

    let task = URLSession.shared.dataTask(with: request as URLRequest) {
        data, response, error in
        if error != nil {
            print("error=\(error!)")
            return
        }

        let responseString = String(data: data!, encoding: String.Encoding(rawValue: String.Encoding.utf8.rawValue))
        print("response data = \(responseString!)")
        if let startIndex = responseString?.range(of: "nostr.build_")?.lowerBound,
           let endIndex = responseString?.range(of: "</b></span><BR>")?.lowerBound,
           let nostrBuildImageName = responseString?[startIndex..<endIndex] {
            let nostrBuildURL = "https://nostr.build/i/\(nostrBuildImageName)"
            completion(nostrBuildURL)
        }
    }
    task.resume()
}



func createBodyWithParameters(imageDataKey: NSData, boundary: String) -> NSData {
    let body = NSMutableData();
    let contentType = "image/png"
    body.appendString(string: "--\(boundary)\r\n")
    body.appendString(string: "Content-Disposition: form-data; name=\"fileToUpload\"; filename=\"Damus.png\"\r\n")
    body.appendString(string: "Content-Type: \(contentType)\r\n\r\n")
    body.append(imageDataKey as Data)
    body.appendString(string: "\r\n")
    body.appendString(string: "--\(boundary)--\r\n")
    return body
}

func generateBoundaryString() -> String {
    return "Boundary-\(NSUUID().uuidString)"

}

extension NSMutableData {
    func appendString(string: String) {
        let data = string.data(using: String.Encoding.utf8, allowLossyConversion: true)
        append(data!)
    }
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
