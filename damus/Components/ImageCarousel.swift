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

struct ImageContextMenuModifier: ViewModifier {
    let url: URL?
    let image: UIImage?
    @Binding var showShareSheet: Bool
    
    func body(content: Content) -> some View {
        return content.contextMenu {
            Button {
                UIPasteboard.general.url = url
            } label: {
                Label(NSLocalizedString("Copy Image URL", comment: "Context menu option to copy the URL of an image into clipboard."), systemImage: "doc.on.doc")
            }
            if let someImage = image {
                Button {
                    UIPasteboard.general.image = someImage
                } label: {
                    Label(NSLocalizedString("Copy Image", comment: "Context menu option to copy an image into clipboard."), systemImage: "photo.on.rectangle")
                }
                Button {
                    UIImageWriteToSavedPhotosAlbum(someImage, nil, nil, nil)
                } label: {
                    Label(NSLocalizedString("Save Image", comment: "Context menu option to save an image."), systemImage: "square.and.arrow.down")
                }
            }
            Button {
                showShareSheet = true
            } label: {
                Label(NSLocalizedString("Share", comment: "Button to share an image."), systemImage: "square.and.arrow.up")
            }
        }
    }
}

private struct ImageContainerView: View {
    
    @ObservedObject var imageModel: KFImageModel
    
    @State private var image: UIImage?
    @State private var showShareSheet = false
    
    init(url: URL?) {
        self.imageModel = KFImageModel(
            url: url,
            fallbackUrl: nil,
            maxByteSize: 2000000, // 2 MB
            downsampleSize: CGSize(width: 400, height: 400)
        )
    }
    
    private struct ImageHandler: ImageModifier {
        @Binding var handler: UIImage?
        
        func modify(_ image: UIImage) -> UIImage {
            handler = image
            return image
        }
    }
    
    var body: some View {
        
        KFAnimatedImage(imageModel.url)
            .callbackQueue(.dispatch(.global(qos: .background)))
            .processingQueue(.dispatch(.global(qos: .background)))
            .cacheOriginalImage()
            .configure { view in
                view.framePreloadCount = 1
            }
            .scaleFactor(UIScreen.main.scale)
            .loadDiskFileSynchronously()
            .fade(duration: 0.1)
            .imageModifier(ImageHandler(handler: $image))
            .onFailure { _ in
                imageModel.downloadFailed()
            }
            .id(imageModel.refreshID)
            .clipped()
            .modifier(ImageContextMenuModifier(url: imageModel.url, image: image, showShareSheet: $showShareSheet))
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: [imageModel.url])
            }
        
        // TODO: Update ImageCarousel with serializer and processor
        // .serialize(by: imageModel.serializer)
        // .setProcessor(imageModel.processor)
    }
}

struct ImageView: View {
    
    let urls: [URL?]
    
    @Environment(\.presentationMode) var presentationMode
    
    @State private var selectedIndex = 0
    @State var showMenu = true
    
    var navBarView: some View {
        VStack {
            HStack {
                Text(urls[selectedIndex]?.lastPathComponent ?? "")
                    .bold()
                
                Spacer()
                
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }, label: {
                    Image(systemName: "xmark")
                })
            }
            .padding()
            
            Divider()
                .ignoresSafeArea()
        }
        .background(.regularMaterial)
    }
    
    var tabViewIndicator: some View {
        HStack(spacing: 10) {
            ForEach(urls.indices, id: \.self) { index in
                Capsule()
                    .fill(index == selectedIndex ? Color(UIColor.label) : Color.secondary)
                    .frame(width: 7, height: 7)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(Capsule())
    }
    
    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            TabView(selection: $selectedIndex) {
                ForEach(urls.indices, id: \.self) { index in
                    ZoomableScrollView {
                        ImageContainerView(url: urls[index])
                            .aspectRatio(contentMode: .fit)
                            .padding(.top, Theme.safeAreaInsets?.top)
                            .padding(.bottom, Theme.safeAreaInsets?.bottom)
                    }
                    .modifier(SwipeToDismissModifier(minDistance: 50, onDismiss: {
                        presentationMode.wrappedValue.dismiss()
                    }))
                    .ignoresSafeArea()
                    .tag(index)
                }
            }
            .ignoresSafeArea()
            .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
            .gesture(TapGesture(count: 2).onEnded {
                // Prevents menu from hiding on double tap
            })
            .gesture(TapGesture(count: 1).onEnded {
                showMenu.toggle()
            })
            .overlay(
                VStack {
                    if showMenu {
                        navBarView
                        Spacer()
                        
                        if (urls.count > 1) {
                            tabViewIndicator
                        }
                    }
                }
                .animation(.easeInOut, value: showMenu)
                .padding(.bottom, Theme.safeAreaInsets?.bottom)
            )
        }
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
                            .callbackQueue(.dispatch(.global(qos: .background)))
                            .processingQueue(.dispatch(.global(qos: .background)))
                            .cancelOnDisappear(true)
                            .backgroundDecode()
                            .cacheOriginalImage()
                            .scaleFactor(UIScreen.main.scale)
                            .configure { view in
                                view.framePreloadCount = 3
                            }
                            .aspectRatio(contentMode: .fit)
                            .tabItem {
                                Text(url.absoluteString)
                            }
                            .id(url.absoluteString)
                            .contextMenu {
                                Button(NSLocalizedString("Copy Image", comment: "Context menu option to copy an image to clipboard.")) {
                                    UIPasteboard.general.string = url.absoluteString
                                }
                            }
                    }
            }
        }
        .cornerRadius(10)
        .fullScreenCover(isPresented: $open_sheet) {
            ImageView(urls: urls)
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
        ImageCarousel(urls: [URL(string: "https://jb55.com/red-me.jpg")!,URL(string: "https://jb55.com/red-me.jpg")!])
    }
}
