//
//  ImageCarousel.swift
//  damus
//
//  Created by William Casarin on 2022-10-16.
//

import SwiftUI
import Kingfisher

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

class CarouselModel: ObservableObject {
    var current_url: URL?
    var fillHeight: CGFloat
    var maxHeight: CGFloat
    var firstImageHeight: CGFloat?

    @Published var open_sheet: Bool
    @Published var selectedIndex: Int
    @Published var video_size: CGSize?
    @Published var image_fill: ImageFill?

    init(image_fill: ImageFill?) {
        self.current_url = nil
        self.fillHeight = 350
        self.maxHeight = UIScreen.main.bounds.height * 1.2 // 1.2
        self.firstImageHeight = nil
        self.open_sheet = false
        self.selectedIndex = 0
        self.video_size = nil
        self.image_fill = image_fill
    }
}

// MARK: - Image Carousel
@MainActor
struct ImageCarousel<Content: View>: View {
    var urls: [MediaUrl]
    
    let evid: NoteId
    
    let state: DamusState
    @ObservedObject var model: CarouselModel
    let content: ((_ dismiss: @escaping (() -> Void)) -> Content)?

    init(state: DamusState, evid: NoteId, urls: [MediaUrl]) {
        self.urls = urls
        self.evid = evid
        self.state = state
        let media_model = state.events.get_cache_data(evid).media_metadata_model
        self._model = ObservedObject(initialValue: CarouselModel(image_fill: media_model.fill))
        self.content = nil
    }
    
    init(state: DamusState, evid: NoteId, urls: [MediaUrl], @ViewBuilder content: @escaping (_ dismiss: @escaping (() -> Void)) -> Content) {
        self.urls = urls
        self.evid = evid
        self.state = state
        let media_model = state.events.get_cache_data(evid).media_metadata_model
        self._model = ObservedObject(initialValue: CarouselModel(image_fill: media_model.fill))
        self.content = content
    }
    
    var filling: Bool {
        model.image_fill?.filling == true
    }
    
    var height: CGFloat {
        model.firstImageHeight ?? model.image_fill?.height ?? model.fillHeight
    }
    
    func Placeholder(url: URL, geo_size: CGSize, num_urls: Int) -> some View {
        Group {
            if num_urls > 1 {
                // jb55: quick hack since carousel with multiple images looks horrible with blurhash background
                Color.clear
            } else if let meta = state.events.lookup_img_metadata(url: url),
               case .processed(let blurhash) = meta.state {
                Image(uiImage: blurhash)
                    .resizable()
                    .frame(width: geo_size.width * UIScreen.main.scale, height: self.height * UIScreen.main.scale)
            } else {
                Color.clear
            }
        }
        .onAppear {
            if self.model.image_fill == nil, let size = state.video.size_for_url(url) {
                let fill = ImageFill.calculate_image_fill(geo_size: geo_size, img_size: size, maxHeight: model.maxHeight, fillHeight: model.fillHeight)
                self.model.image_fill = fill
            }
        }
    }
    
    func Media(geo: GeometryProxy, url: MediaUrl, index: Int) -> some View {
        Group {
            switch url {
            case .image(let url):
                Img(geo: geo, url: url, index: index)
                    .onTapGesture {
                        model.open_sheet = true
                    }
            case .video(let url):
                DamusVideoPlayer(url: url, video_size: $model.video_size, controller: state.video, style: .preview(on_tap: { model.open_sheet = true }))
                    .onChange(of: model.video_size) { size in
                        guard let size else { return }
                        
                        let fill = ImageFill.calculate_image_fill(geo_size: geo.size, img_size: size, maxHeight: model.maxHeight, fillHeight: model.fillHeight)

                        print("video_size changed \(size)")
                        if self.model.image_fill == nil {
                            print("video_size firstImageHeight \(fill.height)")
                            self.model.firstImageHeight = fill.height
                            state.events.get_cache_data(evid).media_metadata_model.fill = fill
                        }
                        
                        self.model.image_fill = fill
                    }
            }
        }
    }
    
    func Img(geo: GeometryProxy, url: URL, index: Int) -> some View {
        KFAnimatedImage(url)
            .callbackQueue(.dispatch(.global(qos:.background)))
            .backgroundDecode(true)
            .imageContext(.note, disable_animation: state.settings.disable_animation)
            .image_fade(duration: 0.25)
            .cancelOnDisappear(true)
            .configure { view in
                view.framePreloadCount = 3
            }
            .imageFill(for: geo.size, max: model.maxHeight, fill: model.fillHeight) { fill in
                state.events.get_cache_data(evid).media_metadata_model.fill = fill
                // blur hash can be discarded when we have the url
                // NOTE: this is the wrong place for this... we need to remove
                //       it when the image is loaded in memory. This may happen
                //       earlier than this (by the preloader, etc)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    state.events.lookup_img_metadata(url: url)?.state = .not_needed
                }
                self.model.image_fill = fill
                if index == 0 {
                    self.model.firstImageHeight = fill.height
                    //maxHeight = firstImageHeight ?? maxHeight
                } else {
                    //maxHeight = firstImageHeight ?? fill.height
                }
            }
            .background {
                Placeholder(url: url, geo_size: geo.size, num_urls: urls.count)
            }
            .aspectRatio(contentMode: filling ? .fill : .fit)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
            .tabItem {
                Text(url.absoluteString)
            }
            .id(url.absoluteString)
            .padding(0)
                
    }
    
    var Medias: some View {
        TabView(selection: $model.selectedIndex) {
            ForEach(urls.indices, id: \.self) { index in
                GeometryReader { geo in
                    Media(geo: geo, url: urls[index], index: index)
                }
            }
        }
        .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
        .fullScreenCover(isPresented: $model.open_sheet) {
            if let content {
                FullScreenCarouselView<Content>(video_controller: state.video, urls: urls, settings: state.settings, selectedIndex: $model.selectedIndex) {
                    content({ // Dismiss closure
                        model.open_sheet = false
                    })
                }
            }
            else {
                FullScreenCarouselView<AnyView>(video_controller: state.video, urls: urls, settings: state.settings, selectedIndex: $model.selectedIndex)
            }
        }
        .frame(height: height)
        .onChange(of: model.selectedIndex) { value in
            model.selectedIndex = value
        }
    }
    
    var body: some View {
        VStack {
            Medias
                .onTapGesture { }
            
            if urls.count > 1 {
                PageControlView(currentPage: $model.selectedIndex, numberOfPages: urls.count)
                    .frame(maxWidth: 0, maxHeight: 0)
                    .padding(.top, 5)
            }
        }
    }
}

// MARK: - Image Modifier
extension KFOptionSetter {
    /// Sets a block to get image size
    ///
    /// - Parameter block: The block which is used to read the image object.
    /// - Returns: `Self` value after read size
    public func imageFill(for size: CGSize, max: CGFloat, fill: CGFloat, block: @escaping (ImageFill) throws -> Void) -> Self {
        let modifier = AnyImageModifier { image -> KFCrossPlatformImage in
            let img_size = image.size
            let geo_size = size
            let fill = ImageFill.calculate_image_fill(geo_size: geo_size, img_size: img_size, maxHeight: max, fillHeight: fill)
            DispatchQueue.main.async { [block, fill] in
                try? block(fill)
            }
            return image
        }
        options.imageModifier = modifier
        return self
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

