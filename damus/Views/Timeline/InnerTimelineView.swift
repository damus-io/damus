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
    let debouncer: Debouncer
    @State var pages: Int = 0
    @State var max_pages: Int = 0

    init(events: EventHolder, damus: DamusState, filter: @escaping (NostrEvent) -> Bool) {
        self.events = events
        self.state = damus
        self.filter = filter
        self.debouncer = Debouncer(interval: 0.5)
    }
    
    var event_options: EventViewOptions {
        if self.state.settings.truncate_timeline_text {
            return [.wide, .truncate_content]
        }
        
        return [.wide]
    }
    
    func is_page_in_range(ind: Int) -> Bool {
        let page_ind = (pages-1) * Constants.VSTACK_LIMIT
        let start_ind = page_ind - Int(Double(Constants.VSTACK_LIMIT) / Constants.VSTACK_LIMIT_EV_THRESHOLD)
        let end_ind = page_ind + Int(Double(Constants.VSTACK_LIMIT) * (1.0+(1.0/Constants.VSTACK_LIMIT_EV_THRESHOLD)))
        return ind >= start_ind && ind < end_ind
    }

    var body: some View {
        VStack(spacing: 0) {
            let events = self.events.events
            if events.isEmpty {
                EmptyTimelineView()
            } else {
                let evs = events.filter(filter)
                let indexed = Array(zip(evs, 0...Constants.VSTACK_LIMIT * pages))
                ForEach(indexed, id: \.0.id) { tup in
                    let ev = tup.0
                    let ind = tup.1
                    if is_page_in_range(ind: ind) {
                        EventView(damus: state, event: ev, options: event_options)
                            .onTapGesture {
                                let event = ev.get_inner_event(cache: state.events) ?? ev
                                let thread = ThreadModel(event: event, damus_state: state)
                                state.nav.push(route: Route.Thread(thread: thread))
                            }
                            .padding(.top, 7)
                            .onAppear {
                                // TODO: preload next page
                                preload_events(state: state, events: [ev])
                            }
                            .modifier(SizeReader { size in
                                let height = size.height
                                print("SizeReader height \(height)")
                                if height > state.events.get_height(ev.id) ?? 0.0 {
                                    state.events.set_height(ev.id, height: height)
                                }
                            })
                        ThiccDivider()
                            .padding([.top], 7)
                    } else {
                        Color.clear
                            .frame(height: state.events.get_height(ev.id))
                    }

                }

                GeometryReader { geometry in
                    ProgressView().progressViewStyle(.circular)
                        .preference(key: ViewOffsetKey.self, value: geometry.frame(in: .global).minY)
                }
                .frame(height: 20.0)
            }
        }
        .onReceive(handle_notify(.scroll_to_top)) { _ in
            pages = 1
        }
        .onPreferenceChange(ViewOffsetKey.self) { value in
            print("timeline: pages:\(pages) value:\(value)")
            debouncer.debounce_immediate {
                if events.events.count > 0 && value > 0.0 && value < Constants.VSTACK_LIMIT_THRESHOLD { // 'someThreshold' is the y-coordinate value that represents the bottom
                    pages += 1
                    max_pages = max(max_pages, pages)
                    print("timeline: Near the bottom pages:\(pages) \(value)")
                    // Perform your action here
                }
            }
        }
        //.padding(.horizontal)
    }
}

struct InnerTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        InnerTimelineView(events: test_event_holder, damus: test_damus_state, filter: { _ in true })
            .frame(width: 300, height: 500)
            .border(Color.red)
    }
}


struct ViewOffsetKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}


struct SizeReader: ViewModifier {
    var onSizeChange: (CGSize) -> Void

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { geometry in
                Color.clear
                    .preference(key: SizePreferenceKey.self, value: geometry.size)
                    .onPreferenceChange(SizePreferenceKey.self, perform: onSizeChange)
            }
        )
    }
}

struct SizePreferenceKey: PreferenceKey {
    static var defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {}
}
