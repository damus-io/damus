//
//  LiveStreamView.swift
//  damus
//
//  Created by eric on 7/25/25.
//

import SwiftUI
import Kingfisher

struct LiveStreamView: View {
    let state: DamusState
    let event: LiveEvent
    @StateObject var model: LiveEventModel

    @Environment(\.colorScheme) var colorScheme
    @Environment(\.presentationMode) var presentationMode

    @ObservedObject var artifacts: NoteArtifactsModel


    @State private var dragOffset: CGSize = .zero
    @State private var isDragging = false
    @State private var currentVideoModel: DamusVideoPlayer?

    init(state: DamusState, ev: LiveEvent, model: LiveEventModel) {
        self.state = state
        self.event = ev
        self._model = StateObject(wrappedValue: model)

        self._artifacts = ObservedObject(wrappedValue: state.events.get_cache_data(ev.event.id).artifacts_model)
    }

    init(state: DamusState, ev: NostrEvent, model: LiveEventModel) {
        self.state = state
        self.event = LiveEvent.parse(from: ev)
        self._model = StateObject(wrappedValue: model)

        self._artifacts = ObservedObject(wrappedValue: state.events.get_cache_data(ev.id).artifacts_model)
    }

    func content_filter(_ pubkeys: [Pubkey]) -> ((NostrEvent) -> Bool) {
        var filters = ContentFilters.defaults(damus_state: self.state)
        filters.append({ pubkeys.contains($0.pubkey) })
        return ContentFilters(filters: filters).filter
    }

    func setupVideoModel() {
        if let streamingURL = event.streaming {
            currentVideoModel = state.video.get_player(for: streamingURL)
//            currentVideoModel = state.video.get_player(for: streamingURL, title: event.title ?? "Untitled", link: streamingURL.absoluteString, artist: "Nostrich", artwork: event.image?.absoluteString ?? "")
        } else if let recordingURL = event.recording {
            currentVideoModel = model.damus_state.video.get_player(for: recordingURL)
//            currentVideoModel = model.damus_state.video.get_player(for: recordingURL, title: event.title ?? "Untitled", link: recordingURL.absoluteString, artist: "Nostrich", artwork: event.image?.absoluteString ?? "")
        }
    }

    var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                if value.translation.height > 0 {
                    dragOffset = value.translation
                    isDragging = true
                }
            }
            .onEnded { value in
                isDragging = false

                if value.translation.height > 100 {
                    withAnimation(.easeOut(duration: 0.3)) {
                        dragOffset.height = UIScreen.main.bounds.height
                    }

                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        presentationMode.wrappedValue.dismiss()
                    }
                } else {
                    withAnimation(.spring()) {
                        dragOffset = .zero
                    }
                }
            }
    }

    var body: some View {
        VStack(spacing: 0) {
            LiveEventHeader
                .highPriorityGesture(dragGesture, including: .all)

            LiveChatHomeView(state: state, event: event, model: LiveChatModel(damus_state: state, root: event.event.pubkey.hex(), dtag: event.uuid ?? ""))
                .scrollDismissesKeyboard(.immediately)
        }
        .offset(y: dragOffset.height)
        .opacity(isDragging ? Double(1 - min(abs(dragOffset.height) / 250, 0.5)) : 1.0)
        .animation(.interactiveSpring(), value: dragOffset)
        .navigationBarBackButtonHidden(true)
        .onAppear {
            notify(.display_tabbar(false))
            model.subscribe()
            setupVideoModel()
        }
        .onDisappear {
            notify(.display_tabbar(true))
            model.unsubscribe()
        }
    }

    var LiveEventHeader: some View {
        VStack(alignment: .leading, spacing: 0) {

            ZStack {
                if let videoModel = currentVideoModel {
                    DamusVideoPlayerView(
                        model: videoModel,
                        coordinator: state.video,
                        style: .preview(on_tap: {})
                    )
                } else {
                    LiveStreamBanner(state: state, options: EventViewOptions(), image: event.image, preview: false)
                }
            }
            .frame(width: UIScreen.main.bounds.width, height: 250)
            .fixedSize(horizontal: true, vertical: true)
            .background(Color.black)

            if !event.publicKeys.isEmpty {
                LiveStreamProfile(state: state, pubkey: event.publicKeys[0], size: 35)
            } else {
                LiveStreamProfile(state: state, pubkey: event.event.pubkey, size: 35)
            }

            if let title = event.title {
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                    .fontWeight(.bold)
                    .padding(.horizontal, 5)
            }

           // TO DO: Add description in sheet
        }
    }
}


struct LiveStreamView_Previews: PreviewProvider {
    static var previews: some View {
        LiveStreamView(state: test_damus_state, ev: test_live_event, model: LiveEventModel(damus_state: test_damus_state))
            .environmentObject(OrientationTracker())
    }
}
