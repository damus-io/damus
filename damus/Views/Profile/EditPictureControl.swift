//
//  EditPictureControl.swift
//  damus
//
//  Created by Joel Klabo on 3/30/23.
//

import SwiftUI
import Kingfisher
import SwiftyCrop

// MARK: - Main view

/// A view that shows an existing picture, and allows a user to upload a new one.
struct EditPictureControl: View {
    
    // MARK: Type aliases
    
    typealias T = ImageUploadModel
    typealias Model = EditPictureControlViewModel<T>
    
    
    // MARK: Properties and state
    
    @StateObject var model: Model
    @Binding var current_image_url: URL?
    let style: Style
    let callback: (URL?) -> Void
    
    @Environment(\.dismiss) var dismiss
    
    
    // MARK: Initializers
    
    init(model: Model, style: Style? = nil, callback: @escaping (URL?) -> Void) {
        self._model = StateObject.init(wrappedValue: model)
        self.style = style ?? Style(size: nil, first_time_setup: false)
        self.callback = callback
        self._current_image_url = model.$current_image_url
    }
    
    init(
        uploader: any MediaUploaderProtocol,
        context: Model.Context,
        keypair: Keypair?,
        pubkey: Pubkey,
        style: Style? = nil,
        current_image_url: Binding<URL?>,
        upload_observer: ImageUploadingObserver? = nil,
        callback: @escaping (URL?) -> Void
    ) {
        let model = EditPictureControlViewModel(
            context: context,
            pubkey: pubkey,
            current_image_url: current_image_url,
            keypair: keypair,
            uploader: uploader,
            callback: callback
        )
        self.init(model: model, style: style, callback: callback)
    }
    
    
    // MARK: View definitions

    var body: some View {
        Menu {
            self.menu_options
        } label: {
            if self.style.first_time_setup {
                self.first_time_setup_view
            }
            else {
                self.default_view
            }
        }
        .sheet(isPresented: self.model.show_camera) {
            CameraController(uploader: model.uploader, mode: .handle_image(handler: { image in
                self.model.request_upload_authorization(PreUploadedMedia.uiimage(image))
            }))
        }
        .sheet(isPresented: self.model.show_library) {
            MediaPicker(mediaPickerEntry: .editPictureControl) { media in
                self.model.request_upload_authorization(media)
            }
        }
        .alert(
            NSLocalizedString("Are you sure you want to upload this image?", comment: "Alert message asking if the user wants to upload an image."),
            isPresented: Binding.constant(self.model.state.is_confirming_upload)
        ) {
            Button(NSLocalizedString("Upload", comment: "Button to proceed with uploading."), role: .none) {
                self.model.confirm_upload_authorization()
            }
            Button(NSLocalizedString("Cancel", comment: "Button to cancel the upload."), role: .cancel) {}
        }
        .fullScreenCover(isPresented: self.model.show_image_cropper) {
            self.image_cropper
        }
        .sheet(isPresented: self.model.show_url_sheet) {
            ImageURLSelector(callback: { url in
                self.model.choose_url(url)
            }, cancel: { self.model.cancel() })
            .presentationDetents([.height(300)])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: self.model.error_message, onDismiss: { self.model.cancel() }, content: { error in
            Text(error.rawValue)
        })
    }
    
    var progress_view: some View {
        ProgressView()
            .progressViewStyle(CircularProgressViewStyle(tint: DamusColors.purple))
            .frame(width: style.size, height: style.size)
            .padding(10)
            .background(DamusColors.white.opacity(0.7))
            .clipShape(Circle())
            .shadow(color: DamusColors.purple, radius: 15, x: 0, y: 0)
    }
    
    var menu_options: some View {
        Group {
            Button(action: { self.model.select_image_from_url() }) {
                Text("Image URL", comment: "Option to enter a url")
            }
            .accessibilityIdentifier(AppAccessibilityIdentifiers.own_profile_banner_image_edit_from_url.rawValue)
            
            Button(action: { self.model.select_image_from_library() }) {
                Text("Choose from Library", comment: "Option to select photo from library")
            }
            
            Button(action: { self.model.select_image_from_camera() }) {
                Text("Take Photo", comment: "Option to take a photo with the camera")
            }
        }
    }
    
