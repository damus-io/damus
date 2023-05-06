//
//  CarouselImageContainerView.swift
//  damus
//
//  Created by William Casarin on 2023-03-23.
//

import SwiftUI
import Kingfisher

    
struct ImageContainerView: View {
    let url: URL?
    
    @State private var image: UIImage?
    @State private var showShareSheet = false
    
    let disable_animation: Bool
    
    private struct ImageHandler: ImageModifier {
        @Binding var handler: UIImage?
        
        func modify(_ image: UIImage) -> UIImage {
            handler = image
            return image
        }
    }
    
    var body: some View {
        
        KFAnimatedImage(url)
            .imageContext(.note, disable_animation: disable_animation)
            .configure { view in
                view.framePreloadCount = 3
            }
            .imageModifier(ImageHandler(handler: $image))
            .clipped()
            .modifier(ImageContextMenuModifier(url: url, image: image, showShareSheet: $showShareSheet))
            .sheet(isPresented: $showShareSheet) {
                ShareSheet(activityItems: [url])
            }
    }
}

let test_image_url = URL(string: "https://jb55.com/red-me.jpg")!

struct ImageContainerView_Previews: PreviewProvider {
    static var previews: some View {
        ImageContainerView(url: test_image_url, disable_animation: false)
    }
}
