//
//  ImageCarousel.swift
//  damus
//
//  Created by William Casarin on 2022-10-16.
//

import SwiftUI
import Kingfisher
import Combine

// TODO: all this ShareSheet complexity can be replaced with ShareLink once we update to iOS 16
struct ShareSheet: UIViewControllerRepresentable {
    typealias Callback = (_ activityType: UIActivity.ActivityType?, _ completed: Bool, _ returnedItems: [Any]?, _ error: Error?) -> Void
    
    let activityItems: [URL?]
    let callback: Callback? = nil
    let applicationActivities: [UIActivity]? = nil
    let excludedActivityTypes: [UIActivity.ActivityType]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems as [Any],
            applicationActivities: applicationActivities)
        controller.excludedActivityTypes = excludedActivityTypes
        controller.completionWithItemsHandler = callback
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // nothing to do here
    }
}

//  Custom UIPageControl
struct PageControlView: UIViewRepresentable {
    @Binding var currentPage: Int
    var numberOfPages: Int
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UIPageControl {
        let uiView = UIPageControl()
        uiView.backgroundStyle = .minimal
        uiView.currentPageIndicatorTintColor = UIColor(Color("DamusPurple"))
        uiView.pageIndicatorTintColor = UIColor(Color("DamusLightGrey"))
        uiView.currentPage = currentPage
        uiView.numberOfPages = numberOfPages
        uiView.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged), for: .valueChanged)
        return uiView
    }

    func updateUIView(_ uiView: UIPageControl, context: Context) {
        uiView.currentPage = currentPage
        uiView.numberOfPages = numberOfPages
    }
}

extension PageControlView {
    final class Coordinator: NSObject {
        var parent: PageControlView
        
        init(_ parent: PageControlView) {
            self.parent = parent
        }
        
        @objc func valueChanged(sender: UIPageControl) {
            let currentPage = sender.currentPage
            withAnimation {
                parent.currentPage = currentPage
            }
        }
    }
}


enum ImageShape {
    case square
    case landscape
    case portrait
    case unknown
    
    static func determine_image_shape(_ size: CGSize) -> ImageShape {
        guard size.height > 0 else {
            return .unknown
        }
        let imageRatio = size.width / size.height
        switch imageRatio {
            case 1.0: return .square
            case ..<1.0: return .portrait
            case 1.0...: return .landscape
            default: return .unknown
        }
    }
}

/// The `CarouselModel` helps `ImageCarousel` with some state management logic, keeping track of media sizes, and the ideal display size
///
/// This model is necessary because the state management logic required to keep track of media sizes for each one of the carousel items,
/// and the ideal display size at each moment is not a trivial task.
///
/// The rules for the media fill are as follows:
///  1. The media item should generally have a width that completely fills the width of its parent view
///  2. The height of the carousel should be adjusted accordingly
///  3. The only exception to rules 1 and 2 is when the total height would be 20% larger than the height of the device
///  4. If none of the above can be computed (e.g. due to missing information), default to a reasonable height, where the media item will fit into.
///
/// ## Usage notes
///
/// The view is has the following state management responsibilities:
///  1. Watching the size of the images (via the `.observe_image_size` modifier)
///  2. Notifying this class of geometry reader changes, by setting `geo_size`
///
/// ## Implementation notes
///
/// This class is organized in a way to reduce stateful behavior and the transiency bugs it can cause.
///
/// This is accomplished through the following pattern:
/// 1. The `current_item_fill` is a published property so that any updates instantly re-render the view
/// 2. However, `current_item_fill` has a mathematical dependency on other members of this class
/// 3. Therefore, the members on which the fill property depends on all have `didSet` observers that will cause the `current_item_fill` to be recalculated and published.
///
/// This pattern helps ensure that the state is always consistent and that the view is always up-to-date.
/// 
/// This class is marked as `@MainActor` since most of its properties are published and should be accessed from the main thread to avoid inconsistent SwiftUI state during renders
@MainActor
class CarouselModel: ObservableObject {
    // MARK: Immutable object attributes
    // These are some attributes that are not expected to change throughout the lifecycle of this object
    // These should not be modified after initialization to avoid state inconsistency
    