    /// We show this on non-onboarding places such as profile edit page
    var default_view: some View {
        Group {
            switch self.model.state {
            case .uploading:
                self.progress_view
            default:
                Image("camera")
                    .resizable()
                    .scaledToFit()
                    .frame(width: style.size ?? 25, height: style.size ?? 25)
                    .foregroundColor(DamusColors.purple)
                    .padding(10)
                    .background(DamusColors.white.opacity(0.7))
                    .clipShape(Circle())
                    .background {
                        Circle()
                            .fill(DamusColors.purple, strokeBorder: .white, lineWidth: 2)
                    }
                    .shadow(radius: 3)
            }
        }
    }
    
    /// We show this on onboarding
    var first_time_setup_view: some View {
        Group {
            switch self.model.state {
            case .uploading:
                self.progress_view
            default:
                if let url = current_image_url {
                    KFAnimatedImage(url)
                        .imageContext(.pfp, disable_animation: false)
                        .onFailure(fallbackUrl: URL(string: robohash(model.pubkey)), cacheKey: url.absoluteString)
                        .cancelOnDisappear(true)
                        .configure { view in
                            view.framePreloadCount = 3
                        }
                        .scaledToFill()
                        .frame(width: (style.size ?? 25) + 30, height: (style.size ?? 25) + 30)
                        .kfClickable()
                        .foregroundColor(DamusColors.white)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(.white, lineWidth: 4))
                }
                else {
                    self.first_time_setup_no_image_view
                }
            }
        }
    }
    
    /// We show this on onboarding before the user enters any image
    var first_time_setup_no_image_view: some View {
        Image(systemName: "person.fill")
            .resizable()
            .scaledToFit()
            .frame(width: style.size, height: style.size)
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
                        width: max((style.size ?? 30)/3, 20),
                        height: max((style.size ?? 30)/3, 20)
                    )
                    .background(.damusDeepPurple)
                    .clipShape(Circle())
                    .padding(.leading, -10)
                    .padding(.top, -10)
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.2), radius: 4)
                , alignment: .bottomTrailing
            )
    }
    
    
    var crop_configuration: SwiftyCropConfiguration = SwiftyCropConfiguration(rotateImage: false, zoomSensitivity: 5)
    
    var image_cropper: some View {
        Group {
            if case .cropping(let preUploadedMedia) = model.state {
                switch preUploadedMedia {
                case .uiimage(let image):
                    SwiftyCropView(
                        imageToCrop: image,
                        maskShape: .circle
                    ) { croppedImage in
                        self.model.finished_cropping(croppedImage: croppedImage)
                    }
                case .unprocessed_image(let url), .processed_image(let url):
                    if let image = try? UIImage.from(url: url) {
                        SwiftyCropView(
                            imageToCrop: image,
                            maskShape: .circle,
                            configuration: crop_configuration
                        ) { croppedImage in
                            self.model.finished_cropping(croppedImage: croppedImage)
                        }
                    }
                    else {
                        self.cropping_error_screen  // Cannot load image
                    }
                case .unprocessed_video(_), .processed_video(_):
                    self.cropping_error_screen  // No support for video profile pictures
                }
            }
            else {
                self.cropping_error_screen  // Some form of internal logical inconsistency
            }
        }
    }
    
    var cropping_error_screen: some View {
        VStack(spacing: 5) {
            Text("Error while cropping image", comment: "Heading on cropping error page")
                .font(.headline)
            Text("Sorry, but for some reason there has been an issue while trying to crop this image. Please try again later. If the error persists, please contact [Damus support](mailto:support@damus.io)", comment: "Cropping error message")
            Button(action: { self.model.cancel() }, label: {
                Text("Dismiss", comment: "Button to dismiss error")
            })
        }
    }
}


// MARK: - View model


/// Tracks the state, and provides the logic needed for the EditPictureControl view
///
/// ## Implementation notes
///
/// - This makes it easier to test the logic as well as the view, and makes the view easier to work with by separating concerns.
@MainActor
class EditPictureControlViewModel<T: ImageUploadModelProtocol>: ObservableObject {
    // MARK: Properties
    // Properties are designed to reduce statefulness and hopefully increase predictability.
    
