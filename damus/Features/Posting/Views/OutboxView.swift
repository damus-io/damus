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
                    PendingPostRow(post: post,
                                   retryAction: { retry(post) },
                                   deleteAction: { remove(post) })
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
    let retryAction: () -> Void
    let deleteAction: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(post.preview)
                .font(.body)
                .lineLimit(3)
            
            HStack {
                Text(post.createdAt, style: .time)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button(action: retryAction) {
                    Label(NSLocalizedString("Send now", comment: "Button title to immediately send a pending post."), systemImage: "arrow.up.circle")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                
                Button(role: .destructive, action: deleteAction) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}
