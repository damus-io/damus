//
//  PostingTimelineView.swift
//  damus
//
//  Created by eric on 7/15/24.
//

import SwiftUI
import TipKit

struct PostingTimelineView: View {
    
    let damus_state: DamusState
    @ObservedObject var home: HomeModel
    /// Set this to `home.events`. This is separate from `home` because we need the events object to be directly observed so that we get instant view updates
    @ObservedObject var homeEvents: EventHolder
    @State var search: String = ""
    @State var results: [NostrEvent] = []
    @State var initialOffset: CGFloat?
    @State var offset: CGFloat?
    @State var showSearch: Bool = true
    @Binding var isSideBarOpened: Bool
    @Binding var active_sheet: Sheets?
    @FocusState private var isSearchFocused: Bool
    @State private var contentOffset: CGFloat = 0
    @State private var indicatorWidth: CGFloat = 0
    @State private var indicatorPosition: CGFloat = 0
    @State var headerHeight: CGFloat = 0
    @Binding var headerOffset: CGFloat
    @SceneStorage("PostingTimelineView.filter_state") var filter_state : FilterState = .posts_and_replies
    @State var timeline_source: TimelineSource = .follows
    
    @State private var damusTips: Any? = {
        if #available(iOS 18.0, *) {
            return TipGroup(.ordered) {
                TrustedNetworkButtonTip.shared
                TrustedNetworkRepliesTip.shared
                PostingTimelineSwitcherView.TimelineSwitcherTip.shared
            }
        }
        return nil
    }()

    var loading: Binding<Bool> {
        Binding(get: {
            return home.loading
        }, set: {
            home.loading = $0
        })
    }

    func content_filter(_ fstate: FilterState) -> ((NostrEvent) -> Bool) {
        var filters = ContentFilters.defaults(damus_state: damus_state)
        filters.append(fstate.filter)

        // If favourites feature is disabled, always use follows
        let sourceToUse = damus_state.settings.enable_favourites_feature ? timeline_source : .follows

        // Only apply friend_filter for follows timeline
        // Favorites timeline uses a dedicated EventHolder (favoriteEvents) that already contains only favorited users' events
        if sourceToUse == .follows {
            filters.append(damus_state.contacts.friend_filter)
        }
        return ContentFilters(filters: filters).filter
    }
    
    func contentTimelineView(filter: (@escaping (NostrEvent) -> Bool)) -> some View {
        let eventsSource = timeline_source == .favorites ? home.favoriteEvents : home.events
        return TimelineView<AnyView>(events: eventsSource, loading: self.loading, headerHeight: $headerHeight, headerOffset: $headerOffset, damus: damus_state, show_friend_icon: false, filter: filter, viewId: timeline_source)
    }
    
    func HeaderView() -> some View {
        VStack {
            VStack(spacing: 0) {
                // This is needed for the Dynamic Island
                HStack {}
                .frame(height: getSafeAreaTop())

                HStack(alignment: .center) {
                    TopbarSideMenuButton(damus_state: damus_state, isSideBarOpened: $isSideBarOpened)

                    Spacer()

                    HStack(alignment: .center) {
                        SignalView(state: damus_state, signal: home.signal)
                        if damus_state.settings.enable_favourites_feature {
                            Image(systemName: "square.stack")
                                .foregroundColor(DamusColors.purple)
                                .overlay(PostingTimelineSwitcherView(
                                    damusState: damus_state,
                                    timelineSource: $timeline_source
                                ))
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .overlay {
                    VStack(spacing: 2) {
                        Image("damus-home")
                            .resizable()
                            .frame(width: 30, height: 30)
                            .shadow(color: DamusColors.purple, radius: 2)
                        if damus_state.settings.enable_favourites_feature {
                            Text(timeline_source == .favorites ? timeline_source.description : " ")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .opacity(timeline_source == .favorites ? 1 : 0)
                        }
                    }
                    .opacity(isSideBarOpened ? 0 : 1)
                    .animation(isSideBarOpened ? .none : .default, value: isSideBarOpened)
                    .onTapGesture {
                        isSideBarOpened.toggle()
                    }
                }
            }
            .padding(.horizontal, 20)
            if #available(iOS 18.0, *), let tipGroup = damusTips as? TipGroup {
                TipView(tipGroup.currentTip as? PostingTimelineSwitcherView.TimelineSwitcherTip)
                    .tipBackground(.clear)
                    .tipViewStyle(TrustedNetworkButtonTipViewStyle())
                    .padding(.horizontal)
            }

            CustomPicker(tabs: [
                (NSLocalizedString("Notes", comment: "Label for filter for seeing only notes (instead of notes and replies)."), FilterState.posts),
                (NSLocalizedString("Notes & Replies", comment: "Label for filter for seeing notes and replies (instead of only notes)."), FilterState.posts_and_replies)
            ],
                         selection: $filter_state)

            Divider()
                .frame(height: 1)
        }
        .background {
            DamusColors.adaptableWhite
                .ignoresSafeArea()
        }
    }

    var body: some View {
        VStack {
            timelineBody
        }
        .overlay(alignment: .top) {
            HeaderView()
                .anchorPreference(key: HeaderBoundsKey.self, value: .bounds){$0}
                .overlayPreferenceValue(HeaderBoundsKey.self) { value in
                    GeometryReader{ proxy in
                        if let anchor = value{
                            Color.clear
                                .onAppear {
                                    headerHeight = proxy[anchor].height
                                }
                        }
                    }
                }
                .offset(y: -headerOffset < headerHeight ? headerOffset : (headerOffset < 0 ? headerOffset : 0))
                .opacity(1.0 - (abs(headerOffset/100.0)))
        }
    }
}

private extension PostingTimelineView {
    var timelineBody: some View {
        ZStack {
            TabView(selection: $filter_state) {
                contentTimelineView(filter: content_filter(.posts))
                    .tag(FilterState.posts)
                    .id(FilterState.posts)
                contentTimelineView(filter: content_filter(.posts_and_replies))
                    .tag(FilterState.posts_and_replies)
                    .id(FilterState.posts_and_replies)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            
            if damus_state.keypair.privkey != nil {
                PostButtonContainer(is_left_handed: damus_state.settings.left_handed) {
                    self.active_sheet = .post(.posting(.none))
                }
                .padding(.bottom, tabHeight + getSafeAreaBottom())
                .opacity(0.35 + abs(1.25 - (abs(headerOffset/100.0))))
            }
        }
    }
}

struct PostingTimelineView_Previews: PreviewProvider {
    static var previews: some View {
        PostingTimelineView(
            damus_state: test_damus_state,
            home: HomeModel(),
            homeEvents: .init(),
            isSideBarOpened: .constant(false),
            active_sheet: .constant(nil),
            headerOffset: .constant(0)
        )
    }
}

// MARK: - Vine feed components

struct VineTimelineView: View {
    let damus_state: DamusState
    @StateObject private var model: VineFeedModel
    
    init(damus_state: DamusState) {
        self.damus_state = damus_state
        _model = StateObject(wrappedValue: VineFeedModel(damus_state: damus_state))
    }
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                if let message = model.relayMessage {
                    infoBanner(text: message)
                }
                ForEach(Array(model.vines.enumerated()), id: \.1.id) { index, vine in
                    VineCard(vine: vine, damus_state: damus_state) {
                        model.noteAppeared(at: index)
                    }
                }
                if model.vines.isEmpty && !model.isLoading && model.relayMessage == nil {
                    Text("No Vine videos yet. Pull down to refresh.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 32)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .background(DamusColors.adaptableWhite)
        .refreshable { await model.refresh() }
        .overlay {
            if model.isLoading {
                ProgressView()
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(uiColor: .systemBackground)))
                    .shadow(radius: 4)
            }
        }
        .onAppear { model.subscribe() }
        .onDisappear { model.stop() }
        .onReceive(damus_state.settings.objectWillChange) { _ in
            model.handleSettingsChange()
        }
    }
    
    private func infoBanner(text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bolt.horizontal.circle")
                .foregroundColor(.purple)
            Text(text)
                .font(.footnote)
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
    }
}

private final class VineFeedModel: ObservableObject {
    @Published private(set) var vines: [VineVideo] = []
    @Published var isLoading: Bool = false
    @Published var relayMessage: String? = nil
    
    private let damus_state: DamusState
    private var streamTask: Task<Void, Never>?
    private var lastSeenTimestamp: UInt32?
    
    init(damus_state: DamusState) {
        self.damus_state = damus_state
    }
    
    func subscribe() {
        stop()
        streamTask = Task { await self.stream() }
    }
    
    func stop() {
        streamTask?.cancel()
        streamTask = nil
    }
    
    func refresh() async {
        await MainActor.run {
            vines.removeAll()
            lastSeenTimestamp = nil
        }
        subscribe()
    }
    
    func handleSettingsChange() {
        guard damus_state.settings.enable_vine_relay else {
            stop()
            Task { @MainActor in
                relayMessage = NSLocalizedString("Enable the Divine relay in Settings ▸ Relays to see Vine videos.", comment: "Message shown when the Vine relay is disabled.")
                vines.removeAll()
                isLoading = false
            }
            return
        }
        
        if streamTask == nil {
            subscribe()
        }
    }
    
    func noteAppeared(at index: Int) {
        let nextIndex = index + 1
        guard vines.indices.contains(nextIndex) else { return }
        guard let url = vines[nextIndex].playbackURL else { return }
        Task.detached(priority: .background) {
            _ = try? await URLSession.shared.data(from: url)
        }
    }
    
    private func stream() async {
        guard damus_state.settings.enable_vine_relay else {
            await MainActor.run {
                relayMessage = NSLocalizedString("Enable the Divine relay in Settings ▸ Relays to see Vine videos.", comment: "Message shown when the Vine relay is disabled.")
                isLoading = false
            }
            return
        }
        
        await damus_state.nostrNetwork.ensureRelayConnected(.vineRelay)
        
        await MainActor.run {
            relayMessage = nil
            isLoading = true
        }
        
        var filter = NostrFilter(kinds: [.vine_short])
        filter.limit = 200
        let now = UInt32(Date().timeIntervalSince1970)
        filter.until = now
        if let lastSeenTimestamp {
            filter.since = lastSeenTimestamp
        } else {
            filter.since = now > 604800 ? now - 604800 : 0
        }
        
        for await item in damus_state.nostrNetwork.reader.advancedStream(filters: [filter], to: [.vineRelay]) {
            if Task.isCancelled { break }
            switch item {
            case .event(let lender):
                await lender.justUseACopy({ await self.handle(event: $0) })
            case .ndbEose, .networkEose, .eose:
                await MainActor.run { self.isLoading = false }
            }
        }
        
        await MainActor.run {
            self.isLoading = false
        }
    }
    
    private func handle(event: NostrEvent) async {
        guard let video = VineVideo(event: event) else { return }
        let shouldInclude = await MainActor.run {
            should_show_event(state: damus_state, ev: event)
        }
        guard shouldInclude else { return }
        
        await MainActor.run {
            if let index = vines.firstIndex(where: { $0.dedupeKey == video.dedupeKey }) {
                if vines[index].createdAt >= video.createdAt {
                    return
                }
                vines[index] = video
            } else {
                vines.append(video)
            }
            vines.sort { $0.createdAt > $1.createdAt }
            lastSeenTimestamp = max(lastSeenTimestamp ?? 0, video.createdAt)
        }
    }
}

private struct VineVideo: Identifiable, Equatable {
    struct MediaCandidate {
        enum Kind {
            case mp4
            case mov
            case hls
            case dash
            case fallback
            case unknown
            
            var priority: Int {
                switch self {
                case .mp4, .mov:
                    return 0
                case .hls:
                    return 1
                case .dash, .fallback:
                    return 2
                case .unknown:
                    return 3
                }
            }
        }
        
        let url: URL
        let kind: Kind
    }
    
    let event: NostrEvent
    let dedupeKey: String
    let title: String
    let summary: String?
    let authorDisplay: String
    let createdAt: UInt32
    let hashtags: [String]
    let playbackURL: URL?
    let fallbackURL: URL?
    let thumbnailURL: URL?
    let blurhash: String?
    let contentWarning: String?
    let altText: String?
    let durationDescription: String?
    let dimensionDescription: String?
    let originDescription: String?
    let proofTags: [[String]]
    
    var id: String { event.id.hex() }
    
    init?(event: NostrEvent) {
        guard event.known_kind == .vine_short else { return nil }
        self.event = event
        
        let content = event.content.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = content.isEmpty ? nil : content
        self.hashtags = event.referenced_hashtags.map(\.hashtag)
        self.title = VineVideo.tagValue("title", in: event) ?? summary ?? NSLocalizedString("Untitled Vine", comment: "Fallback title when a Vine video is missing metadata.")
        self.contentWarning = VineVideo.tagValue("content-warning", in: event)
        self.altText = VineVideo.tagValue("alt", in: event)
        self.durationDescription = VineVideo.tagValue("duration", in: event)
        self.dimensionDescription = VineVideo.tagValue("dim", in: event)
        self.originDescription = VineVideo.originDescription(from: event)
        self.proofTags = VineVideo.proofTags(from: event)
        
        self.dedupeKey = VineVideo.tagValue("d", in: event) ?? event.id.hex()
        self.createdAt = event.created_at
        
        let npub = event.pubkey.npub
        if npub.count > 12 {
            self.authorDisplay = "\(npub.prefix(8))…\(npub.suffix(4))"
        } else {
            self.authorDisplay = npub
        }
        
        var candidates = [MediaCandidate]()
        VineVideo.collectDirectURLs(from: event, into: &candidates)
        VineVideo.collectIMetaURLs(from: event, into: &candidates)
        VineVideo.collectStreamingURLs(from: event, into: &candidates)
        
        let sorted = candidates.sorted { $0.kind.priority < $1.kind.priority }
        guard let primaryURL = sorted.first?.url else {
            return nil
        }
        
        self.playbackURL = primaryURL
        self.fallbackURL = sorted.dropFirst().first(where: { $0.kind == .hls })?.url
        self.thumbnailURL = VineVideo.thumbnailURL(from: event)
        self.blurhash = VineVideo.blurhash(from: event)
    }
    
    var requiresBlur: Bool {
        contentWarning != nil
    }
    
    private static func collectDirectURLs(from event: NostrEvent, into candidates: inout [MediaCandidate]) {
        for tag in event.tags {
            let values = tag.strings()
            guard values.first == "url", values.count > 1,
                  let url = normalizedURL(values[1]) else { continue }
            candidates.append(MediaCandidate(url: url, kind: mediaKind(for: url)))
        }
    }
    
    private static func collectIMetaURLs(from event: NostrEvent, into candidates: inout [MediaCandidate]) {
        for tag in event.tags {
            let values = tag.strings()
            guard values.first == "imeta" else { continue }
            for entry in values.dropFirst() {
                let pieces = entry.split(separator: " ", maxSplits: 1)
                guard pieces.count == 2,
                      let url = normalizedURL(String(pieces[1])) else { continue }
                let key = pieces[0]
                let kind = mediaKind(forMetaKey: String(key), url: url)
                candidates.append(MediaCandidate(url: url, kind: kind))
            }
        }
    }
    
    private static func collectStreamingURLs(from event: NostrEvent, into candidates: inout [MediaCandidate]) {
        for tag in event.tags {
            let values = tag.strings()
            guard values.first == "streaming", values.count >= 2,
                  let url = normalizedURL(values[1]) else { continue }
            candidates.append(MediaCandidate(url: url, kind: .hls))
        }
    }
    
    private static func mediaKind(for url: URL) -> MediaCandidate.Kind {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp4":
            return .mp4
        case "mov":
            return .mov
        case "m3u8":
            return .hls
        case "mpd":
            return .dash
        default:
            return .unknown
        }
    }
    
    private static func mediaKind(forMetaKey key: String, url: URL) -> MediaCandidate.Kind {
        switch key {
        case "url", "mp4", "video":
            return mediaKind(for: url)
        case "hls", "stream":
            return .hls
        case "dash":
            return .dash
        case "fallback":
            return .fallback
        default:
            return mediaKind(for: url)
        }
    }
    
    private static func normalizedURL(_ raw: String) -> URL? {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "apt.openvine.co", with: "api.openvine.co")
        guard let url = URL(string: cleaned),
              let scheme = url.scheme,
              scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }
    
    private static func thumbnailURL(from event: NostrEvent) -> URL? {
        if let direct = tagValue("thumb", in: event), let url = normalizedURL(direct) {
            return url
        }
        for tag in event.tags {
            let values = tag.strings()
            guard values.first == "imeta" else { continue }
            for entry in values.dropFirst() {
                let parts = entry.split(separator: " ", maxSplits: 1)
                guard parts.count == 2 else { continue }
                let key = parts[0]
                if key == "image" || key == "thumb", let url = normalizedURL(String(parts[1])) {
                    return url
                }
            }
        }
        return nil
    }
    
    private static func blurhash(from event: NostrEvent) -> String? {
        for tag in event.tags {
            let values = tag.strings()
            guard values.first == "imeta" else { continue }
            for entry in values.dropFirst() {
                let parts = entry.split(separator: " ", maxSplits: 1)
                guard parts.count == 2, parts[0] == "blurhash" else { continue }
                return String(parts[1])
            }
        }
        return nil
    }
    
    private static func originDescription(from event: NostrEvent) -> String? {
        for tag in event.tags {
            let values = tag.strings()
            guard values.first == "origin", values.count >= 3 else { continue }
            return "\(values[1]) • \(values[2])"
        }
        return nil
    }
    
    private static func proofTags(from event: NostrEvent) -> [[String]] {
        event.tags.strings().filter { tag in
            guard let key = tag.first else { return false }
            return key == "proof" || key == "pm-report"
        }
    }
    
    private static func tagValue(_ key: String, in event: NostrEvent) -> String? {
        for tag in event.tags {
            let values = tag.strings()
            guard values.first == key else { continue }
            return values.count > 1 ? values[1] : nil
        }
        return nil
    }
}

