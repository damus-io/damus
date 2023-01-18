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

struct ImageView: View {
    let urls: [URL]
    
    @Environment(\.presentationMode) var presentationMode
    //let pubkey: String
    //let profiles: Profiles

    @GestureState private var scaleState: CGFloat = 1
    @GestureState private var offsetState = CGSize.zero

    @State private var offset = CGSize.zero
    @State private var scale: CGFloat = 1

    func resetStatus(){
        self.offset = CGSize.zero
        self.scale = 1
    }

    var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($scaleState) { currentState, gestureState, _ in
                gestureState = currentState
            }
            .onEnded { value in
                scale *= value
            }
    }

    var dragGesture: some Gesture {
        DragGesture()
            .updating($offsetState) { currentState, gestureState, _ in
                gestureState = currentState.translation
            }.onEnded { value in
                offset.height += value.translation.height
                offset.width += value.translation.width
            }
    }

    var doubleTapGesture : some Gesture {
        TapGesture(count: 2).onEnded { value in
            resetStatus()
        }
    }
    
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
        ZStack(alignment: .topLeading) {
            Color("DamusDarkGrey") // Or Color("DamusBlack")
                .edgesIgnoringSafeArea(.all)
            
            HStack() {
                Button {
                    presentationMode.wrappedValue.dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .foregroundColor(.white)
                        .font(.largeTitle)
                        .frame(width: 40, height: 40)
                        .padding(20)
                }
            }
            .zIndex(1)
            
            VStack(alignment: .center) {
                //Spacer()
                    //.frame(height: 120)
                
                TabView {
                    ForEach(urls, id: \.absoluteString) { url in
                        VStack{
                            //Color("DamusDarkGrey")
                            Text(url.lastPathComponent)
                                .foregroundColor(Color("DamusWhite"))
                            
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
                                //.padding(100)
                                .scaledToFit()
                                .scaleEffect(self.scale * scaleState)
                                .offset(x: offset.width + offsetState.width, y: offset.height + offsetState.height)
                                .gesture(SimultaneousGesture(zoomGesture, dragGesture))
                                .gesture(doubleTapGesture)
                                .modifier(SwipeToDismissModifier(onDismiss: {
                                    presentationMode.wrappedValue.dismiss()
                                }))
                            
                        }.padding(.bottom, 50) // Ensure carousel appears beneath
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
