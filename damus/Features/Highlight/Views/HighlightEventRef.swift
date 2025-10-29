//
//  HighlightEventRef.swift
//  damus
//
//  Created by eric on 4/29/24.
//

import SwiftUI
import Kingfisher

struct HighlightEventRef: View {
    let damus_state: DamusState
    let event_ref: NoteId

    init(damus_state: DamusState, event_ref: NoteId) {
        self.damus_state = damus_state
        self.event_ref = event_ref
    }

    struct FailedImage: View {
        var body: some View {
            Image("markdown")
                .resizable()
                .foregroundColor(DamusColors.neutral6)
                .background(DamusColors.neutral3)
                .frame(width: 35, height: 35)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.gray.opacity(0.5), lineWidth: 0.5))
                .scaledToFit()
        }
    }

    var body: some View {
        EventLoaderView(damus_state: damus_state, event_id: event_ref) { event in
            EventMutingContainerView(damus_state: damus_state, event: event) {
                if event.known_kind == .longform {
                    Button(action: {
                        let longform_event = LongformEvent.parse(from: event)
                        damus_state.nav.push(route: .Longform(event: longform_event))
                    }) {
                    HStack(alignment: .top, spacing: 10) {
                        let longform_event = LongformEvent.parse(from: event)
                        if let url = longform_event.image {
                            KFAnimatedImage(url)
                                .callbackQueue(.dispatch(.global(qos:.background)))
                                .backgroundDecode(true)
                                .imageContext(.note, disable_animation: true)
                                .image_fade(duration: 0.25)
                                .cancelOnDisappear(true)
                                .configure { view in
                                    view.framePreloadCount = 3
                                }
                                .background {
                                    FailedImage()
                                }
                                .frame(width: 35, height: 35)
                                .kfClickable()
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.gray.opacity(0.5), lineWidth: 0.5))
                                .scaledToFit()
                        } else {
                            FailedImage()
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text(longform_event.title ?? NSLocalizedString("Untitled", comment: "Title of longform event if it is untitled."))
                                .font(.system(size: 14, weight: .bold))
                                .lineLimit(1)

                            let profile_txn = damus_state.profiles.lookup(id: longform_event.event.pubkey, txn_name: "highlight-profile")
                            let profile = profile_txn?.unsafeUnownedValue

                            if let display_name = profile?.display_name {
                                Text(display_name)
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            } else if let name = profile?.name {
                                Text(name)
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding([.leading, .vertical], 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(DamusColors.neutral3, lineWidth: 2)
                    )
                    }
                    .buttonStyle(PlainButtonStyle())
                } else {
                    EmptyView()
                }
            }
        }
    }
}
