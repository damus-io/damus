//
//  CarouselImageContainerView.swift
//  damus
//
//  Created by William Casarin on 2023-03-23.
//

import SwiftUI
import Kingfisher

    
struct ImageContainerView: View {
    let cache: EventCache
    let url: MediaUrl
    
    @State private var image: UIImage?
    @State private var showShareSheet = false
    @ObservedObject var imageSaver = ImageSaver()

    let disable_animation: Bool
    
    private struct ImageHandler: ImageModifier {
        @Binding var handler: UIImage?
        
        func modify(_ image: UIImage) -> UIImage {
            handler = image
            return image
        }
    }
    
    func Img(url: URL) -> some View {
        KFAnimatedImage(url)
            .imageContext(.note, disable_animation: disable_animation)
            .configure { view in
                view.framePreloadCount = 3
            }
            .imageModifier(ImageHandler(handler: $image))
            .clipped()
            .modifier(ImageContextMenuModifier(url: url, image: image, imageSaver: imageSaver, showShareSheet: $showShareSheet))
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: [url])
            }
            .alert(
                imageSaver.errorTitle,
                isPresented: $imageSaver.error,
                actions: {
                    if imageSaver.errorType == .permissions {
                        Button("Settings") {
                            UIApplication.shared.open(URL(string: UIApplication.openSettingsURLString)!)
                        }
                        Button("Cancel", role: .cancel) {}
                    }
                },
                message: { Text(imageSaver.errorMessage) }
            )
    }
    
    var body: some View {
        Group {
            switch url {
            case .image(let url):
                Img(url: url)
            case .video(let url):
                DamusVideoPlayer(url: url, model: cache.get_video_player_model(url: url), video_size: .constant(nil))
            }
        }
    }
}

let test_image_url = URL(string: "https://jb55.com/red-me.jpg")!

struct ImageContainerView_Previews: PreviewProvider {
    static var previews: some View {
        ImageContainerView(cache: test_damus_state().events, url: .image(test_image_url), disable_animation: false)
    }
}
