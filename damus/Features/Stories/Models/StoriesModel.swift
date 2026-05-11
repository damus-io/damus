//
//  StoriesModel.swift
//  damus
//
//  Created by William Casarin on 2026-05-11.
//

import Foundation

struct StorySlide: Identifiable, Equatable {
    let event: NostrEvent
    let imeta: ImageMetadata
    let expiresAt: Date?

    var id: NoteId { event.id }
    var createdAt: UInt32 { event.created_at }

    static func == (lhs: StorySlide, rhs: StorySlide) -> Bool {
        lhs.event.id == rhs.event.id
    }
}

struct Story: Identifiable, Equatable {
    let author: Pubkey
    var slides: [StorySlide]

    var id: Pubkey { author }
    var latestCreatedAt: UInt32 { slides.map(\.createdAt).max() ?? 0 }
}

@MainActor
class StoriesModel: ObservableObject {
    @Published private(set) var tray: [Story] = []

    let damus: DamusState
    private var listener: Task<Void, Never>? = nil
    private var stories: [Pubkey: Story] = [:]

    private static let WINDOW: TimeInterval = 24 * 60 * 60

    init(damus: DamusState) {
        self.damus = damus
    }

    func subscribe() {
        listener?.cancel()
        listener = Task { [weak self] in
            await self?.runSubscription()
        }
    }

    func unsubscribe() {
        listener?.cancel()
        listener = nil
    }

    private func runSubscription() async {
        var authors = damus.contacts.get_friend_list()
        authors.insert(damus.pubkey)
        let since = UInt32(Date().timeIntervalSince1970 - Self.WINDOW)
        let nostrFilter = NostrFilter(
            kinds: [.picture],
            since: since,
            authors: Array(authors),
            tag_T: ["story"]
        )
        do {
            let ndbFilter = try NdbFilter(from: nostrFilter)
            for await item in try damus.ndb.subscribe(filters: [ndbFilter]) {
                switch item {
                case .eose:
                    continue
                case .event(let noteKey):
                    let lender = NdbNoteLender(ndb: damus.ndb, noteKey: noteKey)
                    if let ev = lender.justGetACopy() {
                        ingest(ev)
                    }
                }
            }
        } catch {
            print("StoriesModel: local subscription failed: \(error)")
        }
    }

    private func ingest(_ ev: NostrEvent) {
        guard ev.known_kind == .picture else { return }
        guard hasStoryTag(ev) else { return }
        guard let imeta = event_image_metadata(ev: ev).first else { return }

        let now = Date()
        let expiresAt = parseExpiration(ev)
        if let expiresAt, expiresAt <= now { return }
        let cutoff = UInt32(now.timeIntervalSince1970 - Self.WINDOW)
        if ev.created_at < cutoff { return }

        let slide = StorySlide(event: ev, imeta: imeta, expiresAt: expiresAt)
        let author = ev.pubkey

        var story = stories[author] ?? Story(author: author, slides: [])
        if story.slides.contains(where: { $0.id == slide.id }) { return }
        story.slides.append(slide)
        story.slides.sort { $0.createdAt < $1.createdAt }
        stories[author] = story

        rebuildTray()
    }

    private func rebuildTray() {
        let now = Date()
        let cutoff = UInt32(now.timeIntervalSince1970 - Self.WINDOW)
        for (pk, var story) in stories {
            story.slides.removeAll { slide in
                if let exp = slide.expiresAt, exp <= now { return true }
                return slide.createdAt < cutoff
            }
            if story.slides.isEmpty {
                stories.removeValue(forKey: pk)
            } else {
                stories[pk] = story
            }
        }
        let me = damus.pubkey
        tray = stories.values.sorted { a, b in
            if a.author == me { return true }
            if b.author == me { return false }
            return a.latestCreatedAt > b.latestCreatedAt
        }
    }
}

@MainActor
class StoryViewerModel: ObservableObject {
    @Published private(set) var authorIndex: Int
    @Published private(set) var slideIndex: Int = 0
    @Published private(set) var progress: Double = 0
    @Published var paused: Bool = false

    let stories: [Story]
    let onDismiss: () -> Void

    static let SLIDE_DURATION: TimeInterval = 5.0

    init(stories: [Story], startAuthorIndex: Int, onDismiss: @escaping () -> Void) {
        self.stories = stories
        self.authorIndex = startAuthorIndex
        self.onDismiss = onDismiss
    }

    var currentStory: Story? {
        guard stories.indices.contains(authorIndex) else { return nil }
        return stories[authorIndex]
    }

    var currentSlide: StorySlide? {
        guard let s = currentStory, s.slides.indices.contains(slideIndex) else { return nil }
        return s.slides[slideIndex]
    }

    func fillFraction(at i: Int) -> Double {
        if i < slideIndex { return 1.0 }
        if i == slideIndex { return progress }
        return 0
    }

    /// Drive one slide's progress to completion, then advance.
    /// The view owns the Task via `.task(id:)`; cancellation happens when slide/author changes.
    func runCurrentSlide() async {
        progress = 0
        let steps = 60
        let stepDuration = Self.SLIDE_DURATION / Double(steps)
        for _ in 0..<steps {
            if Task.isCancelled { return }
            try? await Task.sleep(for: .seconds(stepDuration))
            if Task.isCancelled { return }
            if !paused {
                progress = min(1.0, progress + 1.0 / Double(steps))
            }
        }
        if Task.isCancelled { return }
        nextSlide()
    }

    func previousSlide() {
        if slideIndex > 0 {
            slideIndex -= 1
        } else {
            previousAuthor()
        }
    }

    func nextSlide() {
        guard let count = currentStory?.slides.count else { return }
        if slideIndex + 1 < count {
            slideIndex += 1
        } else {
            nextAuthor()
        }
    }

    func previousAuthor() {
        if authorIndex > 0 {
            authorIndex -= 1
            slideIndex = 0
        } else {
            slideIndex = 0
        }
    }

    func nextAuthor() {
        if authorIndex + 1 < stories.count {
            authorIndex += 1
            slideIndex = 0
        } else {
            onDismiss()
        }
    }
}

private func hasStoryTag(_ ev: NostrEvent) -> Bool {
    for tag in ev.tags {
        guard tag.count >= 2 else { continue }
        if tag[0].matches_char("T") && tag[1].matches_str("story") {
            return true
        }
    }
    return false
}

private func parseExpiration(_ ev: NostrEvent) -> Date? {
    guard let tag = ev.tags.first(where: { t in t.count >= 2 && t[0].matches_str("expiration") }),
          tag.count == 2,
          let expires = UInt32(tag[1].string()) else {
        return nil
    }
    return Date(timeIntervalSince1970: TimeInterval(expires))
}
