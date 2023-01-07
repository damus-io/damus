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
    
    let activityItems: [URL]
    let callback: Callback? = nil
    let applicationActivities: [UIActivity]? = nil
    let excludedActivityTypes: [UIActivity.ActivityType]? = nil
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities)
        controller.excludedActivityTypes = excludedActivityTypes
        controller.completionWithItemsHandler = callback
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // nothing to do here
    }
}

struct ImageContextMenuModifier: ViewModifier {
    let url: URL
    let image: UIImage?
    @Binding var showShareSheet: Bool
    
    func body(content: Content) -> some View {
        return content.contextMenu {
            Button {
                UIPasteboard.general.url = url
            } label: {
                Label("Copy Image URL", systemImage: "doc.on.doc")
            }
            if let someImage = image {
                Button {
                    UIPasteboard.general.image = someImage
                } label: {
                    Label("Copy Image", systemImage: "photo.on.rectangle")
                }
                Button {
                    UIImageWriteToSavedPhotosAlbum(someImage, nil, nil, nil)
                } label: {
                    Label("Save Image", systemImage: "square.and.arrow.down")
                }
            }
            Button {
                showShareSheet = true
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
        }
    }
}

struct ImageViewer: View {
    let urls: [URL]
    
    private struct ImageHandler: ImageModifier {
        @Binding var handler: UIImage?
        
        func modify(_ image: UIImage) -> UIImage {
            handler = image
            return image
        }
    }

    @State private var image: UIImage?
    @State private var showShareSheet = false
    
    func onShared(completed: Bool) -> Void {
        if (completed) {
            showShareSheet = false
        }
    }
    
    var body: some View {
        TabView {
            ForEach(urls, id: \.absoluteString) { url in
                VStack{
                    Text(url.lastPathComponent)
                    
                    KFAnimatedImage(url)
                        .configure { view in
                            view.framePreloadCount = 3
                        }
                        .cacheOriginalImage()
                        .imageModifier(ImageHandler(handler: $image))
                        .loadDiskFileSynchronously()
                        .scaleFactor(UIScreen.main.scale)
                        .fade(duration: 0.1)
                        .aspectRatio(contentMode: .fit)
                        .tabItem {
                            Text(url.absoluteString)
                        }
                        .id(url.absoluteString)
                        .modifier(ImageContextMenuModifier(url: url, image: image, showShareSheet: $showShareSheet))
                        .sheet(isPresented: $showShareSheet) {
                            ShareSheet(activityItems: [url])
                        }

                }
            }
        }
        .tabViewStyle(PageTabViewStyle())
    }
}

struct ImageCarousel: View {
    var urls: [URL]
    
    @State var open_sheet: Bool = false
    @State var current_url: URL? = nil
    
    var body: some View {
        TabView {
            ForEach(urls, id: \.absoluteString) { url in
                Rectangle()
                    .foregroundColor(Color.clear)
                    .overlay {
                        KFAnimatedImage(url)
                            .configure { view in
                                view.framePreloadCount = 3
                            }
                            .cacheOriginalImage()
                            .loadDiskFileSynchronously()
                            .scaleFactor(UIScreen.main.scale)
                            .fade(duration: 0.1)
                            .aspectRatio(contentMode: .fit)
                            .tabItem {
                                Text(url.absoluteString)
                            }
                            .id(url.absoluteString)
                            .contextMenu {
                                Button("Copy Image") {
                                    UIPasteboard.general.string = url.absoluteString
                                }
                            }
                    }
            }
        }
        .cornerRadius(10)
        .sheet(isPresented: $open_sheet) {
            ImageViewer(urls: urls)
        }
        .frame(height: 200)
        .onTapGesture {
            open_sheet = true
        }
        .tabViewStyle(PageTabViewStyle())
    }
}

struct ImageCarousel_Previews: PreviewProvider {
    static var previews: some View {
        ImageCarousel(urls: [URL(string: "https://jb55.com/red-me.jpg")!])
    }
}
