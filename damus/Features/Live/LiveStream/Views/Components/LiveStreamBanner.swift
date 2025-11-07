//
//  LiveStreamBanner.swift
//  damus
//
//  Created by eric on 8/8/25.
//

import SwiftUI
import Kingfisher

struct LiveStreamBanner: View {
    let state: DamusState
    let options: EventViewOptions
    var image: URL? = nil
    var preview: Bool

    func Placeholder(url: URL, preview: Bool) -> some View {
        Group {
            if let meta = state.events.lookup_img_metadata(url: url),
               case .processed(let blurhash) = meta.state {
                Image(uiImage: blurhash)
                    .resizable()
                    .frame(minWidth: UIScreen.main.bounds.width, minHeight: preview ? 200 : 200, maxHeight: preview ? 200 : 200)
            } else {
                DamusColors.adaptableWhite
            }
        }
    }

    func titleImage(url: URL, preview: Bool) -> some View {
        KFAnimatedImage(url)
            .callbackQueue(.dispatch(.global(qos:.background)))
            .backgroundDecode(true)
            .imageContext(.note, disable_animation: state.settings.disable_animation)
            .image_fade(duration: 0.25)
            .cancelOnDisappear(true)
            .configure { view in
                view.framePreloadCount = 3
            }
            .background {
                Placeholder(url: url, preview: preview)
            }
            .aspectRatio(contentMode: .fill)
            .frame(minWidth: UIScreen.main.bounds.width, minHeight: preview ? 200 : 200, maxHeight: preview ? 200 : 200)
            .kfClickable()
            .cornerRadius(1)
    }

    var body: some View {
        if let url = image {
            if (self.options.contains(.no_media)) {
                EmptyView()
            } else {
                titleImage(url: url, preview: preview)
            }
        } else {
            Text(NSLocalizedString("No cover image", comment: "Text letting user know there is no cover image."))
                .bold()
                .foregroundColor(.white)
                .frame(width: UIScreen.main.bounds.width, height: 200)
                .background(DamusGradient.gradient.opacity(0.75))
            Divider()
        }
    }
}
