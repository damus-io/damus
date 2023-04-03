//
//  EditPictureControl.swift
//  damus
//
//  Created by Joel Klabo on 3/30/23.
//

import SwiftUI

struct EditPictureControl: View {
    
    let pubkey: String
    @Binding var image_url: URL?
    @ObservedObject var uploadObserver: ImageUploadingObserver
    let callback: (URL?) -> Void
    
    @StateObject var image_upload: ImageUploadModel = ImageUploadModel()
    
    @State private var show_camera = false
    @State private var show_library = false
    @State var image_upload_confirm: Bool = false

    var body: some View {
        Menu {
            Button(action: {
                self.show_library = true
            }) {
                Text("Choose from Library", comment: "Option to select photo from library")
            }
            
            Button(action: {
                self.show_camera = true
            }) {
                Text("Take Photo", comment: "Option to take a photo with the camera")
            }
        } label: {
            if uploadObserver.isLoading {
                ProgressView()
            } else {
                Image(systemName: "camera")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 25, height: 25)
                    .foregroundColor(DamusColors.white)
            }
        }
        .sheet(isPresented: $show_camera) {
            // The alert may not be required for the profile pic upload case. Not showing the confirm check alert for this scenario
            ImagePicker(sourceType: .camera, pubkey: pubkey, image_upload_confirm: $image_upload_confirm, imagesOnly: true) { img in
                handle_upload(media: .image(img))
            } onVideoPicked: { url in
                print("Cannot upload videos as profile image")
            }
        }
        .sheet(isPresented: $show_library) {
            // The alert may not be required for the profile pic upload case. Not showing the confirm check alert for this scenario
            ImagePicker(sourceType: .photoLibrary, pubkey: pubkey, image_upload_confirm: $image_upload_confirm, imagesOnly: true) { img in
                handle_upload(media: .image(img))
            } onVideoPicked: { url in
                print("Cannot upload videos as profile image")
            }
        }
    }
    
    private func handle_upload(media: MediaUpload) {
        uploadObserver.isLoading = true
        let uploader = get_media_uploader(pubkey)
        Task {
            let res = await image_upload.start(media: media, uploader: uploader)
            
            switch res {
            case .success(let urlString):
                let url = URL(string: urlString)
                image_url = url
                callback(url)
            case .failed(let error):
                if let error {
                    print("Error uploading profile image \(error.localizedDescription)")
                } else {
                    print("Error uploading image :(")
                }
                callback(nil)
            }
            uploadObserver.isLoading = false
        }
    }
}
