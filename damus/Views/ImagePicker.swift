//
//  ImagePicker.swift
//  damus
//
//  Created by Swift on 3/31/23.
//

import UIKit
import SwiftUI

struct ImagePicker: UIViewControllerRepresentable {

    @Environment(\.presentationMode)
    private var presentationMode

    let sourceType: UIImagePickerController.SourceType
    let pubkey: String
    var imagesOnly: Bool = false
    let onImagePicked: (URL) -> Void
    let onVideoPicked: (URL) -> Void

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        @Binding private var presentationMode: PresentationMode
        private let sourceType: UIImagePickerController.SourceType
        private let onImagePicked: (URL) -> Void
        private let onVideoPicked: (URL) -> Void

        init(presentationMode: Binding<PresentationMode>,
             sourceType: UIImagePickerController.SourceType,
             onImagePicked: @escaping (URL) -> Void,
             onVideoPicked: @escaping (URL) -> Void) {
            _presentationMode = presentationMode
            self.sourceType = sourceType
            self.onImagePicked = onImagePicked
            self.onVideoPicked = onVideoPicked
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let videoURL = info[UIImagePickerController.InfoKey.mediaURL] as? URL {
                // Handle the selected video
                onVideoPicked(videoURL)
            } else if let imageURL = info[UIImagePickerController.InfoKey.imageURL] as? URL {
                // Handle the selected image
                self.onImagePicked(imageURL)
            }
            presentationMode.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            presentationMode.dismiss()
        }
    }

    func makeCoordinator() -> Coordinator {
        return Coordinator(presentationMode: presentationMode,
                           sourceType: sourceType,
                           onImagePicked: { url in
            // Handle the selected image URL
            onImagePicked(url)
        },
                           onVideoPicked: { videoURL in
            // Handle the selected video URL
            onVideoPicked(videoURL)
        })
    }

    func makeUIViewController(context: UIViewControllerRepresentableContext<ImagePicker>) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = sourceType
        let mediaUploader = get_media_uploader(pubkey)
        picker.mediaTypes = ["public.image", "com.compuserve.gif"]
        if mediaUploader.supportsVideo && !imagesOnly {
            picker.mediaTypes.append("public.movie")
        }
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController,
                                context: UIViewControllerRepresentableContext<ImagePicker>) {

    }
}
