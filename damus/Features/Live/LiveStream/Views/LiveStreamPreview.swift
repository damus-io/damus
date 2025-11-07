//
//  LiveStreamPreview.swift
//  damus
//
//  Created by eric on 7/10/25.
//

import SwiftUI
import Kingfisher

struct LiveStreamPreviewBody: View {
    let state: DamusState
    let event: LiveEvent
    let options: EventViewOptions
    let header: Bool

    @ObservedObject var artifacts: NoteArtifactsModel

    init(state: DamusState, ev: LiveEvent, options: EventViewOptions, header: Bool) {
        self.state = state
        self.event = ev
        self.options = options
        self.header = header

        self._artifacts = ObservedObject(wrappedValue: state.events.get_cache_data(ev.event.id).artifacts_model)
    }

    init(state: DamusState, ev: NostrEvent, options: EventViewOptions, header: Bool) {
        self.state = state
        self.event = LiveEvent.parse(from: ev)
        self.options = options
        self.header = header

        self._artifacts = ObservedObject(wrappedValue: state.events.get_cache_data(ev.id).artifacts_model)
    }

    var body: some View {
        if event.status == .live {
            if let streamingURL = event.streaming {
                if streamingURL.absoluteString.hasSuffix(".m3u8") {
                    Group {
                        if options.contains(.wide) {
                            Main.padding(.horizontal)
                        } else {
                            Main
                        }
                    }
                }
            }
        }
    }

    var Main: some View {
        VStack(alignment: .leading, spacing: 0) {

            ZStack(alignment: .topLeading) {
                if state.settings.media_previews {
                    LiveStreamBanner(state: state, options: options, image: event.image, preview: true)
                }
                VStack {
                    if let status = event.status {
                        LiveStreamStatus(status: status, starts: event.starts)
                    }

                    Spacer()

                    LiveStreamViewers(state: state, currentParticipants: event.currentParticipants ?? 0, preview: true)
                        .padding(10)
                }
            }
            .frame(minWidth: UIScreen.main.bounds.width, minHeight: 200, maxHeight: 200)

            VStack(alignment: .leading) {
                LiveStreamProfile(state: state, pubkey: event.event.pubkey)

                Text(event.title ?? NSLocalizedString("Untitled", comment: "Title of follow list event if it is untitled."))
                    .font(header ? .title : .headline)
                    .padding(.horizontal, 10)

                EventTags(tags: event.hashtags)
            }
        }
    }
}

struct LiveStreamPreview: View {
    let state: DamusState
    let event: LiveEvent
    let options: EventViewOptions

    init(state: DamusState, ev: NostrEvent, options: EventViewOptions) {
        self.state = state
        self.event = LiveEvent.parse(from: ev)
        self.options = options.union(.no_mentions)
    }

    var body: some View {
        let _ = print(event)
        LiveStreamPreviewBody(state: state, ev: event, options: options, header: false)
    }
}

let test_live_event = LiveEvent.parse(from: NostrEvent(
    content: "",
    keypair: test_keypair,
    kind: NostrKind.live.rawValue,
    tags: [
        ["title", "DAMUSES MEETING"],
        ["summary", "Damus Team Meeting"],
        ["image", "https://damus.io/img/logo.png"],
        ["streaming", "https://ome.mapboss.co.th/live/local_019865b4-6814-71af-b86d-17d0c96d7867/llhls.m3u8"],
        ["recording", "https://damus.io"],
        ["status", "live"],
        ["t", "meeting"],
        ["t", "damus"]
    ])!
)


struct LiveStreamPreview_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            LiveStreamPreview(state: test_damus_state, ev: test_live_event.event, options: [])
        }
        .frame(height: 400)
    }
}
