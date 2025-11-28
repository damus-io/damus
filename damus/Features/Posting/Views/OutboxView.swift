//
//  OutboxView.swift
//  damus
//
//  Created by OpenAI Codex on 2025-01-04.
//

import SwiftUI

struct OutboxView: View {
    @ObservedObject var store: PendingPostStore
    let postbox: PostBox
    let damusState: DamusState
    
    var pendingPosts: [PendingPost] {
        store.posts
    }
    
    var body: some View {
        List {
            if pendingPosts.isEmpty {
                VStack(alignment: .center, spacing: 8) {
                    Image(systemName: "paperplane")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Text("Outbox empty", comment: "Empty state title when there are no pending notes in the outbox.")
                        .font(.headline)
                    Text("Notes waiting to send will appear here when you are offline.", comment: "Additional context explaining the outbox purpose.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .listRowBackground(Color.clear)
            } else {
                ForEach(pendingPosts) { post in
                    PendingPostRow(
                        post: post,
                        damusState: damusState,
                        retryAction: { retry(post) },
                        deleteAction: { remove(post) }
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(Text("Outbox", comment: "Navigation title for the view listing pending posts awaiting delivery."))
    }
    
    private func retry(_ post: PendingPost) {
        guard let event = post.event else { return }
        Task { await postbox.send(event, trackPending: false) }
    }
    
    private func remove(_ post: PendingPost) {
        guard let noteId = post.noteId else { return }
        postbox.dropPending(noteId: noteId)
    }
}

private struct PendingPostRow: View {
    let post: PendingPost
    let damusState: DamusState
    let retryAction: () -> Void
    let deleteAction: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let event = post.event {
                NoteContentView(
                    damus_state: damusState,
                    event: event,
                    blur_images: should_blur_images(damus_state: damusState, ev: event),
                    size: .normal,
                    options: [.truncate_content]
                )
                .accessibilityIdentifier("pending-post-\(post.id)")
            } else {
                Text(post.preview)
                    .font(.body)
            }
            
            HStack(spacing: 20) {
                Text(post.createdAt, style: .time)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button(action: retryAction) {
                    Label(NSLocalizedString("Send now", comment: "Button title to immediately send a pending post."), systemImage: "arrow.up.circle")
                }
                .labelStyle(.iconOnly)
                .font(.title3)
                .buttonStyle(.borderless)
                
                Button(role: .destructive, action: deleteAction) {
                    Image(systemName: "trash")
                }
                .font(.title3)
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}
