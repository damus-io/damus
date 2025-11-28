//
//  PendingPostStore.swift
//  damus
//
//  Created by OpenAI Codex on 2025-01-04.
//

import Foundation
import os

struct PendingPost: Codable, Identifiable {
    enum Status: String, Codable {
        case pending
        case sent
    }
    
    let id: String
    let createdAt: Date
    var updatedAt: Date
    var status: Status
    let eventJSON: String
    
    init(event: NostrEvent) {
        self.id = event.id.hex()
        self.createdAt = Date()
        self.updatedAt = Date()
        self.status = .pending
        self.eventJSON = event_to_json(ev: event)
    }
    
    var noteId: NoteId? {
        NoteId(hex: id)
    }
    
    var event: NostrEvent? {
        decode_nostr_event_json(json: eventJSON)
    }
    
    var preview: String {
        event?.content ?? NSLocalizedString("Pending note", comment: "Fallback preview text for a pending outbox note.")
    }
}

struct PendingPostStoreError: Identifiable {
    let id = UUID()
    let message: String
}

@MainActor
final class PendingPostStore: ObservableObject {
    @Published private(set) var posts: [PendingPost] = []
    @Published private(set) var lastError: PendingPostStoreError?
    
    private let ioQueue = DispatchQueue(label: "io.damus.pendingposts", qos: .utility)
    private let fileURL: URL
    
    private static let logger = Logger(
        subsystem: Constants.MAIN_APP_BUNDLE_IDENTIFIER,
        category: "pending_post_store"
    )
    
    init(fileURL: URL? = nil) {
        if let fileURL {
            self.fileURL = fileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            let folder = base.appendingPathComponent("PendingPosts", isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            self.fileURL = folder.appendingPathComponent("pending-posts.json")
        }
        load()
    }
    
    func pendingEvents() -> [NostrEvent] {
        posts.compactMap { $0.status == .pending ? $0.event : nil }
    }
    
    func clearError() {
        lastError = nil
    }
    
    func track(event: NostrEvent) {
        if let index = posts.firstIndex(where: { $0.id == event.id.hex() }) {
            posts[index].updatedAt = Date()
            posts[index].status = .pending
        } else {
            posts.append(PendingPost(event: event))
        }
        posts.sort(by: { $0.createdAt > $1.createdAt })
        persist(snapshot: posts)
    }
    
    func markSent(_ id: NoteId) {
        posts.removeAll { $0.id == id.hex() }
        persist(snapshot: posts)
    }
    
    func remove(_ id: NoteId) {
        posts.removeAll { $0.id == id.hex() }
        persist(snapshot: posts)
    }
    
    private func load() {
        ioQueue.async {
            if !FileManager.default.fileExists(atPath: self.fileURL.path) {
                return
            }
            
            do {
                let data = try Data(contentsOf: self.fileURL)
                let decoded = try JSONDecoder().decode([PendingPost].self, from: data)
                Task { @MainActor in
                    self.posts = decoded.sorted(by: { $0.createdAt > $1.createdAt })
                }
            } catch {
                self.publishPersistenceError(message: "Failed to load pending posts", error: error)
            }
        }
    }
    
    private func persist(snapshot: [PendingPost]) {
        ioQueue.async {
            do {
                let data = try JSONEncoder().encode(snapshot)
                try data.write(to: self.fileURL)
            } catch {
                self.publishPersistenceError(message: "Failed to save pending posts", error: error)
            }
        }
    }
    
    private func publishPersistenceError(message: String, error: Error) {
        Self.logger.error("\(message, privacy: .public): \(error.localizedDescription, privacy: .public)")
        Task { @MainActor in
            self.lastError = PendingPostStoreError(
                message: "\(message): \(error.localizedDescription)"
            )
        }
    }
}