    /// The context of the upload. Is it a profile picture? A regular picture?
    let context: Context
    /// Pubkey of the user
    let pubkey: Pubkey
    /// The currently loaded image URL
    @Binding var current_image_url: URL?
    /// The state of the picture selection process
    @Published private(set) var state: PictureSelectionState
    /// User's keypair
    let keypair: Keypair?
    /// The uploader service to be used when uploading
    let uploader: any MediaUploaderProtocol
    /// An image upload observer, that can be set when the parent view wants to keep track of the upload process
    let image_upload_observer: ImageUploadingObserver?
    /// A callback to receive new image urls once the picture selection and upload is complete.
    let callback: (URL?) -> Void
    
    
    // MARK: Constants
    
    /// The desired profile image size
    var profile_image_size: CGSize = CGSize(width: 400, height: 400)
    
    
    // MARK: Initializers
    
    init(
        context: Context,
        pubkey: Pubkey,
        setup: Bool? = nil,
        current_image_url: Binding<URL?>,
        state: PictureSelectionState = .ready,
        keypair: Keypair?,
        uploader: any MediaUploaderProtocol,
        image_upload_observer: ImageUploadingObserver? = nil,
        callback: @escaping (URL?) -> Void
    ) {
        self.context = context
        self.pubkey = pubkey
        self._current_image_url = current_image_url
        self.state = state
        self.keypair = keypair
        self.uploader = uploader
        self.image_upload_observer = image_upload_observer
        self.callback = callback
    }
    
    
    // MARK: Convenience bindings to be used in views
    
    var show_camera: Binding<Bool> {
        Binding(
            get: { self.state.show_camera },
            set: { newShowCamera in
                switch self.state {
                case .selecting_picture_from_camera:
                    self.state = newShowCamera ? .selecting_picture_from_camera : .ready
                default:
                    if newShowCamera == true { self.state = .selecting_picture_from_camera }
                    else { return } // Leave state as-is
                }
            }
        )
    }
    
    var show_library: Binding<Bool> {
        Binding(
            get: { self.state.show_library },
            set: { newValue in
                switch self.state {
                case .selecting_picture_from_library:
                    self.state = newValue ? .selecting_picture_from_library : .ready
                default:
                    if newValue == true { self.state = .selecting_picture_from_library }
                    else { return } // Leave state as-is
                }
            }
        )
    }
    
    var show_url_sheet: Binding<Bool> {
        Binding(
            get: { self.state.show_url_sheet },
            set: { newValue in self.state = newValue ? .selecting_picture_from_url : .ready }
        )
    }
    
    var show_image_cropper: Binding<Bool> {
        Binding(
            get: { self.state.show_image_cropper },
            set: { newValue in
                switch self.state {
                case .cropping(let media):
                    self.state = newValue ? .cropping(media) : .ready
                default:
                    return // Leave state as-is
                }
            }
        )
    }
    
    fileprivate var error_message: Binding<IdentifiableString?> {
        Binding(
            get: { IdentifiableString(text: self.state.error_message) },
            set: { newValue in
                if let newValue {
                    self.state = .failed(message: newValue.rawValue)
                }
                else {
                    self.state = .ready
                }
            }
        )
    }
    
    
    // MARK: Control methods
    // These are methods to be used by the view or a test program to represent user actions.
    
    /// Ask user if they are sure they want to upload an image
    func request_upload_authorization(_ media: PreUploadedMedia) {
        self.state = .confirming_upload(media)
    }
    
    /// Confirm on behalf of the user that we have their permission to upload image
    func confirm_upload_authorization() {
        guard case .confirming_upload(let preUploadedMedia) = state else {
            return
        }
        switch self.context {
        case .normal:
            self.upload(media: preUploadedMedia)
        case .profile_picture:
            self.state = .cropping(preUploadedMedia)
        }
    }
    
    /// Indicate the image has finished being cropped. This will resize the image and upload it
    func finished_cropping(croppedImage: UIImage?) {
        guard let croppedImage else { return }
        let resizedCroppedImage = croppedImage.resized(to: profile_image_size)
        let newPreUploadedMedia: PreUploadedMedia = .uiimage(resizedCroppedImage)
        self.upload(media: newPreUploadedMedia)
    }
    
