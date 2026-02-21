//
//  CarouselImageContainerView.swift
//  damus
//
//  Created by William Casarin on 2023-03-23.
//

import SwiftUI
import Kingfisher

    
struct ImageContainerView: View {
    let video_coordinator: DamusVideoCoordinator
    let url: MediaUrl
    /// User settings driving media loading behavior.
    @ObservedObject var settings: UserSettingsStore
    
    @Binding var imageDict: [URL: UIImage]
    @State private var image: UIImage?
    @State private var showShareSheet = false
    /// Shared monitor for Low Data Mode changes.
    @StateObject private var networkMonitor = NetworkMonitor.shared
    
    init(video_coordinator: DamusVideoCoordinator, url: MediaUrl, settings: UserSettingsStore, imageDict: Binding<[URL: UIImage]>) {
        self.video_coordinator = video_coordinator
        self.url = url
        self.settings = settings
        self._imageDict = imageDict
    }
    
    private struct ImageHandler: ImageModifier {
        @Binding var handler: UIImage?
        @Binding var imageDict: [URL: UIImage]
        let url: URL
        
        func modify(_ image: UIImage) -> UIImage {
            handler = image
            imageDict[url] = image
            return image
        }
    }
    
    func Img(url: URL) -> some View {
        KFAnimatedImage(url)
            .imageContext(.note, disable_animation: settings.disable_animation)
            .configure { view in
                view.framePreloadCount = 3
            }
            .imageModifier(ImageHandler(handler: $image, imageDict: $imageDict, url: url))
            .kfClickable()
            .clipped()
            .modifier(ImageContextMenuModifier(url: url, image: image, settings: settings, showShareSheet: $showShareSheet))
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: [url])
            }
    }
    
    /// Determines if media loading should be blocked due to low data mode.
    /// Checks both user preference and iOS system Low Data Mode.
    private var shouldBlockMediaLoading: Bool {
        settings.low_data_mode || networkMonitor.isLowDataMode
    }
    
    var body: some View {
        Group {
            if shouldBlockMediaLoading {
                // Low Data Mode: Show placeholder instead of loading media
                LowDataModePlaceholder(url: url, onTap: {
                    // Future: Allow manual load on tap
                })
            } else {
                switch url {
                    case .image(let url):
                        Img(url: url)
                    case .video(let url):
                        DamusVideoPlayerView(url: url, coordinator: video_coordinator, style: .no_controls(on_tap: nil))
                }
            }
        }
    }
}


/// A placeholder view displayed when media loading is disabled due to Low Data Mode.
///
/// This view shows a gray placeholder with an icon and localized text indicating
/// that media has been hidden to save data. Users can tap the placeholder to
/// manually load the content (future enhancement).
///
/// - Parameters:
///   - url: The `MediaUrl` of the hidden content.
///   - onTap: A closure called when the user taps the placeholder.
struct LowDataModePlaceholder: View {
    /// The URL of the media that was not loaded.
    let url: MediaUrl
    
    /// Called when the user taps the placeholder to request manual load.
    let onTap: () -> Void
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.gray.opacity(0.2))
            VStack(spacing: 8) {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundColor(.gray)
                Text(NSLocalizedString("Media hidden (Low Data Mode)", comment: "Placeholder text when media is blocked due to low data mode"))
                    .font(.caption)
                    .foregroundColor(.gray)
            }
        }
        .frame(minHeight: 150)
        .contentShape(Rectangle())
        .onTapGesture {
            onTap()
        }
    }
}


let test_image_url = URL(string: "https://jb55.com/red-me.jpg")!
fileprivate let test_video_url = URL(string: "http://cdn.jb55.com/s/zaps-build.mp4")!

struct ImageContainerView_Previews: PreviewProvider {
    static var previews: some View {
        @State var imageDict: [URL: UIImage] = [:]
        Group {
            ImageContainerView(video_coordinator: test_damus_state.video, url: .image(test_image_url), settings: test_damus_state.settings, imageDict: $imageDict)
                .previewDisplayName("Image")
            ImageContainerView(video_coordinator: test_damus_state.video, url: .video(test_video_url), settings: test_damus_state.settings, imageDict: $imageDict)
                .previewDisplayName("Video")
        }
        .environmentObject(OrientationTracker())
    }
}
