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



struct ImageCarousel: View {
    var urls: [URL]
    
    @State var open_sheet: Bool = false

    var body: some View {
        TabView {
            ForEach(urls, id: \.absoluteString) { url in
                if FailedImageURLsCache.shared.urls.contains(url) {
                    ZStack {
                        Rectangle()
                            .foregroundColor(Color("DamusDarkGrey"))
                            .cornerRadius(10)
                        ProgressView()
                    }
                } else {
                    Rectangle()
                        .foregroundColor(Color.clear)
                        .overlay {
                            KFAnimatedImage(url)
                                .imageContext(.note)
                                .cancelOnDisappear(true)
                                .configure { view in
                                    view.framePreloadCount = 3
                                }
                                .onFailure { error in
                                    FailedImageURLsCache.shared.add(url)
                                }
                                .aspectRatio(contentMode: .fill)
                                //.cornerRadius(10)
                                .tabItem {
                                    Text(url.absoluteString)
                                }
                                .id(url.absoluteString)
//                            .contextMenu {
//                                Button(NSLocalizedString("Copy Image", comment: "Context menu option to copy an image to clipboard.")) {
//                                    UIPasteboard.general.string = url.absoluteString
//                                }
//                            }
                        }
                }
            }
        }
        .fullScreenCover(isPresented: $open_sheet) {
            ImageView(urls: urls)
        }
        .frame(height: 350)
        .onTapGesture {
            open_sheet = true
        }
        .tabViewStyle(PageTabViewStyle())
    }
}

struct ImageCarousel_Previews: PreviewProvider {
    static var previews: some View {
        ImageCarousel(urls: [URL(string: "https://jb55.com/red-me.jpg")!,URL(string: "https://jb55.com/red-me.jpg")!])
    }
}