private struct VineCard: View {
    let vine: VineVideo
    let damus_state: DamusState
    let onAppear: () -> Void
    @State private var isSensitiveRevealed = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            videoBody
            metadataRows
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color(uiColor: .secondarySystemBackground))
        )
        .onAppear(perform: onAppear)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(vine.altText ?? vine.title))
    }
    
    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(vine.title)
                .font(.headline)
            Text("\(vine.authorDisplay) • \(relativeDate)")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
    }
    
    private var videoBody: some View {
        ZStack {
            if let url = vine.playbackURL {
                DamusVideoPlayerView(url: url, coordinator: damus_state.video, style: .preview(on_tap: nil))
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                Color.gray.opacity(0.2)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            
            if shouldBlurContent {
                Color.black.opacity(0.5)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                VStack {
                    Image(systemName: "eye.slash")
                        .font(.title2)
                        .foregroundColor(.white)
                    if let warning = vine.contentWarning {
                        Text(warning)
                            .font(.caption)
                            .foregroundColor(.white)
                            .padding(.top, 2)
                    }
                    Button(NSLocalizedString("Reveal", comment: "Button to reveal sensitive Vine content.")) {
                        isSensitiveRevealed = true
                    }
                    .padding(.top, 8)
                    .buttonStyle(.borderedProminent)
                }
            }
        }
    }
    
    private var metadataRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let summary = vine.summary {
                Text(summary)
                    .font(.body)
            }
            
            if !vine.hashtags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack {
                        ForEach(vine.hashtags, id: \.self) { hashtag in
                            Text("#\(hashtag)")
                                .font(.caption)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(DamusColors.purple.opacity(0.15))
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            
            if let origin = vine.originDescription {
                VineMetadataRow(icon: "globe", text: origin)
            }
            
            if let duration = vine.durationDescription {
                VineMetadataRow(icon: "clock", text: duration)
            }
            
            if let dim = vine.dimensionDescription {
                VineMetadataRow(icon: "aspectratio", text: dim)
            }
            
            if !vine.proofTags.isEmpty {
                VineMetadataRow(icon: "checkmark.seal", text: NSLocalizedString("ProofMode metadata attached", comment: "Label shown when a Vine video has proof tags attached."))
            }
        }
    }
    
    private var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let date = Date(timeIntervalSince1970: TimeInterval(vine.createdAt))
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    private var shouldBlurContent: Bool {
        guard let _ = vine.contentWarning else { return false }
        return damus_state.settings.hide_nsfw_tagged_content && !isSensitiveRevealed
    }
}

private struct VineMetadataRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
        }
    }
}
