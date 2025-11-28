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
    @State private var retryingPosts: Set<String> = []
    @State private var retryStatusMessage: RetryStatusMessage?
    
    var pendingPosts: [PendingPost] {
        store.posts
    }
    
    var body: some View {
        List {
            if let error = store.lastError {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text(error.message)
                            .font(.subheadline)
                        Spacer()
                        Button {
                            store.clearError()
                        } label: {
                            Text("Dismiss", comment: "Button title for dismissing a persistence error banner.")
                        }
                        .font(.caption)
                    }
                    .accessibilityIdentifier("outbox-persistence-error")
                }
            }
            
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
                        deleteAction: { remove(post) },
                        isRetrying: retryingPosts.contains(post.id)
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier(AppAccessibilityIdentifiers.outbox_list.rawValue)
        .navigationTitle(Text("Outbox", comment: "Navigation title for the view listing pending posts awaiting delivery."))
        .alert(item: $retryStatusMessage) { status in
            Alert(
                title: Text("Outbox", comment: "Title for alerts shown in the outbox view."),
                message: Text(status.message),
                dismissButton: .default(Text("OK", comment: "Alert dismissal button title."))
            )
        }
    }
    
    private func retry(_ post: PendingPost) {
        if retryingPosts.contains(post.id) {
            return
        }
        
        guard let event = post.event else {
            retryStatusMessage = RetryStatusMessage(
                message: NSLocalizedString("Unable to resend this note because it is missing local data.", comment: "Error shown when retrying a pending post without serialized content.")
            )
            return
        }
        
        retryingPosts.insert(post.id)
        Task {
            await postbox.send(event, trackPending: true)
            await MainActor.run {
                retryingPosts.remove(post.id)
                retryStatusMessage = RetryStatusMessage(
                    message: NSLocalizedString("Note queued for delivery. It will disappear once a relay acknowledges it.", comment: "Confirmation shown after tapping retry on a pending post.")
                )
            }
        }
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
    let isRetrying: Bool
    
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
                
                if isRetrying {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 28, height: 28)
                        .accessibilityIdentifier("pending-post-\(post.id)-retrying")
                } else {
                    Button(action: retryAction) {
                        Label(NSLocalizedString("Send now", comment: "Button title to immediately send a pending post."), systemImage: "arrow.up.circle")
                    }
                    .labelStyle(.iconOnly)
                    .font(.title3)
                    .buttonStyle(.borderless)
                    .accessibilityLabel(Text("Send pending note now", comment: "Accessibility label describing the action to immediately send a pending post." ))
                }
                
                Button(role: .destructive, action: deleteAction) {
                    Image(systemName: "trash")
                }
                .font(.title3)
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Delete pending note", comment: "Accessibility label describing the action to delete a pending post."))
            }
        }
        .padding(.vertical, 4)
    }
}

private struct RetryStatusMessage: Identifiable {
    let id = UUID()
    let message: String
}