    /// The state of the app
    let damus_state: DamusState
    /// All urls in the carousel
    let urls: [MediaUrl]
    /// The default fill height for the carousel, if we cannot calculate a more appropriate height
    /// **Usage note:** Default to this when `current_item_fill` is nil
    let default_fill_height: CGFloat
    /// The maximum height for any carousel item
    let max_height: CGFloat
    
    
    // MARK: Miscellaneous
    
    /// Holds items that allows us to cancel video size observers during de-initialization
    private var all_cancellables: [AnyCancellable] = []
    
    
    // MARK: State management properties
    /// Properties relevant to state management. 
    /// These should be made into computed/functional properties when possible to avoid stateful behavior
    /// When that is not possible (e.g. when dealing with an observed published property), establish its mathematical dependencies, 
    /// and use `didSet` observers to ensure that the state is always re-computed when necessary.

    /// Stores information about the size of each media item in `urls`.
    /// **Usage note:** The view is responsible for setting the size of image urls
    var media_size_information: [URL: CGSize] {
        didSet {
            guard let current_url else { return }
            // Upon updating information, update the carousel fill size if the size for the current url has changed
            if oldValue[current_url] != media_size_information[current_url] {
                self.refresh_current_item_fill()
                self.refresh_first_item_height()
            }
        }
    }
    /// Stores information about the geometry reader
    /// **Usage note:** The view is responsible for setting this value
    var geo_size: CGSize? {
        didSet { self.refresh_current_item_fill() }
    }
    /// The index of the currently selected item
    /// **Usage note:** The view is responsible for setting this value
    @Published var selectedIndex: Int {
        didSet { self.refresh_current_item_fill() }
    }
    /// The current fill for the media item.
    /// **Usage note:** This property is read-only and should not be set directly. Update `selectedIndex` to update the current item being viewed.
    var current_url: URL? {
        return urls[safe: selectedIndex]?.url
    }
    /// Holds the ideal fill dimensions for the current item.
    /// **Usage note:** This property is automatically updated when other properties are set, and should not be set directly
    /// **Implementation note:** This property is mathematically dependent on geo_size, media_size_information, and `selectedIndex`, 
    ///   and is automatically updated upon changes to these properties.
    @Published private(set) var current_item_fill: ImageFill?
    
    /// Holds the ideal fill dimensions for the first item in the carousel.
    /// This is used to maintain a consistent height for the carousel when swiping between images.
    /// **Usage note:** This property is automatically updated when other properties are set, and should not be set directly.
    /// **Implementation note:** This property ensures the carousel maintains a consistent height based on the first image,
    /// preventing the UI from "jumping" when swiping between images of different aspect ratios.
    @Published private(set) var first_image_fill: ImageFill?
    
    
    // MARK: Initialization and de-initialization

    /// Initializes the `CarouselModel` with the given `DamusState` and `MediaUrl` array
    init(damus_state: DamusState, urls: [MediaUrl]) {
        // Immutable object attributes
        self.damus_state = damus_state
        self.urls = urls
        self.default_fill_height = 350
        self.max_height = UIScreen.main.bounds.height * 1.2 // 1.2
        
        // State management properties
        self.selectedIndex = 0
        self.current_item_fill = nil
        self.geo_size = nil
        self.media_size_information = [:]
        
        // Setup the rest of the state management logic
        self.observe_video_sizes()
        Task {
            self.refresh_current_item_fill()
            self.refresh_first_item_height()
        }
    }
    
    /// This private function observes the video sizes for all videos
    private func observe_video_sizes() {
        for media_url in urls {
            switch media_url {
                case .video(let url):
                    let video_player = damus_state.video.get_player(for: url)
                    if let video_size = video_player.video_size {
                        self.media_size_information[url] = video_size  // Set the initial size if available
                    }
                    let observer_cancellable = video_player.$video_size.sink(receiveValue: { new_size in
                        self.media_size_information[url] = new_size    // Update the size when it changes
                    })
                    all_cancellables.append(observer_cancellable)      // Store the cancellable to cancel it later
                case .image(_):
                    break;  // Observing an image size needs to be done on the view directly, through the `.observe_image_size` modifier
            }
        }
    }
    
    deinit {
        for cancellable_item in all_cancellables {
            cancellable_item.cancel()
        }
    }
    
    // MARK: State management and logic

    /// This function refreshes the current item fill based on the current state of the model
    /// **Usage note:** This is private, do not call this directly from outside the class.
    /// **Implementation note:** This should be called using `didSet` observers on properties that affect the fill
    private func refresh_current_item_fill() {
        self.current_item_fill = self.compute_item_fill(url: current_url)
    }
    
