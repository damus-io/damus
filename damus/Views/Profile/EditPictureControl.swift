//
//  EditPictureControl.swift
//  damus
//
//  Created by Joel Klabo on 3/30/23.
//

import SwiftUI
import Kingfisher

class ImageUploadingObserver: ObservableObject {
    @Published var isLoading: Bool = false
}

struct EditPictureControl: View {
    let uploader: MediaUploader
    let pubkey: Pubkey
    var size: CGFloat? = 25
    var setup: Bool? = false
    @Binding var image_url: URL?
    @ObservedObject var uploadObserver: ImageUploadingObserver
    let callback: (URL?) -> Void
    
    @StateObject var image_upload: ImageUploadModel = ImageUploadModel()
    
    @State private var show_camera = false
    @State private var show_library = false
    @State private var show_url_sheet = false
    @State var image_upload_confirm: Bool = false

    @State var preUploadedMedia: PreUploadedMedia? = nil
    
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Menu {
            Button(action: {
                self.show_url_sheet = true
            }) {
                Text("Image URL", comment: "Option to enter a url")
            }
            
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
                    .progressViewStyle(CircularProgressViewStyle(tint: DamusColors.purple))
                    .frame(width: size, height: size)
                    .padding(10)
                    .background(DamusColors.white.opacity(0.7))
                    .clipShape(Circle())
                    .shadow(color: DamusColors.purple, radius: 15, x: 0, y: 0)
            } else if let url = image_url, setup ?? false {
                KFAnimatedImage(url)
                    .imageContext(.pfp, disable_animation: false)
                    .onFailure(fallbackUrl: URL(string: robohash(pubkey)), cacheKey: url.absoluteString)
                    .cancelOnDisappear(true)
                    .configure { view in
                        view.framePreloadCount = 3
                    }
                    .scaledToFill()
                    .frame(width: (size ?? 25) + 10, height: (size ?? 25) + 10)
                    .foregroundColor(DamusColors.white)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 4))
            } else {
                if setup ?? false {
                    Image(systemName: "person")
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .foregroundColor(DamusColors.white)
                        .padding(20)
                        .clipShape(Circle())
                        .background {
                            Circle()
                                .fill(PinkGradient, strokeBorder: .white, lineWidth: 4)
                        }
                        
                } else {
                    Image("camera")
                        .resizable()
                        .scaledToFit()
                        .frame(width: size, height: size)
                        .foregroundColor(DamusColors.purple)
                        .padding(10)
                        .background(DamusColors.white.opacity(0.7))
                        .clipShape(Circle())
                        .background {
                            Circle()
                                .fill(DamusColors.purple, strokeBorder: .white, lineWidth: 2)
                        }
                }
                    
            }
        }
        .sheet(isPresented: $show_camera) {
            CameraController(uploader: uploader) {
                self.show_camera = false
                self.show_library = true
            }
        }
        .sheet(isPresented: $show_library) {
            MediaPicker(image_upload_confirm: $image_upload_confirm, imagesOnly: true) { media in
                self.preUploadedMedia = media
            }
            .alert(NSLocalizedString("Are you sure you want to upload this image?", comment: "Alert message asking if the user wants to upload an image."), isPresented: $image_upload_confirm) {
                Button(NSLocalizedString("Upload", comment: "Button to proceed with uploading."), role: .none) {
                    if let mediaToUpload = generateMediaUpload(preUploadedMedia) {
                        self.handle_upload(media: mediaToUpload)
                        self.show_library = false
                    }
                }
                Button(NSLocalizedString("Cancel", comment: "Button to cancel the upload."), role: .cancel) {}
            }
        }
        .sheet(isPresented: $show_url_sheet) {
            VStack {
                Text("Update image URL")
                    .bold()
                
                HStack {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundColor(.gray)
                        .onTapGesture {
                            if let pastedURL = UIPasteboard.general.string {
                                image_url = URL(string: pastedURL)
                            }
                        }
                    TextField(image_url?.absoluteString ?? "", text: Binding(
                        get: { image_url?.absoluteString ?? "" },
                        set: { image_url = URL(string: $0) }
                    ))
                }
                .padding(15)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.gray.opacity(0.5), lineWidth: 1)
                        .background {
                            RoundedRectangle(cornerRadius: 12)
                                .foregroundColor(.damusAdaptableWhite)
                        }
                }
                .padding()
                
                Button(action: {
                    dismiss()
                }, label: {
                    Text("Cancel", comment: "Cancel button text for dismissing updating image url.")
                        .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
                        .padding(10)
                })
                .buttonStyle(NeutralButtonStyle())
                .padding(10)
                
                Button(action: {
                    
                    dismiss()
                }, label: {
                    Text("Update", comment: "Save button text for saving profile status settings.")
                        .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
                })
                .buttonStyle(GradientButtonStyle())
                .padding(10)
            }
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
        }
    }
    
    private func handle_upload(media: MediaUpload) {
        uploadObserver.isLoading = true
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

struct EditPictureControl_Previews: PreviewProvider {
    static var previews: some View {
        let url = Binding<URL?>.constant(URL(string: "https://damus.io")!)
        let observer = ImageUploadingObserver()
        ZStack {
            Color.gray
            EditPictureControl(uploader: .nostrBuild, pubkey: test_pubkey, size: 100, setup: false, image_url: url, uploadObserver: observer) { _ in
                //
            }
        }
    }
}