    /// Upload the media
    func upload(media: PreUploadedMedia) {
        if let mediaToUpload = generateMediaUpload(media) {
            self.handle_upload(media: mediaToUpload)
        }
        else {
            self.state = .failed(message: NSLocalizedString("Failed to generate media for upload. Please try again. If error persists, please contact Damus support at support@damus.io", comment: "Error label forming media for upload after user crops the image."))
        }
    }
    
    /// Cancel the picture selection process
    func cancel() {
        self.state = .ready
    }
    
    /// Mark the picture selection process as failed
    func failed(message: String) {
        self.state = .failed(message: message)
    }
    
    /// Choose an image based on a URL
    func choose_url(_ url: URL?) {
        self.current_image_url = url
        callback(url)
        self.state = .ready
    }
    
    /// Select an image from the gallery
    func select_image_from_library() {
        self.state = .selecting_picture_from_library
    }
    
    /// Select an image by taking a photo
    func select_image_from_camera() {
        self.state = .selecting_picture_from_camera
    }
    
    /// Select an image by specifying a URL
    func select_image_from_url() {
        self.state = .selecting_picture_from_url
    }
    
    
    // MARK: Internal logic
    
    /// Handles the upload process
    private func handle_upload(media: MediaUpload) {
        let image_upload = T()
        let upload_observer = ImageUploadingObserver()
        self.state = .uploading(media: media, upload: image_upload, uploadObserver: upload_observer)
        upload_observer.isLoading = true
        Task {
            let res = await image_upload.start(media: media, uploader: uploader, mediaType: self.context.mediaType, keypair: keypair)
            
            switch res {
            case .success(let urlString):
                let url = URL(string: urlString)
                current_image_url = url
                self.state = .ready
                callback(url)
            case .failed(let error):
                if let error {
                    Log.info("Error uploading profile image with error: %@", for: .image_uploading, error.localizedDescription)
                } else {
                    Log.info("Failed to upload profile image without error", for: .image_uploading)
                }
                self.state = .failed(message: NSLocalizedString("Error uploading profile image. Please check your internet connection and try again. If error persists, please contact Damus support (support@damus.io).", comment: "Error label when uploading profile image"))
            }
            upload_observer.isLoading = false
        }
    }
}


// MARK: - Helper views

/// A view that can be used for inputting a URL.
struct ImageURLSelector: View {
    @State var image_url_temp: String = ""
    @State var error: String? = nil
    @State var image_url: URL? = nil
    let callback: (URL?) -> Void
    let cancel: () -> Void
    
    var body: some View {
        ZStack {
            DamusColors.adaptableWhite.edgesIgnoringSafeArea(.all)
            VStack {
                Text("Image URL", comment: "Label for image url text field")
                    .bold()
                
                Divider()
                    .padding(.horizontal)
                
                HStack {
                    Image(systemName: "doc.on.clipboard")
                        .foregroundColor(.gray)
                        .onTapGesture {
                            if let pastedURL = UIPasteboard.general.string {
                                image_url_temp = URL(string: pastedURL)?.absoluteString ?? ""
                            }
                        }
                    TextField(image_url_temp, text: $image_url_temp)
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
                
                if let error {
                    Text(error)
                        .foregroundStyle(.red)
                }
                
                Button(action: {
                    self.cancel()
                }, label: {
                    Text("Cancel", comment: "Cancel button text for dismissing updating image url.")
                        .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
                        .padding(10)
                })
                .buttonStyle(NeutralButtonStyle())
                .padding(10)
                
                Button(action: {
                    guard let the_url = URL(string: image_url_temp) else {
                        error = NSLocalizedString("Invalid URL", comment: "Error label when user enters an invalid URL")
                        return
                    }
                    image_url = the_url
                    callback(the_url)
                }, label: {
                    Text("Update", comment: "Update button text for updating image url.")
                        .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
                })
                .buttonStyle(GradientButtonStyle(padding: 10))
                .padding(.horizontal, 10)
                .disabled(image_url_temp == image_url?.absoluteString)
                .opacity(image_url_temp == image_url?.absoluteString ? 0.5 : 1)
            }
        }
        .onAppear {
            image_url_temp = image_url?.absoluteString ?? ""
        }
    }
}

// MARK: - Helper structures

extension EditPictureControlViewModel {
    /// Tracks the state of the picture selection process in the picture control view and provides convenient computed properties for the view
    ///
    /// ## Implementation notes
    ///
    /// Made as an enum with associated values to reduce the amount of independent variables in the view model, and enforce the presence of certain values in certain steps of the process.
    enum PictureSelectionState {
        case ready
        case selecting_picture_from_library
        case selecting_picture_from_url
        case selecting_picture_from_camera
        case confirming_upload(PreUploadedMedia)
        case cropping(PreUploadedMedia)
        case uploading(media: MediaUpload, upload: any ImageUploadModelProtocol, uploadObserver: ImageUploadingObserver)
        case failed(message: String)
        
