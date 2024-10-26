//
//  ProfileZoomView.swift
//  damus
//
//  Created by scoder1747 on 12/27/22.
//
import SwiftUI
import Kingfisher

struct ProfileImageContainerView: View {
    let url: URL?
    let settings: UserSettingsStore
    
    @State private var image: UIImage?
    @State private var showShareSheet = false
    
    private struct ImageHandler: ImageModifier {
        @Binding var handler: UIImage?
        
        func modify(_ image: UIImage) -> UIImage {
            handler = image
            return image
        }
    }
    
    var body: some View {
        
        KFAnimatedImage(url)
            .imageContext(.pfp, disable_animation: settings.disable_animation)
            .configure { view in
                view.framePreloadCount = 3
            }
            .imageModifier(ImageHandler(handler: $image))
            .clipShape(Circle())
            .modifier(ImageContextMenuModifier(url: url, image: image, settings: settings, showShareSheet: $showShareSheet))
            .kfClickable()
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: [url])
            }
    }
}

enum NavDismissBarContainer {
    case fullScreenCarousel
    case profilePicImageView
}

struct NavDismissBarView: View {
    
    @Environment(\.presentationMode) var presentationMode
    let navDismissBarContainer: NavDismissBarContainer
    
    init(navDismissBarContainer: NavDismissBarContainer) {
        self.navDismissBarContainer = navDismissBarContainer
    }
    
    var body: some View {
        HStack {
            Button(action: {
                presentationMode.wrappedValue.dismiss()
            }, label: {
                switch navDismissBarContainer {
                case .profilePicImageView:
                    Image("close")
                        .frame(width: 33, height: 33)
                        .background(.regularMaterial)
                        .clipShape(Circle())
                    
                case .fullScreenCarousel:
                    Image("close")
                        .frame(width: 33, height: 33)
                        .background(.damusBlack)
                        .clipShape(Circle())
                }
            })
            
            Spacer()
        }
        .padding()
    }
}

struct ProfilePicImageView: View {
    let pubkey: Pubkey
    let profiles: Profiles
    let settings: UserSettingsStore
    
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            ZoomableScrollView {
                ProfileImageContainerView(url: get_profile_url(picture: nil, pubkey: pubkey, profiles: profiles), settings: settings)
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
        .overlay(NavDismissBarView(navDismissBarContainer: .profilePicImageView), alignment: .top)
    }
}

struct ProfileZoomView_Previews: PreviewProvider {
    static var previews: some View {
        ProfilePicImageView(
            pubkey: test_pubkey,
            profiles: make_preview_profiles(test_pubkey),
            settings: test_damus_state.settings
        )
    }
}