    /// Computes the image fill properties for a given URL without side effects.
    /// This is a pure function that calculates the appropriate fill dimensions based on image size and container constraints.
    /// **Usage note:** This is a helper method used by both `refresh_current_item_fill` and `refresh_first_item_height`.
    private func compute_item_fill(url: URL?) -> ImageFill? {
        if let url,
           let item_size = self.media_size_information[url],
           let geo_size {
            return ImageFill.calculate_image_fill(
                geo_size: geo_size,
                img_size: item_size,
                maxHeight: self.max_height,
                fillHeight: self.default_fill_height
            )
        }
        else {
            return nil    // Not enough information to compute the proper fill. Default to nil
        }
    }
    
    /// This function refreshes the first item height based on the current state of the model
    /// **Usage note:** This is private, do not call this directly from outside the class.
    /// **Implementation note:** This should be called using `didSet` observers on properties that affect the height.
    /// When the first image dimensions change, this ensures the carousel maintains consistent dimensions.
    private func refresh_first_item_height() {
        self.first_image_fill = self.compute_first_item_fill()
    }
    
    /// Computes the first item fill with no side-effects.
    /// **Usage note:** Not to be used outside the class. Use the `first_image_fill` property instead.
    /// **Implementation note:** This retrieves the first URL from the carousel and computes its fill properties
    /// to establish a consistent height for the entire carousel.
    private func compute_first_item_fill() -> ImageFill? {
        guard let first_url = urls[safe: 0] else { return nil }
        return self.compute_item_fill(url: first_url.url)
    }
}

// MARK: - Image Carousel

/// A carousel that displays images and videos
/// 
/// ## Implementation notes
/// 
/// - State management logic is mostly handled by `CarouselModel`, as it is complex, and becomes difficult to manage in a view
///
@MainActor
struct ImageCarousel<Content: View>: View {
    /// The event id of the note that this carousel is displaying
    let evid: NoteId
    /// The model that holds information and state of this carousel
    /// This is observed to update the view when the model changes
    @ObservedObject var model: CarouselModel
    @ObservedObject var settings: UserSettingsStore
    @StateObject private var networkMonitor = NetworkMonitor.shared
    let content: ((_ dismiss: @escaping (() -> Void)) -> Content)?

    init(state: DamusState, evid: NoteId, urls: [MediaUrl]) {
        self.evid = evid
        self._model = ObservedObject(initialValue: CarouselModel(damus_state: state, urls: urls))
        self.settings = state.settings
        self.content = nil
    }
    
    init(state: DamusState, evid: NoteId, urls: [MediaUrl], @ViewBuilder content: @escaping (_ dismiss: @escaping (() -> Void)) -> Content) {
        self.evid = evid
        self._model = ObservedObject(initialValue: CarouselModel(damus_state: state, urls: urls))
        self.settings = state.settings
        self.content = content
    }
    
    /// Determines if the image should fill its container.
    /// Always returns true to ensure images consistently fill the width of the container.
    /// This simplifies the layout behavior and prevents inconsistent sizing between carousel items.
    var filling: Bool { true }
    
    var height: CGFloat {
        // Use the first image height (to prevent height from jumping when swiping), then default to the default fill height
        // This prioritization ensures consistent carousel height regardless of which image is currently displayed
        model.first_image_fill?.height ?? model.default_fill_height
    }
    
    func Placeholder(url: URL, geo_size: CGSize, num_urls: Int) -> some View {
        Group {
            if num_urls > 1 {
                // jb55: quick hack since carousel with multiple images looks horrible with blurhash background
                Color.clear
            } else if let meta = model.damus_state.events.lookup_img_metadata(url: url),
               case .processed(let blurhash) = meta.state {
                Image(uiImage: blurhash)
                    .resizable()
                    .frame(width: geo_size.width * UIScreen.main.scale, height: self.height * UIScreen.main.scale)
            } else {
                Color.clear
            }
        }
    }
    
