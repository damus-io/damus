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

// MARK: - Image Carousel
struct ImageCarousel: View {
    var urls: [URL]
    let evid: String
    
    let state: DamusState
    
    @State private var open_sheet: Bool = false
    @State private var current_url: URL? = nil
    @State private var image_fill: ImageFill? = nil

    @State private var fillHeight: CGFloat = 350
    @State private var maxHeight: CGFloat = UIScreen.main.bounds.height * 0.85 // 1.2
    @State private var firstImageHeight: CGFloat = UIScreen.main.bounds.height * 0.85
    @State private var currentImageHeight: CGFloat?
    @State private var selectedIndex = 0
    
    init(state: DamusState, evid: String, urls: [URL]) {
        _open_sheet = State(initialValue: false)
        _current_url = State(initialValue: nil)
        _image_fill = State(initialValue: state.previews.lookup_image_meta(evid))
        self.urls = urls
        self.evid = evid
        self.state = state
    }
    
    var filling: Bool {
        image_fill?.filling == true
    }
    
    var height: CGFloat {
        image_fill?.height ?? fillHeight
    }
    
    func Placeholder(url: URL, geo_size: CGSize) -> some View {
        Group {
            if let meta = state.events.lookup_img_metadata(url: url),
               case .processed(let blurhash) = meta.state {
                Image(uiImage: blurhash)
                    .resizable()
                    .frame(width: geo_size.width * UIScreen.main.scale, height: self.height * UIScreen.main.scale)
            } else {
                EmptyView()
            }
        }
        .onAppear {
            if self.image_fill == nil,
               let meta = state.events.lookup_img_metadata(url: url),
               let size = meta.meta.dim?.size
            {
                let fill = ImageFill.calculate_image_fill(geo_size: geo_size, img_size: size, maxHeight: maxHeight, fillHeight: fillHeight)
                self.image_fill = fill
            }
        }
    }

    var body: some View {
        VStack {
            TabView(selection: $selectedIndex) {
                ForEach(urls.indices, id: \.self) { index in
                    ZStack {
                        Rectangle()
                            .foregroundColor(Color.clear)
                            .overlay {
                                GeometryReader { geo in
                                    KFAnimatedImage(urls[index])
                                        .callbackQueue(.dispatch(.global(qos:.background)))
                                        .backgroundDecode(true)
                                        .imageContext(.note, disable_animation: state.settings.disable_animation)
                                        .cancelOnDisappear(true)
                                        .configure { view in
                                            view.framePreloadCount = 3
                                        }
                                        .imageFill(for: geo.size, max: maxHeight, fill: fillHeight) { fill in
                                            state.previews.cache_image_meta(evid: evid, image_fill: fill)
                                            // blur hash can be discarded when we have the url
                                            // NOTE: this is the wrong place for this... we need to remove
                                            //       it when the image is loaded in memory. This may happen
                                            //       earlier than this (by the preloader, etc)
                                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                                state.events.lookup_img_metadata(url: urls[index])?.state = .not_needed
                                            }
                                            image_fill = fill
                                            if index == 0 {
                                                firstImageHeight = fill.height
                                                //maxHeight = firstImageHeight ?? maxHeight
                                            } else {
                                                //maxHeight = firstImageHeight ?? fill.height
                                            }
                                        }
                                        .aspectRatio(contentMode: .fill)
                                        //.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                                        .position(x: geo.size.width / 2, y: geo.size.height / 2)
                                        .tabItem {
                                            Text(urls[index].absoluteString)
                                        }
                                        .id(urls[index].absoluteString)
                                        .padding(0)
                                }
                            }
                            .tag(index)
                            .background(Color("DamusDarkGrey"))
                        
                        if (state.settings.show_carousel_counter) {
                            CarouselImageCounter(urls: urls, selectedIndex: $selectedIndex)
                        }
                    }
                }
            }
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .fullScreenCover(isPresented: $open_sheet) {
                ImageView(urls: urls, disable_animation: state.settings.disable_animation)
            }
            .frame(height: firstImageHeight)
            .onTapGesture {
                open_sheet = true
            }
            .onChange(of: selectedIndex) { value in
                            selectedIndex = value
                        }
            .tabViewStyle(PageTabViewStyle())
            
            // This is our custom carousel image indicator
            CarouselDotsView(urls: urls, selectedIndex: $selectedIndex)
        }
    }
}

// MARK: - Custom Carousel
struct CarouselDotsView: View {
    let urls: [URL]
    @Binding var selectedIndex: Int

    var body: some View {
        if urls.count > 1 {
            HStack {
                ForEach(urls.indices, id: \.self) { index in
                    Circle()
                        .fill(index == selectedIndex ? Color("DamusPurple") : Color("DamusLightGrey"))
                        .frame(width: 10, height: 10)
                        .onTapGesture {
                            selectedIndex = index
                        }
                }
            }
            .padding(.top, CGFloat(8))
            .id(UUID())
        }
    }
}

// MARK: - Carousel Image Counter
struct CarouselImageCounter: View {
    let urls: [URL]
    @Binding var selectedIndex: Int
    
    var body: some View {
        if urls.count > 1 {
            VStack {
                HStack {
                    Text("\(selectedIndex + 1)/\(urls.count)")
                        .foregroundColor(.white)
                        .padding(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                        .background(
                            RoundedRectangle(cornerRadius: 40)
                                .foregroundColor(Color("DamusDarkGrey"))
                                .opacity(0.40)
                        )
                        .padding(EdgeInsets(top: 12, leading: 12, bottom: 12, trailing: 12))
                    
                    Spacer()
                }
                Spacer()
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
        ImageCarousel(state: test_damus_state(), evid: "evid", urls: [URL(string: "https://jb55.com/red-me.jpg")!,URL(string: "https://jb55.com/red-me.jpg")!])
    }
}

