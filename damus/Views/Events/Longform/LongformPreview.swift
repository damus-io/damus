//
//  LongformPreview.swift
//  damus
//
//  Created by William Casarin on 2023-06-01.
//

import SwiftUI

struct LongformPreviewBody: View {
    let state: DamusState
    let event: LongformEvent
    let options: EventViewOptions
    @ObservedObject var artifacts: NoteArtifactsModel

    init(state: DamusState, ev: LongformEvent, options: EventViewOptions) {
        self.state = state
        self.event = ev
        self.options = options

        self._artifacts = ObservedObject(wrappedValue: state.events.get_cache_data(ev.event.id).artifacts_model)
    }

    init(state: DamusState, ev: NostrEvent, options: EventViewOptions) {
        self.state = state
        self.event = LongformEvent.parse(from: ev)
        self.options = options

        self._artifacts = ObservedObject(wrappedValue: state.events.get_cache_data(ev.id).artifacts_model)
    }

    func Words(_ words: Int) -> Text {
        let wordCount = pluralizedString(key: "word_count", count: words)
        return Text(wordCount)
    }

    var body: some View {
        Group {
            if options.contains(.wide) {
                Main.padding(.horizontal)
            } else {
                Main
            }
        }
    }

    var Main: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title = event.title {
                Text(title)
                    .font(.title)
            } else {
                Text("Untitled", comment: "Text indicating that the long-form note title is untitled.")
                    .font(.title)
            }

            Text(event.summary ?? "")
                .foregroundColor(.gray)

            if case .loaded(let arts) = artifacts.state,
               case .longform(let longform) = arts
            {
                Words(longform.words).font(.footnote)
            }
        }
    }
}

struct LongformPreview: View {
    let state: DamusState
    let event: LongformEvent
    let options: EventViewOptions

    init(state: DamusState, ev: NostrEvent, options: EventViewOptions) {
        self.state = state
        self.event = LongformEvent.parse(from: ev)
        self.options = options.union(.no_mentions)
    }

    var body: some View {
        EventShell(state: state, event: event.event, options: options) {
            LongformPreviewBody(state: state, ev: event, options: options)
        }
    }
}

struct LongformPreview_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            LongformPreview(state: test_damus_state, ev: test_longform_event.event, options: [])

            LongformPreview(state: test_damus_state, ev: test_longform_event.event, options: [.wide])
        }
        .frame(height: 400)
    }
}
