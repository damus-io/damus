//
//  InnerTimelineView.swift
//  damus
//
//  Created by William Casarin on 2023-02-20.
//

import SwiftUI


struct InnerTimelineView: View {
    @ObservedObject var events: EventHolder
    let state: DamusState
    let filter: (NostrEvent) -> Bool

    init(events: EventHolder, damus: DamusState, filter: @escaping (NostrEvent) -> Bool, apply_mute_rules: Bool = true) {
        self.events = events
        self.state = damus
        self.filter = apply_mute_rules ? { filter($0) && !damus.mutelist_manager.is_event_muted($0) } : filter
    }
    
    var event_options: EventViewOptions {
        if self.state.settings.truncate_timeline_text {
            return [.wide, .truncate_content]
        }
        
        return [.wide]
    }
    
    var main_content: some View {
        LazyVStack(spacing: 0) {
            let events = self.events.events
            if events.isEmpty {
                EmptyTimelineView()
            } else {
                let evs = events.filter(filter)
                let indexed = Array(zip(evs, 0...))
                ForEach(indexed, id: \.0.id) { tup in
                    let ev = tup.0
                    // Since NoteId is a struct (therefore a value type, not a reference type),
                    // assigning the id to a variable in Swift will cause the memory contents to be copied over,
                    // therefore ensuring we will *own* this piece of memory, reducing the risk of being rugged by Ndb today and in future as the codebase evolves.
                    // This is a 32-byte copy operation without any parsing, so it should in theory not regress performance significantly.
                    // Thanks for coming to my TED talk about this one line of code.
                    let ev_id = ev.id
                    let ind = tup.1
                    EventView(damus: state, event: ev, options: event_options)
                        .onTapGesture {
                            let event = ev.get_inner_event(cache: state.events) ?? ev
                            let thread = ThreadModel(event: event, damus_state: state)
                            state.nav.push(route: Route.Thread(thread: thread))
                        }
                        .padding(.top, 7)
                        .id(BlockID.note(ev_id))
                        .onAppear {
                            let to_preload =
                            Array([indexed[safe: ind+1]?.0,
                                   indexed[safe: ind+2]?.0,
                                   indexed[safe: ind+3]?.0,
                                   indexed[safe: ind+4]?.0,
                                   indexed[safe: ind+5]?.0
                                  ].compactMap({ $0 }))
                            
                            preload_events(state: state, events: to_preload)
                        }
                    
                    ThiccDivider()
                        .padding([.top], 7)
                }
            }
        }
    }
    
    var body: some View {
        if #available(iOS 17.0, *) {
            self.main_content
                .scrollTargetLayout()   // This helps us keep track of the scroll position by telling SwiftUI which VStack we should use for scroll position ids
        } else {
            // Fallback on earlier versions
            self.main_content
        }
    }
    
    enum BlockID: RawRepresentable, Hashable, Codable {
        case top
        case note(NoteId)
        
        // MARK: - Custom RawRepresentable implementation
        // Note: String RawRepresentable implementation is needed to be used with SceneStorage
        // Note: Declaring enum as a `String` for synthesized protocol conformance does not work as this is an enum with associated types
        
        typealias RawValue = String
        
        var rawValue: String {
            switch self {
                case .top:
                    return "top"
                case .note(let note_id):
                    return "note:\(note_id.hex())"
            }
        }
        
        init?(rawValue: String) {
            let components = rawValue.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            if components.count == 2 && components[0] == "note" {
                let second_component = String(components[1])
                guard let note_id = NoteId.init(hex: second_component) else { return nil }
                self = .note(note_id)
            } else if components[0] == "top" {
                self = .top
            }
            return nil
        }
    }
}

struct InnerTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        InnerTimelineView(events: test_event_holder, damus: test_damus_state, filter: { _ in true })
            .frame(width: 300, height: 500)
            .border(Color.red)
    }
}

