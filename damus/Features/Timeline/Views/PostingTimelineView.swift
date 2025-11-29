//
//  PostingTimelineView.swift
//  damus
//
//  Created by eric on 7/15/24.
//

import SwiftUI
import Network

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
        
        switch sourceToUse {
        case .follows:
            filters.append(damus_state.contacts.friend_filter)
        case .favorites:
            filters.append(damus_state.contactCards.filter)
        }
        return ContentFilters(filters: filters).filter
    }
    
    func contentTimelineView(filter: (@escaping (NostrEvent) -> Bool)) -> some View {
        TimelineView<AnyView>(events: home.events, loading: self.loading, headerHeight: $headerHeight, headerOffset: $headerOffset, damus: damus_state, show_friend_icon: false, filter: filter)
    }
    
    func HeaderView() -> some View {
        VStack {
            VStack(spacing: 0) {
                // This is needed for the Dynamic Island
                HStack {}
                .frame(height: getSafeAreaTop())

                HStack(alignment: .top) {
                    TopbarSideMenuButton(damus_state: damus_state, isSideBarOpened: $isSideBarOpened)

                    Spacer()

                    HStack(alignment: .center) {
                        SignalView(state: damus_state, signal: home.signal)
                        if damus_state.settings.enable_favourites_feature {
                            let switchView = PostingTimelineSwitcherView(
                                damusState: damus_state,
                                timelineSource: $timeline_source
                            )
                            if #available(iOS 17.0, *) {
                                switchView
                                    .popoverTip(PostingTimelineSwitcherView.TimelineSwitcherTip.shared)
                            } else {
                                switchView
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .overlay {
                    Image("damus-home")
                        .resizable()
                        .frame(width:30,height:30)
                        .shadow(color: DamusColors.purple, radius: 2)
                        .opacity(isSideBarOpened ? 0 : 1)
                        .animation(isSideBarOpened ? .none : .default, value: isSideBarOpened)
                        .onTapGesture {
                            isSideBarOpened.toggle()
                        }
                }
            }
            .padding(.horizontal, 20)
            
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
    @State private var presentingFullScreen = false
    @State private var fullScreenIndex = 0
    
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
                    VineCard(
                        vine: vine,
                        damus_state: damus_state,
                        onAppear: { model.noteAppeared(at: index) },
                        onOpenFullScreen: {
                            fullScreenIndex = index
                            presentingFullScreen = true
                        }
                    )
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
        .onDisappear { model.stop(disconnect: true) }
        .onReceive(damus_state.settings.objectWillChange) { _ in
            model.handleSettingsChange()
        }
        .damus_full_screen_cover($presentingFullScreen, damus_state: damus_state) {
            VineFullScreenPager(
                model: model,
                damus_state: damus_state,
                initialIndex: fullScreenIndex,
                onClose: { presentingFullScreen = false }
            )
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
    
    private let pageSize = 40
    private let damus_state: DamusState
    private var streamTask: Task<Void, Never>?
    private var lastSeenTimestamp: UInt32?
    private var managedRelayConnection = false
    private let pathMonitor = NWPathMonitor()
    private let pathQueue = DispatchQueue(label: "io.damus.vines.network")
    @MainActor private var pathIsExpensive = false
    @MainActor private var pathIsConstrained = false
    @MainActor private var prefetchingURLs: Set<URL> = []
    @MainActor private var oldestTimestamp: UInt32?
    @MainActor private var isLoadingOlder = false
    @MainActor private var hasMoreOlder = true
    
    init(damus_state: DamusState) {
        self.damus_state = damus_state
        pathMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.pathIsExpensive = path.isExpensive
                self?.pathIsConstrained = path.isConstrained
            }
        }
        pathMonitor.start(queue: pathQueue)
    }
    
    func subscribe() {
        stop()
        streamTask = Task {
            await self.loadInitialPage()
            await self.stream()
        }
    }
    
    func stop(disconnect: Bool = false) {
        streamTask?.cancel()
        streamTask = nil
        if disconnect {
            Task {
                await self.disconnectManagedRelayIfNeeded()
            }
        }
    }
    
    func refresh() async {
        await MainActor.run {
            vines.removeAll()
            lastSeenTimestamp = nil
            oldestTimestamp = nil
            hasMoreOlder = true
        }
        subscribe()
    }
    
    func handleSettingsChange() {
        guard damus_state.settings.enable_vine_relay else {
            stop(disconnect: true)
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
    
    @MainActor
    func noteAppeared(at index: Int) {
        maybeLoadOlder(after: index)
        guard shouldPrefetchVideos else { return }
        let targets = [index, index + 1]
        let allowCellular = damus_state.settings.prefetch_vines_on_cellular
        Task.detached(priority: .background) { [weak self] in
            guard let self else { return }
            for target in targets {
                guard self.vines.indices.contains(target),
                      let url = self.vines[target].playbackURL else { continue }
                await self.prefetch(url: url, allowCellular: allowCellular)
            }
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
        
        let alreadyConnected = await MainActor.run {
            damus_state.nostrNetwork.getRelay(.vineRelay) != nil
        }
        await damus_state.nostrNetwork.ensureRelayConnected(.vineRelay)
        if !alreadyConnected {
            await MainActor.run {
                self.managedRelayConnection = true
            }
        }
        
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
        let canonical = canonicalEvent(for: event)
        guard let video = VineVideo(event: canonical.base, repostSource: canonical.repost) else {
            Log.debug("Skipping Vine event %s (failed to parse)", for: .timeline, canonical.base.id.hex())
            return
        }
        let shouldInclude = await MainActor.run {
            should_show_event(state: damus_state, ev: canonical.base)
        }
        guard shouldInclude else {
            Log.debug("Filtered Vine event %s via should_show_event", for: .timeline, canonical.base.id.hex())
            return
        }
        
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
    
    private func canonicalEvent(for event: NostrEvent) -> (base: NostrEvent, repost: NostrEvent?) {
        guard event.known_kind == .boost else {
            return (event, nil)
        }
        
        if let inner = event.get_inner_event(cache: damus_state.events),
           inner.known_kind == .vine_short {
            return (inner, event)
        }
        return (event, nil)
    }
    
    private func disconnectManagedRelayIfNeeded() async {
        let shouldDisconnect = await MainActor.run { self.managedRelayConnection }
        guard shouldDisconnect else { return }
        await damus_state.nostrNetwork.disconnectRelay(.vineRelay)
        await MainActor.run { self.managedRelayConnection = false }
    }
    
    private func loadInitialPage() async {
        let start = CFAbsoluteTimeGetCurrent()
        await MainActor.run {
            isLoading = true
            vines.removeAll()
        }
        let events = await fetchPage(before: nil)
        await MainActor.run {
            applyPage(events, reset: true)
            isLoading = false
            Log.info("Vines initial page loaded %d events in %.2fs", for: .timeline, events.count, CFAbsoluteTimeGetCurrent() - start)
        }
    }
    
    private func loadOlderPage() async {
        let before = await MainActor.run { self.oldestTimestamp }
        guard let before else { return }
        let start = CFAbsoluteTimeGetCurrent()
        let events = await fetchPage(before: before > 0 ? before - 1 : 0)
        if events.isEmpty {
            await MainActor.run {
                self.hasMoreOlder = false
                self.isLoadingOlder = false
                Log.debug("Vines older page empty at timestamp %u", for: .timeline, before)
            }
            return
        }
        await MainActor.run {
            applyPage(events, reset: false)
            Log.info("Vines older page loaded %d events in %.2fs", for: .timeline, events.count, CFAbsoluteTimeGetCurrent() - start)
        }
    }
    
    private func fetchPage(before: UInt32?) async -> [NostrEvent] {
        var filter = NostrFilter(kinds: [.vine_short])
        filter.limit = UInt32(pageSize)
        let now = UInt32(Date().timeIntervalSince1970)
        filter.until = before ?? now
        return await damus_state.nostrNetwork.reader.query(filters: [filter], to: [.vineRelay], timeout: .seconds(10))
    }
    
    @MainActor
    private func applyPage(_ events: [NostrEvent], reset: Bool) {
        var videos = events.compactMap { VineVideo(event: $0) }
        videos.sort { $0.createdAt > $1.createdAt }
        if reset {
            vines = videos
        } else {
            let newVideos = videos.filter { video in
                !vines.contains(where: { $0.dedupeKey == video.dedupeKey })
            }
            vines.append(contentsOf: newVideos)
            vines.sort { $0.createdAt > $1.createdAt }
            if newVideos.isEmpty {
                hasMoreOlder = false
            }
            Log.debug("Vines older page appended %d new events (filtered %d duplicates)", for: .timeline, newVideos.count, videos.count - newVideos.count)
        }
        if let newest = vines.first?.createdAt {
            lastSeenTimestamp = max(lastSeenTimestamp ?? 0, newest)
        }
        if let oldest = vines.last?.createdAt {
            oldestTimestamp = oldest
        }
        if hasMoreOlder {
            hasMoreOlder = videos.count == pageSize
        }
        isLoadingOlder = false
    }
    
    @MainActor
    private var shouldPrefetchVideos: Bool {
        if pathIsConstrained {
            return false
        }
        if pathIsExpensive && !damus_state.settings.prefetch_vines_on_cellular {
            return false
        }
        return true
    }
    
    @MainActor
    private func prefetch(url: URL, allowCellular: Bool) async {
        guard markPrefetching(url) else { return }
        var request = URLRequest(url: url)
        request.allowsExpensiveNetworkAccess = allowCellular
        request.allowsConstrainedNetworkAccess = allowCellular
        request.timeoutInterval = 15
        do {
            _ = try await URLSession.shared.data(for: request)
        } catch {
            Log.debug("Vine prefetch failed for %s: %s", for: .timeline, url.absoluteString, error.localizedDescription)
        }
        unmarkPrefetching(url)
    }
    
    @MainActor
    private func markPrefetching(_ url: URL) -> Bool {
        if prefetchingURLs.contains(url) {
            return false
        }
        prefetchingURLs.insert(url)
        return true
    }
    
    @MainActor
    private func unmarkPrefetching(_ url: URL) {
        prefetchingURLs.remove(url)
    }
    
    @MainActor
    private func maybeLoadOlder(after index: Int) {
        guard hasMoreOlder, !isLoadingOlder else { return }
        if index >= vines.count - 5 {
            isLoadingOlder = true
            Task {
                await self.loadOlderPage()
            }
        }
    }
    
    deinit {
        pathMonitor.cancel()
    }
}

struct VineVideo: Identifiable, Equatable {
    struct MediaCandidate: Hashable {
        enum Kind: Hashable {
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
        
        enum Source: Hashable {
            case direct
            case imeta(String)
            case streaming(String?)
            case reference(String?)
            case content
            case fallback
            
            var priority: Int {
                switch self {
                case .direct, .imeta:
                    return 0
                case .reference:
                    return 1
                case .streaming:
                    return 2
                case .content:
                    return 3
                case .fallback:
                    return 4
                }
            }
        }
        
        let url: URL
        let kind: Kind
        let source: Source
        
        var priority: Int {
            (source.priority * 10) + kind.priority
        }
    }
    
    struct VineOrigin: Equatable {
        let source: String
        let identifier: String?
        let detail: String?
        
        var displayText: String {
            if let identifier, let detail {
                return "\(source) • \(identifier) – \(detail)"
            } else if let identifier {
                return "\(source) • \(identifier)"
            } else if let detail {
                return "\(source) – \(detail)"
            } else {
                return source
            }
        }
    }
    
    struct VineProof: Equatable {
        let key: String
        let values: [String]
    }
    
    private struct IMetaEntry {
        let key: String
        let value: String
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
    let origin: VineOrigin?
    let proofTags: [VineProof]
    let expirationTimestamp: UInt32?
    let loopCount: Int?
    let likeCount: Int?
    let commentCount: Int?
    let repostCount: Int?
    let publishedAt: String?
    let repostedBy: String?
    let repostedAt: UInt32?
    
    var id: String { event.id.hex() }
    var originDescription: String? { origin?.displayText }
    
    init?(event: NostrEvent, repostSource: NostrEvent? = nil) {
        guard event.known_kind == .vine_short else { return nil }
        self.event = event
        
        let content = event.content.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = content.isEmpty ? nil : content
        self.hashtags = event.referenced_hashtags.map(\.hashtag)
        let imetaEntries = VineVideo.imetaEntries(in: event)
        self.title = VineVideo.tagValue("title", in: event) ?? summary ?? NSLocalizedString("Untitled Vine", comment: "Fallback title when a Vine video is missing metadata.")
        self.contentWarning = VineVideo.contentWarning(from: event, imetaEntries: imetaEntries)
        self.altText = VineVideo.altText(from: event, imetaEntries: imetaEntries)
        self.durationDescription = VineVideo.duration(from: event, imetaEntries: imetaEntries)
        self.dimensionDescription = VineVideo.dimension(from: event, imetaEntries: imetaEntries)
        self.origin = VineVideo.origin(from: event)
        self.proofTags = VineVideo.proofTags(from: event)
        self.expirationTimestamp = VineVideo.expirationTimestamp(from: event)
        self.loopCount = VineVideo.intTagValue("loops", in: event)
        self.likeCount = VineVideo.intTagValue("likes", in: event)
        self.commentCount = VineVideo.intTagValue("comments", in: event)
        self.repostCount = VineVideo.intTagValue("reposts", in: event)
        self.publishedAt = VineVideo.tagValue("published_at", in: event)
        if let repost = repostSource {
            let npub = repost.pubkey.npub
            if npub.count > 12 {
                self.repostedBy = "\(npub.prefix(8))…\(npub.suffix(4))"
            } else {
                self.repostedBy = npub
            }
            self.repostedAt = repost.created_at
        } else {
            self.repostedBy = nil
            self.repostedAt = nil
        }
        
        self.dedupeKey = VineVideo.tagValue("d", in: event) ?? event.id.hex()
        self.createdAt = event.created_at
        
        let npub = event.pubkey.npub
        if npub.count > 12 {
            self.authorDisplay = "\(npub.prefix(8))…\(npub.suffix(4))"
        } else {
            self.authorDisplay = npub
        }
        
        var candidateMap: [URL: MediaCandidate] = [:]
        VineVideo.collectDirectURLs(from: event, into: &candidateMap)
        VineVideo.collectIMetaURLs(from: imetaEntries, into: &candidateMap)
        VineVideo.collectStreamingURLs(from: event, into: &candidateMap)
        VineVideo.collectReferenceURLs(from: event, into: &candidateMap)
        VineVideo.collectContentURLs(from: content, into: &candidateMap)
        if candidateMap.isEmpty {
            VineVideo.collectFallbackURLs(from: event, into: &candidateMap)
        }
        
        let sorted = candidateMap.values.sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.url.absoluteString < rhs.url.absoluteString
            }
            return lhs.priority < rhs.priority
        }
        guard let primaryURL = sorted.first?.url else {
            Log.debug("VineVideo missing playable URL for event %s", for: .timeline, event.id.hex())
            return nil
        }
        
        self.playbackURL = primaryURL
        self.fallbackURL = sorted.dropFirst().first(where: { $0.kind == .hls || $0.kind == .dash })?.url
        self.thumbnailURL = VineVideo.thumbnailURL(from: event, imetaEntries: imetaEntries)
        self.blurhash = VineVideo.blurhash(from: event, imetaEntries: imetaEntries)
    }
    
    var requiresBlur: Bool {
        contentWarning != nil
    }
    
    private static func collectDirectURLs(from event: NostrEvent, into candidates: inout [URL: MediaCandidate]) {
        for tag in event.tags {
            let values = tag.strings()
            guard values.first == "url", values.count > 1,
                  let url = normalizedURL(values[1]) else { continue }
            addCandidate(url, kind: mediaKind(for: url), source: .direct, into: &candidates)
        }
    }
    
    private static func collectIMetaURLs(from entries: [IMetaEntry], into candidates: inout [URL: MediaCandidate]) {
        for entry in entries {
            switch entry.key {
            case "url", "video", "mp4":
                guard let url = normalizedURL(entry.value) else { continue }
                addCandidate(url, kind: mediaKind(forMetaKey: entry.key, url: url), source: .imeta(entry.key), into: &candidates)
            case "fallback":
                guard let url = normalizedURL(entry.value) else { continue }
                addCandidate(url, kind: .fallback, source: .imeta(entry.key), into: &candidates)
            case "hls", "stream", "streaming":
                guard let url = normalizedURL(entry.value) else { continue }
                addCandidate(url, kind: .hls, source: .imeta(entry.key), into: &candidates)
            case "dash":
                guard let url = normalizedURL(entry.value) else { continue }
                addCandidate(url, kind: .dash, source: .imeta(entry.key), into: &candidates)
            default:
                continue
            }
        }
    }
    
    private static func collectStreamingURLs(from event: NostrEvent, into candidates: inout [URL: MediaCandidate]) {
        for tag in event.tags {
            let values = tag.strings()
            guard values.first == "streaming", values.count >= 2,
                  let url = normalizedURL(values[1]) else { continue }
            let format = values.count >= 3 ? values[2] : nil
            let kind: MediaCandidate.Kind = mediaKind(for: url)
            addCandidate(url, kind: kind, source: .streaming(format), into: &candidates)
        }
    }
    
    private static func collectReferenceURLs(from event: NostrEvent, into candidates: inout [URL: MediaCandidate]) {
        for tag in event.tags {
            let values = tag.strings()
            guard let first = values.first else { continue }
            switch first {
            case "r":
                guard values.count > 1,
                      let url = normalizedURL(values[1]) else { continue }
                let type = values.count > 2 ? values[2] : nil
                if let type, type == "thumbnail" {
                    continue
                }
                addCandidate(url, kind: mediaKind(for: url), source: .reference(type), into: &candidates)
            case "e", "i":
                guard values.count > 1,
                      let url = normalizedURL(values[1]) else { continue }
                addCandidate(url, kind: mediaKind(for: url), source: .reference(first), into: &candidates)
            default:
                continue
            }
        }
    }
    
    private static func collectContentURLs(from content: String?, into candidates: inout [URL: MediaCandidate]) {
        guard let content, !content.isEmpty else { return }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = detector.matches(in: content, options: [], range: range)
        for match in matches {
            guard let matchRange = Range(match.range, in: content) else { continue }
            let urlString = String(content[matchRange])
            guard let url = normalizedURL(urlString) else { continue }
            addCandidate(url, kind: mediaKind(for: url), source: .content, into: &candidates)
        }
    }
    
    private static func collectFallbackURLs(from event: NostrEvent, into candidates: inout [URL: MediaCandidate]) {
        for tag in event.tags {
            let values = tag.strings().dropFirst()
            for value in values {
                guard let url = normalizedURL(value) else { continue }
                addCandidate(url, kind: mediaKind(for: url), source: .fallback, into: &candidates)
            }
        }
    }
    
    private static func addCandidate(_ url: URL, kind: MediaCandidate.Kind, source: MediaCandidate.Source, into candidates: inout [URL: MediaCandidate]) {
        let candidate = MediaCandidate(url: url, kind: kind, source: source)
        if let existing = candidates[url], existing.priority <= candidate.priority {
            return
        }
        candidates[url] = candidate
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
    
    private static func thumbnailURL(from event: NostrEvent, imetaEntries: [IMetaEntry]) -> URL? {
        if let direct = tagValue("thumb", in: event), let url = normalizedURL(direct) {
            return url
        }
        if let image = tagValue("image", in: event), let url = normalizedURL(image) {
            return url
        }
        if let imetaImage = imetaEntries.first(where: { $0.key == "image" || $0.key == "thumb" }), let url = normalizedURL(imetaImage.value) {
            return url
        }
        for tag in event.tags {
            let values = tag.strings()
            guard values.first == "r", values.count > 2 else { continue }
            guard values[2] == "thumbnail", let url = normalizedURL(values[1]) else { continue }
            return url
        }
        return nil
    }
    
    private static func blurhash(from event: NostrEvent, imetaEntries: [IMetaEntry]) -> String? {
        if let tagValue = tagValue("blurhash", in: event) {
            return tagValue
        }
        return imetaEntries.first(where: { $0.key == "blurhash" })?.value
    }
    
    private static func contentWarning(from event: NostrEvent, imetaEntries: [IMetaEntry]) -> String? {
        if let tagValue = tagValue("content-warning", in: event) ?? tagValue("cw", in: event) {
            return tagValue
        }
        return imetaEntries.first(where: { $0.key == "content-warning" || $0.key == "cw" })?.value
    }
    
    private static func altText(from event: NostrEvent, imetaEntries: [IMetaEntry]) -> String? {
        if let tagValue = tagValue("alt", in: event) {
            return tagValue
        }
        return imetaEntries.first(where: { $0.key == "alt" })?.value
    }
    
    private static func duration(from event: NostrEvent, imetaEntries: [IMetaEntry]) -> String? {
        if let tagValue = tagValue("duration", in: event) {
            return tagValue
        }
        return imetaEntries.first(where: { $0.key == "duration" })?.value
    }
    
    private static func dimension(from event: NostrEvent, imetaEntries: [IMetaEntry]) -> String? {
        if let tagValue = tagValue("dim", in: event) {
            return tagValue
        }
        return imetaEntries.first(where: { $0.key == "dim" })?.value
    }
    
    private static func origin(from event: NostrEvent) -> VineOrigin? {
        for tag in event.tags {
            let values = tag.strings()
            guard values.first == "origin" else { continue }
            let source = values.indices.contains(1) ? values[1] : "origin"
            let identifier = values.indices.contains(2) ? values[2] : nil
            let detail = values.indices.contains(3) ? values[3] : nil
            return VineOrigin(source: source, identifier: identifier, detail: detail)
        }
        return nil
    }
    
    private static func proofTags(from event: NostrEvent) -> [VineProof] {
        event.tags.strings().compactMap { tag in
            guard let key = tag.first else { return nil }
            if key == "proof" || key.hasPrefix("pm-") || key == "pm-report" {
                return VineProof(key: key, values: Array(tag.dropFirst()))
            }
            return nil
        }
    }
    
    private static func expirationTimestamp(from event: NostrEvent) -> UInt32? {
        guard let value = tagValue("expiration", in: event) ?? tagValue("expires_at", in: event),
              let intVal = UInt32(value) else { return nil }
        return intVal
    }
    
    private static func intTagValue(_ key: String, in event: NostrEvent) -> Int? {
        guard let value = tagValue(key, in: event) else { return nil }
        return Int(value)
    }
    
    private static func tagValue(_ key: String, in event: NostrEvent) -> String? {
        for tag in event.tags {
            let values = tag.strings()
            guard values.first == key else { continue }
            return values.count > 1 ? values[1] : nil
        }
        return nil
    }
    
    private static func imetaEntries(in event: NostrEvent) -> [IMetaEntry] {
        var entries: [IMetaEntry] = []
        for tag in event.tags {
            let values = tag.strings()
            guard values.first == "imeta" else { continue }
            let payload = Array(values.dropFirst())
            let usesInlineFormat = payload.contains(where: { $0.contains(" ") })
            if usesInlineFormat {
                for element in payload {
                    let parts = element.split(separator: " ", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    entries.append(IMetaEntry(key: String(parts[0]), value: String(parts[1])))
                }
            } else {
                var iterator = payload.makeIterator()
                while let key = iterator.next(), let value = iterator.next() {
                    entries.append(IMetaEntry(key: key, value: value))
                }
            }
        }
        return entries
    }
}

private struct VineCard: View {
    let vine: VineVideo
    let damus_state: DamusState
    let onAppear: () -> Void
    let onOpenFullScreen: () -> Void
    @State private var isSensitiveRevealed = false
    @Environment(\.openURL) private var openURL
    
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
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(vine.title)
                    .font(.headline)
                Text("\(authorDisplayName) • \(relativeDate)")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                if let repostedBy = vine.repostedBy {
                    Text(String(format: NSLocalizedString("Reposted by %@", comment: "Label showing the author who reposted a Vine video."), repostedBy))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            Menu {
                Button {
                    reportVine()
                } label: {
                    Label(NSLocalizedString("Report Vine", comment: "Menu action to report a Vine video."), systemImage: "flag")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    private var videoBody: some View {
        ZStack {
            if let url = vine.playbackURL {
                DamusVideoPlayerView(url: url, coordinator: damus_state.video, style: .preview(on_tap: onOpenFullScreen))
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            } else {
                Color.gray.opacity(0.2)
                    .frame(height: 320)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                Text(NSLocalizedString("Video unavailable", comment: "Fallback text when a Vine video cannot be loaded."))
                    .font(.caption)
                    .foregroundColor(.secondary)
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
        .overlay(alignment: .topLeading) {
            if let warning = vine.contentWarning, !shouldBlurContent {
                Label(warning, systemImage: "eye.trianglebadge.exclamationmark")
                    .font(.caption2.weight(.semibold))
                    .padding(8)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(10)
            }
        }
    }
    
    private var metadataRows: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let summary = vine.summary {
                Text(summary)
                    .font(.body)
            }
            
            if let alt = vine.altText {
                Text(alt)
                    .font(.footnote)
                    .foregroundColor(.secondary)
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
            
            if let loops = vine.loopCount {
                VineMetadataRow(icon: "repeat", text: String(format: NSLocalizedString("%@ loops", comment: "Formatted loop count for a Vine video."), formatCount(loops)))
            }
            
            if let likes = vine.likeCount {
                VineMetadataRow(icon: "hand.thumbsup", text: String(format: NSLocalizedString("%@ likes", comment: "Formatted like count for a Vine video."), formatCount(likes)))
            }
            
            if !vine.proofTags.isEmpty {
                VineMetadataRow(icon: "checkmark.seal", text: NSLocalizedString("ProofMode metadata attached", comment: "Label shown when a Vine video has proof tags attached."))
            }
            
            if let fallback = vine.fallbackURL {
                Button {
                    openURL(fallback)
                } label: {
                    Label(NSLocalizedString("Open backup stream", comment: "Action to open a fallback Vine video URL when the main stream fails."), systemImage: "arrow.up.right.square")
                        .font(.caption)
                }
                .buttonStyle(.plain)
            }
            
            Divider()
                .padding(.vertical, 4)
            
            EventActionBar(damus_state: damus_state, event: vine.event, options: [.no_spread])
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
    
    private var authorDisplayName: String {
        if let profileTxn = damus_state.profiles.lookup(id: vine.event.pubkey, txn_name: "vine-card-name") {
            let profile = profileTxn.unsafeUnownedValue
            return Profile.displayName(profile: profile, pubkey: vine.event.pubkey).displayName
        }
        return vine.authorDisplay
    }
    
    private func formatCount(_ value: Int) -> String {
        let number = Double(value)
        let thousand = number / 1_000
        let million = number / 1_000_000
        if million >= 1.0 {
            return String(format: "%.1fM", million)
        } else if thousand >= 1.0 {
            return String(format: "%.1fK", thousand)
        } else {
            return "\(value)"
        }
    }
    
    private func reportVine() {
        let target = ReportNoteTarget(pubkey: vine.event.pubkey, note_id: vine.event.id)
        notify(.report(.note(target)))
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

private struct VineFullScreenPager: View {
    @ObservedObject var model: VineFeedModel
    let damus_state: DamusState
    let onClose: () -> Void
    @State private var selection: Int
    
    init(model: VineFeedModel, damus_state: DamusState, initialIndex: Int, onClose: @escaping () -> Void) {
        self._model = ObservedObject(wrappedValue: model)
        self.damus_state = damus_state
        self._selection = State(initialValue: initialIndex)
        self.onClose = onClose
    }
    
    var body: some View {
        GeometryReader { geo in
            TabView(selection: $selection) {
                ForEach(Array(model.vines.enumerated()), id: \.1.id) { index, vine in
                    VineFullScreenPage(vine: vine, damus_state: damus_state)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .rotationEffect(.degrees(-90))
                        .tag(index)
                }
            }
            .frame(width: geo.size.height, height: geo.size.width)
            .rotationEffect(.degrees(90))
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(x: (geo.size.width - geo.size.height) / 2, y: (geo.size.height - geo.size.width) / 2)
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.view_layer_context, .full_screen_layer)
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .padding()
            }
            .accessibilityLabel(Text(NSLocalizedString("Close", comment: "Close button label for Vine full-screen player.")))
        }
        .onAppear {
            model.noteAppeared(at: selection)
        }
        .onChange(of: selection) { idx in
            model.noteAppeared(at: idx)
        }
    }
}

private struct VineFullScreenPage: View {
    let vine: VineVideo
    let damus_state: DamusState
    @Environment(\.openURL) private var openURL
    
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let url = vine.playbackURL ?? vine.fallbackURL {
                DamusVideoPlayerView(url: url, coordinator: damus_state.video, style: .full)
                    .ignoresSafeArea()
            } else {
                Color.black
                Text(NSLocalizedString("Video unavailable", comment: "Fallback text when a Vine video cannot be loaded."))
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding()
            }
            
            VStack(alignment: .leading, spacing: 10) {
                Text(vine.title)
                    .font(.title2.bold())
                    .foregroundColor(.white)
                Text("\(authorLine) • \(relativeDate)")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.8))
                
                if let summary = vine.summary {
                    Text(summary)
                        .font(.body)
                        .foregroundColor(.white)
                        .padding(.top, 4)
                }
                
                if let fallback = vine.fallbackURL {
                    Button {
                        openURL(fallback)
                    } label: {
                        Label(NSLocalizedString("Open backup stream", comment: "Action to open a fallback Vine video URL when the main stream fails."), systemImage: "arrow.up.right.square")
                            .font(.caption)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.2))
                }
                
                EventActionBar(damus_state: damus_state, event: vine.event, options: [.no_spread])
                    .tint(.white)
            }
            .padding()
            .background(
                LinearGradient(
                    colors: [Color.black.opacity(0.8), Color.black.opacity(0)],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
        }
        .background(Color.black)
        .ignoresSafeArea()
    }
    
    private var authorLine: String {
        if let profileTxn = damus_state.profiles.lookup(id: vine.event.pubkey, txn_name: "vine-fullscreen-name"),
           let profile = profileTxn.unsafeUnownedValue {
            return Profile.displayName(profile: profile, pubkey: vine.event.pubkey).displayName
        }
        return vine.authorDisplay
    }
    
    private var relativeDate: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let date = Date(timeIntervalSince1970: TimeInterval(vine.createdAt))
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
