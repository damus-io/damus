//
//  LongformEvent.swift
//  damus
//
//  Created by William Casarin on 2023-06-01.
//

import SwiftUI

struct LongformEvent {
    let event: NostrEvent
    
    var title: String? = nil
    var image: URL? = nil
    var summary: String? = nil
    var published_at: Date? = nil
    
    static func parse(from ev: NostrEvent) -> LongformEvent {
        var longform = LongformEvent(event: ev)
        
        for tag in ev.tags {
            guard tag.count >= 2 else { continue }
            switch tag[0] {
            case "title": longform.title = tag[1]
            case "image":   longform.image = URL(string: tag[1])
            case "summary": longform.summary = tag[1]
            case "published_at":
                longform.published_at = Double(tag[1]).map { d in Date(timeIntervalSince1970: d) }
            default:
                break
            }
        }
        
        return longform
    }
}

struct LongformView: View {
    let state: DamusState
    let event: LongformEvent
    @ObservedObject var artifacts: NoteArtifactsModel
    
    init(state: DamusState, event: LongformEvent) {
        self.state = state
        self.event = event
        self._artifacts = ObservedObject(wrappedValue: state.events.get_cache_data(event.event.id).artifacts_model)
    }
    
    var options: EventViewOptions {
        return [.wide, .no_mentions, .no_replying_to]
    }
    
    var body: some View {
        EventShell(state: state, event: event.event, options: options) {
            
            Content
        }
    }
    
    var Content: some View {
        Group {
            if case .loaded(let artifacts) = artifacts.state {
                SelectableText(attributedString: artifacts.content.attributed, size: .selected)
                    .padding(.horizontal)
            } else {
                Text("")
            }
        }
    }
}

let test_longform_event = LongformEvent.parse(from:
        .init(content: "## Let me tell you why coffee is awesome\n**IT JUST IS**",
              pubkey: "pk",
              kind: NostrKind.longform.rawValue,
              tags: [
                ["title", "Coffee is awesome"],
                ["summary", "Did you know coffee is awesome?"],
                ["published_at", "1685638715"],
                ["t", "coffee"],
                ["t", "coffeechain"],
                ["image", "https://cdn.jb55.com/s/038fe8f558153b52.jpg"],
              ])
)

struct LongformView_Previews: PreviewProvider {
    static var previews: some View {
        LongformView(state: test_damus_state(), event: test_longform_event)
    }
}
