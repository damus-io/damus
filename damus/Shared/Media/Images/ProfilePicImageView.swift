//
//  ProfileZoomView.swift
//  damus
//
//  Created by scoder1747 on 12/27/22.
//
import SwiftUI
import Kingfisher

/// Container view for displaying profile pictures with Kingfisher.
///
/// Respects Low Data Mode settings and shows a placeholder when data saving is active.
struct ProfileImageContainerView: View {
    let url: URL?
    let settings: UserSettingsStore
    @Binding var image: UIImage?
    @State private var showShareSheet = false
    @StateObject private var networkMonitor = NetworkMonitor.shared
    
    private struct ImageHandler: ImageModifier {
        @Binding var handler: UIImage?
        
        func modify(_ image: UIImage) -> UIImage {
            handler = image
            return image
        }
    }
    
    /// Returns true if we should block loading due to Low Data Mode.
    private var shouldBlockLoading: Bool {
        settings.low_data_mode || networkMonitor.isLowDataMode
    }
    
    var body: some View {
        if shouldBlockLoading {
            // Low Data Mode: Show stylish circular placeholder
            ProfilePicPlaceholder()
        } else {
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
}

/// A stylish circular placeholder for profile pictures in Low Data Mode.
///
/// Features a person silhouette icon with a subtle pulsing animation
/// to indicate that the image could be loaded on demand.
struct ProfilePicPlaceholder: View {
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.gray.opacity(0.3), Color.gray.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            
            Image(systemName: "person.fill")
                .font(.system(size: 40))
                .foregroundColor(.gray.opacity(0.6))
                .scaleEffect(isPulsing ? 1.05 : 1.0)
                .animation(
                    Animation.easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true),
                    value: isPulsing
                )
        }
        .overlay(
            Circle()
                .stroke(Color.gray.opacity(0.2), lineWidth: 2)
        )
        .onAppear {
            isPulsing = true
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
    let nav: NavigationCoordinator
    let shouldShowEditButton: Bool
    @State var image: UIImage?
    @State var showMenu = true
    
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        ZStack {
            Color(.systemBackground)
                .ignoresSafeArea()
            
            ZoomableScrollView {
                ProfileImageContainerView(url: get_profile_url(picture: nil, pubkey: pubkey, profiles: profiles), settings: settings, image: $image)
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
            profiles: make_preview_profiles(test_pubkey),
            settings: test_damus_state.settings, nav: test_damus_state.nav, shouldShowEditButton: true)
    }
}
