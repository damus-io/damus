//
//  BannerImageView.swift
//  damus
//
//  Created by Jason Jōb on 2023-01-10.
//

import SwiftUI
import Kingfisher

struct EditBannerImageView: View {
    
    var damus_state: DamusState
    @ObservedObject var viewModel: ImageUploadingObserver
    let callback: (URL?) -> Void
    let defaultImage = UIImage(named: "damoose") ?? UIImage()
    let safeAreaInsets: EdgeInsets
    
    @State var banner_image: URL? = nil

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            KFAnimatedImage(get_banner_url(banner: banner_image?.absoluteString, pubkey: damus_state.pubkey, profiles: damus_state.profiles))
                .imageContext(.banner, disable_animation: damus_state.settings.disable_animation)
                .configure { view in
                    view.framePreloadCount = .max
                }
                .placeholder { _ in
                    Color(uiColor: .secondarySystemBackground)
                }
                .onFailureImage(defaultImage)
                .kfClickable()
            
            EditPictureControl(
                uploader: damus_state.settings.default_media_uploader,
                context: .normal,
                keypair: damus_state.keypair,
                pubkey: damus_state.pubkey,
                current_image_url: $banner_image,
                upload_observer: viewModel,
                callback: callback
            )
                .padding(10)
                .backwardsCompatibleSafeAreaPadding(self.safeAreaInsets)
                .accessibilityLabel(NSLocalizedString("Edit banner image", comment: "Accessibility label for edit banner image button"))
                .accessibilityIdentifier(AppAccessibilityIdentifiers.own_profile_banner_image_edit_button.rawValue)
        }
    }
}

extension View {
    fileprivate func backwardsCompatibleSafeAreaPadding(_ insets: EdgeInsets) -> some View {
        if #available(iOS 17.0, *) {
            return self.safeAreaPadding(insets)
        } else {
            return self.padding(.top, insets.top)
        }
    }
}

struct InnerBannerImageView: View {
    let disable_animation: Bool
    let url: URL?
    let defaultImage = UIImage(named: "damoose") ?? UIImage()

    var body: some View {
        ZStack {
            Color(uiColor: .systemBackground)
            
            if (url != nil) {
                KFAnimatedImage(url)
                    .imageContext(.banner, disable_animation: disable_animation)
                    .configure { view in
                        view.framePreloadCount = 3
                    }
                    .placeholder { _ in
                        Color(uiColor: .secondarySystemBackground)
                    }
                    .onFailureImage(defaultImage)
                    .kfClickable()
            } else {
                Image(uiImage: defaultImage).resizable()
            }
        }
    }
}

/// Displays a user's profile banner image.
///
/// Respects Low Data Mode and shows a stylish placeholder when data saving is active.
/// Streams profile updates to automatically refresh the banner when available.
struct BannerImageView: View {
    let disable_animation: Bool
    let pubkey: Pubkey
    let profiles: Profiles
    let damusState: DamusState
    @ObservedObject var settings: UserSettingsStore
    
    @State var banner: String?
    @StateObject private var networkMonitor = NetworkMonitor.shared
    
    init(pubkey: Pubkey, profiles: Profiles, disable_animation: Bool, banner: String? = nil, damusState: DamusState, settings: UserSettingsStore) {
        self.pubkey = pubkey
        self.profiles = profiles
        self._banner = State(initialValue: banner)
        self.disable_animation = disable_animation
        self.damusState = damusState
        self.settings = settings
    }
    
    /// Returns true if we should block loading due to Low Data Mode.
    private var shouldBlockLoading: Bool {
        settings.low_data_mode || networkMonitor.isLowDataMode
    }
    
    var body: some View {
        Group {
            if shouldBlockLoading {
                BannerPlaceholder()
            } else {
                InnerBannerImageView(disable_animation: disable_animation, url: get_banner_url(banner: banner, pubkey: pubkey, profiles: profiles))
            }
        }
        .task {
            for await profile in await damusState.nostrNetwork.profilesManager.streamProfile(pubkey: pubkey) {
                if let bannerImage = profile.banner, bannerImage != self.banner {
                    self.banner = bannerImage
                }
            }
        }
    }
}

/// A stylish wide placeholder for profile banners in Low Data Mode.
///
/// Features a landscape/panorama icon with a subtle shimmer effect
/// to indicate the banner image is hidden to save data.
struct BannerPlaceholder: View {
    @State private var shimmerOffset: CGFloat = -1
    
    var body: some View {
        ZStack {
            // Gradient background simulating a landscape
            LinearGradient(
                colors: [
                    Color.blue.opacity(0.15),
                    Color.purple.opacity(0.1),
                    Color.gray.opacity(0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            
            // Shimmer overlay
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.clear,
                            Color.white.opacity(0.2),
                            Color.clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .offset(x: shimmerOffset * 400)
                .animation(
                    Animation.linear(duration: 2.0)
                        .repeatForever(autoreverses: false),
                    value: shimmerOffset
                )
            
            // Center icon
            VStack(spacing: 4) {
                Image(systemName: "panorama")
                    .font(.system(size: 32))
                    .foregroundColor(.gray.opacity(0.5))
                Text(NSLocalizedString("Banner hidden", comment: "Text shown when banner is hidden in low data mode"))
                    .font(.caption2)
                    .foregroundColor(.gray.opacity(0.6))
            }
        }
        .onAppear {
            shimmerOffset = 1
        }
    }
}


func get_banner_url(banner: String?, pubkey: Pubkey, profiles: Profiles) -> URL? {
    let bannerUrlString = banner ?? (try? profiles.lookup(id: pubkey)?.banner) ?? ""
    if let url = URL(string: bannerUrlString) {
        return url
    }
    return nil
}

struct BannerImageView_Previews: PreviewProvider {
    static var previews: some View {
        BannerImageView(
            pubkey: test_pubkey,
            profiles: make_preview_profiles(test_pubkey),
            disable_animation: false,
            damusState: test_damus_state,
            settings: test_damus_state.settings
        )
    }
}

