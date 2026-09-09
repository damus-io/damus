import SwiftUI
import PhotosUI

/// Compact controls remain available after recording; attachments belong only to audio.
struct VoiceAttachmentButtons: View {
    @ObservedObject var model: VoiceComposerModel
    @State private var mentionPresented = false
    @State private var linkPresented = false
    @State private var link = ""
    @State private var selectedPhotos: [PhotosPickerItem] = []

    var body: some View {
        HStack(spacing: 0) {
            Button { mentionPresented = true } label: { Image(systemName: "at").frame(width: 44, height: 44) }
                .accessibilityLabel("Mention someone").accessibilityIdentifier("voice.addMention")
            Button { link = ""; linkPresented = true } label: { Image(systemName: "link").frame(width: 44, height: 44) }
                .accessibilityLabel("Add a web link").accessibilityIdentifier("voice.addLink")
            PhotosPicker(selection: $selectedPhotos, maxSelectionCount: max(1, 8 - model.attachments.photos.count), matching: .images) {
                Image(systemName: "photo").frame(width: 44, height: 44)
            }
            .disabled(model.attachments.photos.count >= 8)
            .accessibilityLabel("Add photos").accessibilityIdentifier("voice.addPhotos")
        }
        .font(.system(size: 20))
        .disabled(!model.canEditAttachments)
        .sheet(isPresented: $mentionPresented) { VoiceMentionPicker(model: model) }
        .sheet(isPresented: $linkPresented) {
            NavigationStack {
                Form {
                    TextField("https://example.com", text: $link)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("voice.linkURL")
                    if let error = model.error { Text(error).foregroundColor(.red) }
                }
                .navigationTitle("Add a link")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { linkPresented = false } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") { if model.addLink(link) { linkPresented = false } }
                            .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.canEditAttachments)
                    }
                }
            }
        }
        .onChange(of: selectedPhotos) { items in
            guard !items.isEmpty, let id = model.draft?.id else { return }
            model.addPhotos(items.map { item in
                {
                    guard let data = try await item.loadTransferable(type: Data.self) else {
                        throw VoiceFailure("The selected photo could not be loaded.")
                    }
                    return data
                }
            }, compositionID: id)
            selectedPhotos = []
        }
    }
}

/// Reuse the same profile search and result rows as Damus's text composer.
private struct VoiceMentionPicker: View {
    @ObservedObject var model: VoiceComposerModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [Pubkey] = []
    @State private var unusedPost = NSMutableAttributedString()
    @State private var unusedWord: (String?, NSRange?) = (nil, nil)
    @State private var unusedCursor: Int?
    @StateObject private var tagModel = TagModel()

    var body: some View {
        NavigationStack {
            VStack {
                TextField("Search people", text: $query)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder).padding()
                    .accessibilityIdentifier("voice.mentionSearch")
                UserSearch(damus_state: model.state, search: query,
                           onSelect: { pubkey in model.addMention(pubkey); dismiss() }, results: results,
                           focusWordAttributes: $unusedWord, newCursorIndex: $unusedCursor, post: $unusedPost)
                    .environmentObject(tagModel)
            }
            .task(id: query) {
                let profiles = model.state.profiles
                let term = query
                let matches = await Task.detached {
                    search_profile_ids(profiles: profiles, search: term)
                }.value
                guard !Task.isCancelled, model.state.voiceLifetime.isActive else { return }
                results = matches.sorted { a, b in
                    (get_friend_type(contacts: model.state.contacts, pubkey: a)?.priority ?? 0) >
                        (get_friend_type(contacts: model.state.contacts, pubkey: b)?.priority ?? 0)
                }
            }
            .navigationTitle("Mention someone")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

/// Review/removal controls never mutate the normal text draft or its attachments.
struct VoiceAttachmentReview: View {
    @ObservedObject var model: VoiceComposerModel
    @State private var names: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(model.attachments.mentions, id: \.self) { hex in
                if let pubkey = Pubkey(hex: hex) {
                    HStack {
                        Text("@" + (names[hex] ?? pubkey.npub))
                            .lineLimit(1)
                        Spacer()
                        remove("Remove mention") { model.removeMention(hex) }
                    }
                }
            }
            ForEach(model.attachments.links, id: \.self) { link in
                HStack(alignment: .center) {
                    Label(link, systemImage: "link").lineLimit(2)
                    Spacer()
                    remove("Remove link") { model.removeLink(link) }
                }
            }
            if !model.attachments.photos.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 12) {
                        ForEach(model.attachments.photos) { photo in
                            if let image = model.photoPreviews[photo.id] {
                                Image(uiImage: image)
                                    .resizable().scaledToFill().frame(width: 120, height: 120).clipped()
                                    .cornerRadius(8)
                                    .accessibilityLabel("Attached photo")
                                    .overlay(alignment: .topTrailing) {
                                        remove("Remove photo") { model.removePhoto(photo.id) }
                                            .background(.regularMaterial, in: Circle())
                                    }
                            }
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("voice.attachments")
        .task(id: model.attachments.mentions) {
            let mentions = model.attachments.mentions
            let profiles = model.state.profiles
            let resolved = await Task.detached {
                var result: [String: String] = [:]
                for hex in mentions {
                    guard let pubkey = Pubkey(hex: hex) else { continue }
                    result[hex] = Profile.displayName(profile: try? profiles.lookup(id: pubkey), pubkey: pubkey).username
                }
                return result
            }.value
            guard !Task.isCancelled, model.state.voiceLifetime.isActive else { return }
            names = resolved
        }
    }

    private func remove(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44) }
            .accessibilityLabel(label).disabled(!model.canEditAttachments)
    }
}
