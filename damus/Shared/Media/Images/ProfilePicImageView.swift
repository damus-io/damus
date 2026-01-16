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
    @Binding var image: UIImage?
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

/// Full-screen view for displaying an expanded profile picture with zoom and share capabilities.
struct ProfilePicImageView: View {
    let pubkey: Pubkey
    let profiles: Profiles
    let settings: UserSettingsStore
    let nav: NavigationCoordinator
    let shouldShowEditButton: Bool
    let damusState: DamusState

    @State private var image: UIImage?
    @State private var showMenu = true
    @State private var picture: String?

    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        let url = get_profile_url(picture: picture, pubkey: pubkey, profiles: profiles)
        let _ = Log.debug("ProfilePicImageView: pubkey=%@ picture=%@ url=%@", for: .render, pubkey.hex(), picture ?? "nil", url.absoluteString)
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()

            ZoomableScrollView {
                ProfileImageContainerView(url: url, settings: settings, image: $image)
                    .aspectRatio(contentMode: .fit)
                    .padding(.top, Theme.safeAreaInsets?.top)
                    .padding(.bottom, Theme.safeAreaInsets?.bottom)
                    .padding(.horizontal)
                    .allowsHitTesting(false)
            }
            .ignoresSafeArea()
            .modifier(SwipeToDismissModifier(minDistance: 50, onDismiss: {
                presentationMode.wrappedValue.dismiss()
            }))
            .task {
                Log.debug("ProfilePicImageView: starting profile stream for %@", for: .render, pubkey.hex())
                for await profile in await damusState.nostrNetwork.profilesManager.streamProfile(pubkey: pubkey) {
                    guard let pic = profile.picture else {
                        Log.debug("ProfilePicImageView: got profile but no picture for %@", for: .render, pubkey.hex())
                        continue
                    }
                    Log.debug("ProfilePicImageView: got picture for %@: %@", for: .render, pubkey.hex(), pic)
                    self.picture = pic
                }
                Log.debug("ProfilePicImageView: stream ended for %@", for: .render, pubkey.hex())
            }
        }
        .overlay(
            Group {
                if showMenu {
                    HStack {
                        NavDismissBarView(navDismissBarContainer: .profilePicImageView)
                        if let image = image {
                            ShareLink(item: Image(uiImage: image),
                                      preview: SharePreview(NSLocalizedString("Damus Profile", comment: "Label for the preview of the profile picture"), image: Image(uiImage: image))) {
                                Image(systemName: "ellipsis")
                                    .frame(width: 33, height: 33)
                                    .background(.regularMaterial)
                                    .clipShape(Circle())
                            }
                            .padding(20)
                        }
                    }
                }
            },
            alignment: .top
        )
        .overlay(
            shouldShowEditButton && showMenu ?
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                    nav.push(route: Route.EditMetadata)
                }) {
                    Text("Edit", comment: "Edit Button for editing profile")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(Color("DamusPurple"))
                    Spacer()
                }
                .padding([.vertical, .leading], 20)
            : nil,
            alignment: .bottomLeading
        )
        .gesture(TapGesture(count: 1).onEnded {
            showMenu.toggle()
        })
        .animation(.easeInOut, value: showMenu)
    }
}

struct ProfileZoomView_Previews: PreviewProvider {
    static var previews: some View {
        ProfilePicImageView(
            pubkey: test_pubkey,
            profiles: test_damus_state.profiles,
            settings: test_damus_state.settings,
            nav: test_damus_state.nav,
            shouldShowEditButton: true,
            damusState: test_damus_state
        )
    }
}
