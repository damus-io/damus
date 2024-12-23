//
//  EditPictureControl.swift
//  damus
//
//  Created by Joel Klabo on 3/30/23.
//

import SwiftUI
import Kingfisher
import SwiftyCrop

class ImageUploadingObserver: ObservableObject {
    @Published var isLoading: Bool = false
}

struct EditPictureControl: View {
    let uploader: MediaUploader
    let context: Context
    let keypair: Keypair?
    let pubkey: Pubkey
    var size: CGFloat? = 25
    var setup: Bool? = false
    @Binding var image_url: URL?
    @State var image_url_temp: URL?
    @ObservedObject var uploadObserver: ImageUploadingObserver
    let callback: (URL?) -> Void
    
    @State var state: PictureControlState = .no_picture
    
    @Environment(\.dismiss) var dismiss
    
    enum PictureControlState {
        case no_picture
        case selecting_picture_from_library
        case selecting_picture_from_url
        case selecting_picture_from_camera
        case confirming_upload(PreUploadedMedia)
        case cropping(PreUploadedMedia)
        case uploading(media: MediaUpload, upload: ImageUploadModel)
        case failed
        
        var is_confirming_upload: Bool {
            guard case .confirming_upload = self else { return false }
            return true
        }
        
        var show_image_cropper: Bool {
            guard case .cropping = self else { return false }
            return true
        }
        
        var show_library: Bool {
            guard case .selecting_picture_from_library = self else { return false }
            return true
        }
        
        var show_camera: Bool {
            guard case .selecting_picture_from_camera = self else { return false }
            return true
        }
        
        var show_url_sheet: Bool {
            guard case .selecting_picture_from_camera = self else { return false }
            return true
        }
    }
    
    var show_camera: Binding<Bool> {
        Binding(get: {
            return self.state.show_camera
        }, set: { newShowCamera in
            if newShowCamera {
                self.state = .selecting_picture_from_camera
            }
            else {
                self.state = .no_picture
            }
        })
    }
    
    var show_library: Binding<Bool> {
        Binding(get: {
            return self.state.show_library
        }, set: { newValue in
            if newValue {
                self.state = .selecting_picture_from_library
            }
            else {
                self.state = .no_picture
            }
        })
    }
    
    var show_url_sheet: Binding<Bool> {
        Binding(get: {
            return self.state.show_url_sheet
        }, set: { newValue in
            if newValue {
                self.state = .selecting_picture_from_url
            }
            else {
                self.state = .no_picture
            }
        })
    }
    
    var crop_configuration: SwiftyCropConfiguration {
        return SwiftyCropConfiguration(rotateImage: false, zoomSensitivity: 5)
    }
    
    enum Context {
        case normal
        case profile_picture
        
        var mediaType: ImageUploadMediaType {
            switch self {
                case .normal:
                    .normal
                case .profile_picture:
                    .profile_picture
            }
        }
    }

