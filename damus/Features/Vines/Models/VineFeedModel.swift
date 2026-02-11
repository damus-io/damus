//
//  VineFeedModel.swift
//  damus
//
//  Extracted from PostingTimelineView.swift on 2026-02-10.
//

import SwiftUI
import Combine
import Network

/// Manages the Vine short-video feed: subscribes to the Divine relay, paginates
/// historical events, deduplicates replaceable events, and prefetches upcoming
/// video data for smooth playback.
public final class VineFeedModel: ObservableObject {
    @Published private(set) var vines: [VineVideo] = []
    @Published var isLoading: Bool = false
    @Published var relayMessage: String? = nil

    private let pageSize = 40
    private let damus_state: DamusState
    private var streamTask: Task<Void, Never>?
    private var prefetchTasks: [Task<Void, Never>] = []
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

    /// Starts streaming Vine events from the Divine relay. Cancels any existing stream first.
    func subscribe() {
        stop()
        streamTask = Task {
            await self.loadInitialPage()
            await self.stream()
        }
    }

    /// Cancels the active stream and all in-flight prefetch tasks.
    /// - Parameter disconnect: When `true`, also disconnects the feature-managed relay.
    func stop(disconnect: Bool = false) {
        streamTask?.cancel()
        streamTask = nil
        for task in prefetchTasks { task.cancel() }
        prefetchTasks.removeAll()
        if disconnect {
            Task {
                await self.disconnectManagedRelayIfNeeded()
            }
        }
    }

    /// Clears the feed and re-subscribes from scratch. Called by pull-to-refresh.
    func refresh() async {
        await MainActor.run {
            vines.removeAll()
            lastSeenTimestamp = nil
            oldestTimestamp = nil
            hasMoreOlder = true
        }
        subscribe()
    }

    /// Reacts to changes in Vine-related settings (relay toggle). Stops or starts the stream as needed.
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

    /// Called when a vine card appears on-screen. Triggers pagination and prefetching.
    @MainActor
    func noteAppeared(at index: Int) {
        maybeLoadOlder(after: index)
        guard shouldPrefetchVideos else { return }
        let targets = [index, index + 1]
        let allowCellular = damus_state.settings.prefetch_vines_on_cellular

        // Collect URLs on main actor before detaching to avoid data race
        let urlsToPrefetch = targets.compactMap { target -> URL? in
            guard vines.indices.contains(target) else { return nil }
            return vines[target].playbackURL
        }

        let task = Task.detached(priority: .background) { [weak self] in
            for url in urlsToPrefetch {
                guard !Task.isCancelled else { break }
                await self?.prefetch(url: url, allowCellular: allowCellular)
            }
        }
        prefetchTasks.append(task)
        prefetchTasks.removeAll(where: { $0.isCancelled })
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

    /// Downloads a video and writes it to the on-disk VideoCache.
    /// Network I/O and file writes run off the main actor; only the
    /// deduplication set is touched on @MainActor.
    private func prefetch(url: URL, allowCellular: Bool) async {
        let shouldProceed = await MainActor.run { markPrefetching(url) }
        guard shouldProceed else { return }
        defer { Task { @MainActor in self.unmarkPrefetching(url) } }

        var request = URLRequest(url: url)
        request.allowsExpensiveNetworkAccess = allowCellular
        request.allowsConstrainedNetworkAccess = allowCellular
        request.timeoutInterval = 15

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  200..<300 ~= httpResponse.statusCode else {
                Log.debug("Vine prefetch got bad response for %s", for: .timeline, url.absoluteString)
                return
            }

            guard let cache = VideoCache.standard else {
                Log.debug("VideoCache not available for prefetch", for: .timeline)
                return
            }

            let cachedURL = cache.url_to_cached_url(url: url)
            try data.write(to: cachedURL)
            Log.debug("Prefetched Vine video to cache: %s", for: .timeline, url.absoluteString)
        } catch {
            Log.debug("Vine prefetch failed for %s: %s", for: .timeline, url.absoluteString, error.localizedDescription)
        }
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
