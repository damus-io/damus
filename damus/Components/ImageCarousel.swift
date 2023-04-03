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
}


struct ImageCarousel: View {
    var urls: [URL]
    
    let evid: String
    let previews: PreviewCache
    let minHeight: CGFloat = 150
    let maxHeight: CGFloat = 500
    
    @State private var open_sheet: Bool = false
    @State private var current_url: URL? = nil
    @State private var height: CGFloat? = nil
    @State private var filling: Bool = false
    
    init(previews: PreviewCache, evid: String, urls: [URL]) {
        _open_sheet = State(initialValue: false)
        _current_url = State(initialValue: nil)
        _height = State(initialValue: previews.lookup_image_height(evid))
        _filling = State(initialValue: false)
        self.urls = urls
        self.evid = evid
        self.previews = previews
    }
    
    var body: some View {
        TabView {
            ForEach(urls, id: \.absoluteString) { url in
                Rectangle()
                    .foregroundColor(Color.clear)
                    .overlay {
                        GeometryReader { geo in
                            KFAnimatedImage(url)
                                .imageContext(.note)
                                .cancelOnDisappear(true)
                                .configure { view in
                                    view.framePreloadCount = 3
                                }
                                .imageModifier({ img in
                                    guard self.height == nil else {
                                        return
                                    }
                                    let img_size = img.size
                                    let is_animated = img.kf.imageFrameCount != nil
                                    
                                    DispatchQueue.main.async {
                                        let fill = calculate_image_fill(geo: geo, img_size: img_size, is_animated: is_animated, maxHeight: maxHeight, minHeight: minHeight)
                                        
                                        if let filling = fill.filling {
                                            self.filling = filling
                                        }

                                        self.previews.cache_image_height(evid: evid, height: fill.height)
                                        self.height = fill.height
                                    }
                                })
                                .aspectRatio(contentMode: filling ? .fill : .fit)
                                .tabItem {
                                    Text(url.absoluteString)
                                }
                                .id(url.absoluteString)
                        }
                    }
            }
        }
        .fullScreenCover(isPresented: $open_sheet) {
            ImageView(urls: urls)
        }
        .frame(height: height ?? 0)
        .onTapGesture {
            open_sheet = true
        }
        .tabViewStyle(PageTabViewStyle())
    }
}

func determine_image_shape(_ size: CGSize) -> ImageShape {
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

struct ImageFill {
    let filling: Bool?
    let height: CGFloat
}

func calculate_image_fill(geo: GeometryProxy, img_size: CGSize, is_animated: Bool, maxHeight: CGFloat, minHeight: CGFloat) -> ImageFill {
    let shape = determine_image_shape(img_size)

    let xfactor = geo.size.width / img_size.width
    let yfactor = maxHeight / img_size.height
    // calculate scaled image height
    // set scale factor and constrain images to minimum 150
    // and animations to scaled factor for dynamic size adjustment
    switch shape {
    case .portrait:
        let filling = yfactor <= 1.0
        let scaled = img_size.height * xfactor
        let height = filling ? maxHeight : max(scaled, minHeight)
        return ImageFill(filling: filling, height: height)
    case .square:
        let filling = yfactor <= 1.0 && xfactor <= 1.0
        let scaled = img_size.height * xfactor
        let height = filling ? maxHeight : max(scaled, minHeight)
        return ImageFill(filling: filling, height: height)
    case .landscape:
        let scaled = img_size.height * xfactor
        let filling = scaled > maxHeight || xfactor < 1.0
        let height = is_animated ? scaled : filling ? min(maxHeight, scaled) : max(scaled, minHeight)
        return ImageFill(filling: filling, height: height)
    case .unknown:
        let height = max(img_size.height, minHeight)
        return ImageFill(filling: nil, height: height)
    }
}

struct ImageCarousel_Previews: PreviewProvider {
    static var previews: some View {
        ImageCarousel(previews: test_damus_state().previews, evid: "evid", urls: [URL(string: "https://jb55.com/red-me.jpg")!,URL(string: "https://jb55.com/red-me.jpg")!])
    }
}

