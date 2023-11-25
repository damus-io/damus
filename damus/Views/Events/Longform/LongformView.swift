//
//  LongformEvent.swift
//  damus
//
//  Created by William Casarin on 2023-06-01.
//

import SwiftUI

struct LongformView: View {
    let state: DamusState
    let event: LongformEvent
    @ObservedObject var artifacts: NoteArtifactsModel
    
    init(state: DamusState, event: LongformEvent, artifacts: NoteArtifactsModel? = nil) {
        self.state = state
        self.event = event
        self._artifacts = ObservedObject(wrappedValue: artifacts ?? state.events.get_cache_data(event.event.id).artifacts_model)
    }
    
    var options: EventViewOptions {
        return [.wide, .no_mentions, .no_replying_to]
    }
    
    var body: some View {
        EventShell(state: state, event: event.event, options: options) {
            SelectableText(attributedString: AttributedString(stringLiteral: event.title ?? "Untitled"), size: .title)

            NoteContentView(damus_state: state, event: event.event, show_images: true, size: .selected, options: options)
        }
    }
}

let test_longform_event = LongformEvent.parse(from: NostrEvent(
    content: longform_long_test_data,
    keypair: test_keypair,
    kind: NostrKind.longform.rawValue,
    tags: [
        ["title", "What is WASTOIDS?"],
        ["summary", "WASTOIDS is an audio/visual feed, created by Sam Means..."],
        ["published_at", "1685638715"],
        ["t", "coffee"],
        ["t", "coffeechain"],
        ["image", "https://cdn.jb55.com/s/038fe8f558153b52.jpg"],
    ])!
)

struct LongformView_Previews: PreviewProvider {
    static var previews: some View {
        let st = test_damus_state
        let artifacts = render_note_content(ev: test_longform_event.event, profiles: st.profiles, keypair: Keypair(pubkey: .empty, privkey: nil))

        let model = NoteArtifactsModel(state: .loaded(artifacts))
        ScrollView {
            LongformView(state: st, event: test_longform_event, artifacts: model)
        }
    }
}