        // MARK: Convenience computed properties
        // Translates the information in the state, in a way that does not introduce further statefulness
        
        var is_confirming_upload: Bool { self.step == .confirming_upload }
        var show_image_cropper: Bool { self.step == .cropping }
        var show_library: Bool { self.step == .selecting_picture_from_library }
        var show_camera: Bool { self.step == .selecting_picture_from_camera }
        var show_url_sheet: Bool { self.step == .selecting_picture_from_url }
        var is_uploading: Bool { self.step == .uploading }
        var error_message: String? { if case .failed(let message) = self { return message } else { return nil } }
        var step: Step {
            switch self {
            case .ready: .ready
            case .selecting_picture_from_library: .selecting_picture_from_library
            case .selecting_picture_from_url: .selecting_picture_from_url
            case .selecting_picture_from_camera: .selecting_picture_from_camera
            case .confirming_upload(_): .confirming_upload
            case .cropping(_): .cropping
            case .uploading(_,_,_): .uploading
            case .failed(_): .failed
            }
        }
        
        /// Tracks the specific step of the picture selection state, without any associated values, to make easy comparisons on where in the process we are
        enum Step: String, RawRepresentable, Equatable {
            case ready
            case selecting_picture_from_library
            case selecting_picture_from_url
            case selecting_picture_from_camera
            case confirming_upload
            case cropping
            case uploading
            case failed
        }
    }
}

extension EditPictureControlViewModel {
    /// Defines the context of this picture. Is it a profile picture? A normal picture?
    enum Context {
        case normal
        case profile_picture
        
        var mediaType: ImageUploadMediaType {
            switch self {
                case .normal: .normal
                case .profile_picture: .profile_picture
            }
        }
    }
}

/// An object that can be used for tracking the status of an upload across the view hierarchy.
/// For example, a parent view can instantiate this object and pass it to a child view that handles uploads,
/// and that parent view can change its own style accordingly
///
/// ## Implementation note:
///
/// It would be correct to put this entire class in the MainActor, but for some reason adding `@MainActor` crashes the Swift compiler with no helpful messages (on Xcode 16.2 (16C5032a)), so individual members of this class need to be manually put into the main actor.
//@MainActor
class ImageUploadingObserver: ObservableObject {
    @MainActor @Published var isLoading: Bool = false
}

fileprivate struct IdentifiableString: Identifiable, RawRepresentable {
    var id: String { return rawValue }
    typealias RawValue = String
    var rawValue: String
    
    init?(rawValue: String) {
        self.rawValue = rawValue
    }
    
    init?(text: String?) {
        guard let text else { return nil }
        self.rawValue = text
    }
}

extension EditPictureControl {
    struct Style {
        let size: CGFloat?
        let first_time_setup: Bool
    }
}

// MARK: - Convenience extensions

fileprivate extension UIImage {
    /// Convenience function to easily get an UIImage from a URL
    static func from(url: URL) throws -> UIImage? {
        let data = try Data(contentsOf: url)
        return UIImage(data: data)
    }
}

// MARK: - Previews

struct EditPictureControl_Previews: PreviewProvider {
    static var previews: some View {
        let url = Binding<URL?>.constant(URL(string: "https://damus.io")!)
        ZStack {
            Color.gray
            EditPictureControl(uploader: MediaUploader.nostrBuild, context: .profile_picture, keypair: test_keypair, pubkey: test_pubkey, style: .init(size: 100, first_time_setup: false), current_image_url: url) { _ in
                //
            }
        }
    }
}
