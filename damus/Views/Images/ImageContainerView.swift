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
    let settings: UserSettingsStore
    
    @Binding var imageDict: [URL: UIImage]
    @State private var image: UIImage?
    @State private var showShareSheet = false
    
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
    
    var body: some View {
        Group {
            switch url {
                case .image(let url):
                    Img(url: url)
                case .video(let url):
                    DamusVideoPlayer(url: url, video_size: .constant(nil), coordinator: video_coordinator, style: .full, visibility_tracking_method: .generic)
            }
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
