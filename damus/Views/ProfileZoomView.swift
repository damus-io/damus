//
//  ProfileZoomView.swift
//  damus
//
//  Created by scoder1747 on 12/27/22.
//
import SwiftUI
import SDWebImageSwiftUI

private struct ImageContainerView: View {
    
    let url: URL?
    
    @State private var image: UIImage?
    @State private var showShareSheet = false
    
    var body: some View {
        
        WebImage(url: url, options: [.scaleDownLargeImages])
            .onSuccess { image,_,_ in
                self.image = image
            }
            .purgeable(true)
            .maxBufferSize(.max)
            .resizable()
            .scaledToFill()
            .clipShape(Circle())
            .modifier(ImageContextMenuModifier(url: url, image: image, showShareSheet: $showShareSheet))
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: [url])
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
