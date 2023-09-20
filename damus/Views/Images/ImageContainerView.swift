//
//  CarouselImageContainerView.swift
//  damus
//
//  Created by William Casarin on 2023-03-23.
//

import SwiftUI
import Kingfisher

    
struct ImageContainerView: View {
    let video_controller: VideoController
    let url: MediaUrl
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
    
    func Img(url: URL) -> some View {
        KFAnimatedImage(url)
            .imageContext(.note, disable_animation: settings.disable_animation)
            .configure { view in
                view.framePreloadCount = 3
            }
            .imageModifier(ImageHandler(handler: $image))
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
                DamusVideoPlayer(url: url, video_size: .constant(nil), controller: video_controller)
            }
        }
    }
}

let test_image_url = URL(string: "https://jb55.com/red-me.jpg")!

struct ImageContainerView_Previews: PreviewProvider {
    static var previews: some View {
        ImageContainerView(video_controller: test_damus_state.video, url: .image(test_image_url), settings: test_damus_state.settings)
    }
}
