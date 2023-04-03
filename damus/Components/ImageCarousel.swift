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
    
    
    @State private var open_sheet: Bool = false
    @State private var current_url: URL? = nil
    @State private var height: CGFloat = .zero
    @State private var minHeight: CGFloat = 150
    @State private var maxHeight: CGFloat = 500
    @State private var filling: Bool = false
    
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
                                    let fill = calculate_image_fill(geo: geo, img: img, maxHeight: maxHeight, minHeight: minHeight)

                                    DispatchQueue.main.async {
                                        if let filling = fill.filling {
                                            self.filling = filling
                                        }

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
        .frame(height: height)
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

func calculate_image_fill(geo: GeometryProxy, img: UIImage, maxHeight: CGFloat, minHeight: CGFloat) -> ImageFill {
    let shape = determine_image_shape(img.size)

    let xfactor = geo.size.width / img.size.width
    let yfactor = maxHeight / img.size.height
    // calculate scaled image height
    // set scale factor and constrain images to minimum 150
    // and animations to scaled factor for dynamic size adjustment
    switch shape {
    case .portrait:
        let filling = yfactor <= 1.0
        let scaled = img.size.height * xfactor
        let height = filling ? maxHeight : max(scaled, minHeight)
        return ImageFill(filling: filling, height: height)
    case .square:
        let filling = yfactor <= 1.0 && xfactor <= 1.0
        let scaled = img.size.height * xfactor
        let height = filling ? maxHeight : max(scaled, minHeight)
        return ImageFill(filling: filling, height: height)
    case .landscape:
        let scaled = img.size.height * xfactor
        let filling = scaled > maxHeight || xfactor < 1.0
        let height = img.kf.imageFrameCount != nil ? scaled : filling ? min(maxHeight, scaled) : max(scaled, minHeight)
        return ImageFill(filling: filling, height: height)
    case .unknown:
        let height = max(img.size.height, minHeight)
        return ImageFill(filling: nil, height: height)
    }
}

struct ImageCarousel_Previews: PreviewProvider {
    static var previews: some View {
        ImageCarousel(urls: [URL(string: "https://jb55.com/red-me.jpg")!,URL(string: "https://jb55.com/red-me.jpg")!])
    }
}
