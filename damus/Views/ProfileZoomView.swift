//
//  ProfileZoomView.swift
//  damus
//
//  Created by scoder1747 on 12/27/22.
//
import SwiftUI
import Kingfisher

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
            .clipShape(Circle())
            .modifier(ImageContextMenuModifier(url: imageModel.url, image: image, showShareSheet: $showShareSheet))
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: [imageModel.url])
            }
    }
}

struct ProfileZoomView: View {
    
    let pubkey: String
    let profiles: Profiles
    
    @Environment(\.presentationMode) var presentationMode
    
    var navBarView: some View {
        HStack {
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }, label: {
                Image(systemName: "xmark")
                    .frame(width: 33, height: 33)
                    .background(.regularMaterial)
                    .clipShape(Circle())
            })
            
            Spacer()
        }
        .padding()
    }

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            ZoomableScrollView {
                ImageContainerView(url: get_profile_url(picture: nil, pubkey: pubkey, profiles: profiles))
                    .aspectRatio(contentMode: .fit)
                    .padding(.top, Theme.safeAreaInsets?.top)
                    .padding(.bottom, Theme.safeAreaInsets?.bottom)
                    .padding(.horizontal)
            }
            .ignoresSafeArea()
            .modifier(SwipeToDismissModifier(minDistance: 50, onDismiss: {
                presentationMode.wrappedValue.dismiss()
            }))
        }
        .overlay(navBarView, alignment: .top)
    }
}

struct ProfileZoomView_Previews: PreviewProvider {
    static let pubkey = "ca48854ac6555fed8e439ebb4fa2d928410e0eef13fa41164ec45aaaa132d846"
    
    static var previews: some View {
        ProfileZoomView(
            pubkey: pubkey,
            profiles: make_preview_profiles(pubkey))
    }
}