    var body: some View {
        Menu {
            Button(action: {
                self.state = .selecting_picture_from_url
            }) {
                Text("Image URL", comment: "Option to enter a url")
            }
            .accessibilityIdentifier(AppAccessibilityIdentifiers.own_profile_banner_image_edit_from_url.rawValue)
            
            Button(action: {
                self.state = .selecting_picture_from_library
            }) {
                Text("Choose from Library", comment: "Option to select photo from library")
            }
            
            Button(action: {
                self.state = .selecting_picture_from_camera
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
                    .frame(width: (size ?? 25) + 30, height: (size ?? 25) + 30)
                    .kfClickable()
                    .foregroundColor(DamusColors.white)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 4))
            } else {
                if setup ?? false {
                    Image(systemName: "person.fill")
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
                        .overlay(
                            Image(systemName: "plus.circle.fill")
                                .resizable()
                                .frame(
                                    width: max((size ?? 30)/3, 20),
                                    height: max((size ?? 30)/3, 20)
                                )
                                .background(.damusDeepPurple)
                                .clipShape(Circle())
                                .padding(.leading, -10)
                                .padding(.top, -10)
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.2), radius: 4)
                        , alignment: .bottomTrailing)
                        
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
        .sheet(isPresented: self.show_camera) {
            CameraController(uploader: uploader) {
                self.state = .selecting_picture_from_library
            }
        }
        .sheet(isPresented: Binding.constant(self.state.show_library)) {
            MediaPicker(mediaPickerEntry: .editPictureControl) { media in
                self.state = .confirming_upload(media)
            }
        }
        .alert(NSLocalizedString("Are you sure you want to upload this image?", comment: "Alert message asking if the user wants to upload an image."),
               isPresented: Binding.constant(self.state.is_confirming_upload)) {
            Button(NSLocalizedString("Upload", comment: "Button to proceed with uploading."), role: .none) {
                if case .confirming_upload(let preUploadedMedia) = state {
                    self.state = .cropping(preUploadedMedia)
                }
            }
            Button(NSLocalizedString("Cancel", comment: "Button to cancel the upload."), role: .cancel) {}
        }
        .fullScreenCover(isPresented: Binding.constant(self.state.show_image_cropper)) {
            if case .cropping(let preUploadedMedia) = state {
                switch preUploadedMedia {
                case .uiimage(let image):
                    SwiftyCropView(
                        imageToCrop: image,
                        maskShape: .circle
                    ) { croppedImage in
                        guard let croppedImage else { return }
                        let newPreUploadedMedia: PreUploadedMedia = .uiimage(croppedImage)
                        if let mediaToUpload = generateMediaUpload(newPreUploadedMedia) {
                            self.handle_upload(media: mediaToUpload)
                        }
                        else {
                            self.state = .failed
                        }
                    }
                case .unprocessed_image(let url), .processed_image(let url):
                    if let image = try? UIImage.from(url: url) {
                        SwiftyCropView(
                            imageToCrop: image,
                            maskShape: .circle,
                            configuration: crop_configuration
                        ) { croppedImage in
                            guard let croppedImage else { return }
                            guard let resizedCroppedImage = resizeImage(image: croppedImage, targetSize: CGSize(width: 400, height: 400)) else { return }
                            let newPreUploadedMedia: PreUploadedMedia = .uiimage(croppedImage)
                            if let mediaToUpload = generateMediaUpload(newPreUploadedMedia) {
                                self.handle_upload(media: mediaToUpload)
                            }
                            else {
                                self.state = .failed
                            }
                        }
                    }
                    else {
                        Text("Error loading image")
                    }
                default:
                    Text("Nothing to crop?")
                }
            }
            else {
                Text("Nothing to crop?")
            }
        }
        .sheet(isPresented: self.show_url_sheet) {
            ZStack {
                DamusColors.adaptableWhite.edgesIgnoringSafeArea(.all)
                VStack {
                    Text("Image URL")
                        .bold()
                    
                    Divider()
                        .padding(.horizontal)
                    
                    HStack {
                        Image(systemName: "doc.on.clipboard")
                            .foregroundColor(.gray)
                            .onTapGesture {
                                if let pastedURL = UIPasteboard.general.string {
                                    image_url_temp = URL(string: pastedURL)
                                }
                            }
                        TextField(image_url_temp?.absoluteString ?? "", text: Binding(
                            get: { image_url_temp?.absoluteString ?? "" },
                            set: { image_url_temp = URL(string: $0) }
                        ))
                    }
                    .padding(12)
                    .background {
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(.gray.opacity(0.5), lineWidth: 1)
                            .background {
                                RoundedRectangle(cornerRadius: 12)
                                    .foregroundColor(.damusAdaptableWhite)
                            }
                    }
                    .padding(10)
                    
                    Button(action: {
                        self.state = .no_picture
                    }, label: {
                        Text("Cancel", comment: "Cancel button text for dismissing updating image url.")
                            .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
                            .padding(10)
                    })
                    .buttonStyle(NeutralButtonStyle())
                    .padding(10)
                    
                    Button(action: {
                        image_url = image_url_temp
                        callback(image_url)
                        self.state = .no_picture
                    }, label: {
                        Text("Update", comment: "Update button text for updating image url.")
                            .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
                    })
                    .buttonStyle(GradientButtonStyle(padding: 10))
                    .padding(.horizontal, 10)
                    .disabled(image_url_temp == image_url)
                    .opacity(image_url_temp == image_url ? 0.5 : 1)
                }
            }
            .onAppear {
                image_url_temp = image_url
            }
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
        }
    }
    
    private func handle_upload(media: MediaUpload) {
        let image_upload = ImageUploadModel()
        self.state = .uploading(media: media, upload: image_upload)
        uploadObserver.isLoading = true
        Task {
            let res = await image_upload.start(media: media, uploader: uploader, mediaType: self.context.mediaType, keypair: keypair)
            
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
            EditPictureControl(uploader: .nostrBuild, context: .profile_picture, keypair: test_keypair, pubkey: test_pubkey, size: 100, setup: false, image_url: url, uploadObserver: observer) { _ in
                //
            }
        }
    }
}

func resizeImage(image: UIImage, targetSize: CGSize) -> UIImage? {
    let size = image.size

    let widthRatio  = targetSize.width  / size.width
    let heightRatio = targetSize.height / size.height

    // Determine the scale factor that preserves aspect ratio
    let scaleFactor = min(widthRatio, heightRatio)
    
    let scaledImageSize = CGSize(
        width: size.width * scaleFactor,
        height: size.height * scaleFactor
    )

    let renderer = UIGraphicsImageRenderer(size: scaledImageSize)
    
    let scaledImage = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: scaledImageSize))
    }

    return scaledImage
}

extension UIImage {
    static func from(url: URL) throws -> UIImage? {
        let data = try Data(contentsOf: url)
        return UIImage(data: data)
    }
}
