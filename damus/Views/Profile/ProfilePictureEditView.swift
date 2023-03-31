//
//  ProfilePictureEditView.swift
//  damus
//
//  Created by Joel Klabo on 3/30/23.
//

import SwiftUI

struct ProfilePictureEditView: View {
    
    @StateObject var account: CreateAccountModel
    @StateObject var image_upload: ImageUploadModel = ImageUploadModel()

    
    @State private var show_camera = false
    @State private var show_library = false

    var body: some View {
        Menu {
            Button(action: {
                self.show_library = true
            }) {
                Text("Choose from Library")
            }
            
            Button(action: {
                self.show_camera = true
            }) {
                Text("Take Photo")
            }
        } label: {
            Image(systemName: "camera")
                .resizable()
                .scaledToFit()
                .frame(width: 25, height: 25)
                .foregroundColor(DamusColors.white)
        }
        .sheet(isPresented: $show_camera) {
            PostView.ImagePicker(sourceType: .camera, pubkey: account.pubkey, imagesOnly: true) { img in
                handle_upload(media: .image(img))
            } onVideoPicked: { url in
                print("Cannot upload videos as profile image")
            }
        }
        .sheet(isPresented: $show_library) {
            PostView.ImagePicker(sourceType: .photoLibrary, pubkey: account.pubkey, imagesOnly: true) { img in
                handle_upload(media: .image(img))
            } onVideoPicked: { url in
                print("Cannot upload videos as profile image")
            }
        }
    }
    
    private func handle_upload(media: MediaUpload) {
        let uploader = get_media_uploader(account.pubkey)
        
        Task {
            let res = await image_upload.start(media: media, uploader: uploader)
            
            switch res {
            case .success(let url):
                print("GOT URL: \(url)")
                account.profile_image = url
                
            case .failed(let error):
                if let error {
                    print("Error uploading profile image \(error.localizedDescription)")
                } else {
                    print("Error uploading image :(")
                }
            }
        }
    }
}

struct ProfilePictureEditView_Previews: PreviewProvider {
    static var previews: some View {
        let model = CreateAccountModel(real: "", nick: "jb55", about: "")
        ProfilePictureEditView(account: model)
    }
}