    func Media(geo: GeometryProxy, url: MediaUrl, index: Int) -> some View {
        Group {
            if settings.low_data_mode || networkMonitor.isLowDataMode {
                 LowDataModePlaceholder(url: url, onTap: {
                     // Future: Allow manual load
                 })
                 .frame(width: geo.size.width, height: height)
            } else {
                switch url {
                case .image(let url):
                    Img(geo: geo, url: url, index: index)
                        .onTapGesture {
                            present(full_screen_item: .full_screen_carousel(urls: model.urls, selectedIndex: $model.selectedIndex))
                        }
                case .video(let url):
                       let video_model = model.damus_state.video.get_player(for: url)
                        DamusVideoPlayerView(
                            model: video_model,
                            coordinator: model.damus_state.video,
                            style: .preview(on_tap: {
                                present(full_screen_item: .full_screen_carousel(urls: model.urls, selectedIndex: $model.selectedIndex))
                            })
                        )
                }
            }
        }
    }
    
    func Img(geo: GeometryProxy, url: URL, index: Int) -> some View {
        KFAnimatedImage(url)
            .callbackQueue(.dispatch(.global(qos:.background)))
            .backgroundDecode(true)
            .imageContext(.note, disable_animation: model.damus_state.settings.disable_animation)
            .image_fade(duration: 0.25)
            .cancelOnDisappear(true)
            .configure { view in
                view.framePreloadCount = 3
            }
            .observe_image_size(size_changed: { size in
                // Observe the image size to update the model when the size changes, so we can calculate the fill
                model.media_size_information[url] = size
            })
            .background {
                Placeholder(url: url, geo_size: geo.size, num_urls: model.urls.count)
            }
            .aspectRatio(contentMode: filling ? .fill : .fit)
            .kfClickable()
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .tabItem {
                Text(url.absoluteString)
            }
            .id(url.absoluteString)
            .padding(0)
                
    }
    
    var Medias: some View {
        TabView(selection: $model.selectedIndex) {
            ForEach(model.urls.indices, id: \.self) { index in
                GeometryReader { geo in
                    Media(geo: geo, url: model.urls[index], index: index)
                        .onChange(of: geo.size, perform: { new_size in
                            model.geo_size = new_size
                        })
                        .onAppear {
                            model.geo_size = geo.size
                        }
                }
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .frame(height: height)
        .clipped() // Prevents content from overflowing the frame, ensuring clean edges in the carousel
        .onChange(of: model.selectedIndex) { value in
            model.selectedIndex = value
        }
    }
    
    var body: some View {
        VStack {
            if #available(iOS 18.0, *) {
                Medias
            } else {
                // An empty tap gesture recognizer is needed on iOS 17 and below to suppress other overlapping tap recognizers
                // Otherwise it will both open the carousel and go to a note at the same time
                Medias.onTapGesture { }
            }
            
            
            if model.urls.count > 1 {
                PageControlView(currentPage: $model.selectedIndex, numberOfPages: model.urls.count)
                    .frame(maxWidth: 0, maxHeight: 0)
                    .padding(.top, 5)
            }
        }
    }
}


public struct ImageFill {
    let filling: Bool?
    let height: CGFloat
        
    static func calculate_image_fill(geo_size: CGSize, img_size: CGSize, maxHeight: CGFloat, fillHeight: CGFloat) -> ImageFill {
        let shape = ImageShape.determine_image_shape(img_size)

        let xfactor = geo_size.width / img_size.width
        let scaled = img_size.height * xfactor
        
        //print("calc_img_fill \(img_size.width)x\(img_size.height) xfactor:\(xfactor) scaled:\(scaled)")
        
        // calculate scaled image height
        // set scale factor and constrain images to minimum 150
        // and animations to scaled factor for dynamic size adjustment
        switch shape {
        case .portrait, .landscape:
            let filling = scaled > maxHeight
            let height = filling ? fillHeight : scaled
            return ImageFill(filling: filling, height: height)
        case .square, .unknown:
            return ImageFill(filling: nil, height: scaled)
        }
    }
}

// MARK: - Preview Provider
struct ImageCarousel_Previews: PreviewProvider {
    static var previews: some View {
        let url: MediaUrl = .image(URL(string: "https://jb55.com/red-me.jpg")!)
        let test_video_url: MediaUrl = .video(URL(string: "http://cdn.jb55.com/s/zaps-build.mp4")!)
        ImageCarousel<AnyView>(state: test_damus_state, evid: test_note.id, urls: [test_video_url, url])
            .environmentObject(OrientationTracker())
    }
}
