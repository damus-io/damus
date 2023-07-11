//
//  LongformPreview.swift
//  damus
//
//  Created by William Casarin on 2023-06-01.
//

import SwiftUI

struct LongformPreview: View {
    let state: DamusState
    let event: LongformEvent
    let options: EventViewOptions
    @ObservedObject var artifacts: NoteArtifactsModel
    
    init(state: DamusState, ev: NostrEvent, options: EventViewOptions) {
        self.state = state
        self.event = LongformEvent.parse(from: ev)
        self.options = options

        self._artifacts = ObservedObject(wrappedValue: state.events.get_cache_data(ev.id).artifacts_model)
    }
    
    func Words(_ words: Int) -> Text {
        Text(verbatim: words.description) + Text(verbatim: " ") + Text("Words")
    }

    var Main: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(event.title ?? "Untitled")
                .font(.title)

            Text(event.summary ?? "")
                .foregroundColor(.gray)

            if case .loaded(let arts) = artifacts.state,
               case .parts(let parts) = arts
            {
                Words(parts.words).font(.footnote)
            }
        }
    }

    var body: some View {
        EventShell(state: state, event: event.event, options: options.union(.no_mentions)) {

            if options.contains(.wide) {
                Main.padding(.horizontal)
            } else {
                Main
            }
        }
    }
}

struct LongformPreview_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            LongformPreview(state: test_damus_state(), ev: test_longform_event.event, options: [])

            LongformPreview(state: test_damus_state(), ev: test_longform_event.event, options: [.wide])
        }
        .frame(height: 400)
    }
}
