//
//  GIFPickerView.swift
//  damus
//
//  Created by eric on 12/11/25.
//  Updated for Nostr-native GIF discovery.
//

import SwiftUI
import Kingfisher

struct GIFPickerView: View {
    @Environment(\.dismiss) var dismiss
    let damus_state: DamusState
    let onGIFSelected: (URL) -> Void

    @StateObject private var viewModel: GIFSearchModel
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool

    init(damus_state: DamusState, onGIFSelected: @escaping (URL) -> Void) {
        self.damus_state = damus_state
        self.onGIFSelected = onGIFSelected
        _viewModel = StateObject(wrappedValue: GIFSearchModel(damus_state: damus_state))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                SearchInput
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Divider()

                if viewModel.loading && viewModel.gifs.isEmpty {
                    loadingView
                } else if viewModel.gifs.isEmpty && !viewModel.loading {
                    emptyView
                } else {
                    gifGrid
                }
            }
            .navigationTitle(NSLocalizedString("Select GIF", comment: "Title for GIF picker sheet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "Button to cancel GIF selection")) {
                        dismiss()
                    }
                }
            }
        }
        .task {
            viewModel.load()
        }
        .onChange(of: searchText) { newValue in
            if newValue.isEmpty {
                viewModel.load()
            } else {
                viewModel.search(query: newValue)
            }
        }
        .onDisappear {
            viewModel.cancel()
        }
    }

    private var SearchInput: some View {
        HStack {
            HStack {
                Image("search")
                    .foregroundColor(.gray)
                TextField(NSLocalizedString("Search GIFs...", comment: "Placeholder for GIF search field"), text: $searchText)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                    .focused($isSearchFocused)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(10)
            .background(.secondary.opacity(0.2))
            .cornerRadius(20)
        }
    }

    private var gifGrid: some View {
        ScrollView {
            LazyVGrid(columns: [
                GridItem(.flexible(), spacing: 4),
                GridItem(.flexible(), spacing: 4)
            ], spacing: 4) {
                ForEach(viewModel.gifs) { gif in
                    GIFThumbnailView(gif: gif, disable_animation: damus_state.settings.disable_animation)
                        .onTapGesture {
                            onGIFSelected(gif.url)
                            dismiss()
                        }
                }
            }
            .padding(4)

            if viewModel.loading && !viewModel.gifs.isEmpty {
                ProgressView()
                    .padding()
            }
        }
    }

    private var loadingView: some View {
        VStack {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Loading GIFs...", comment: "Loading indicator text for GIF picker")
                .foregroundColor(.secondary)
                .padding(.top)
            Spacer()
        }
    }

    private var emptyView: some View {
        VStack {
            Spacer()
            Image(systemName: "photo.on.rectangle.angled")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text("No GIFs found", comment: "Message when no GIFs match search")
                .foregroundColor(.secondary)
                .padding(.top)
            Spacer()
        }
    }
}

struct GIFThumbnailView: View {
    let gif: DiscoveredGIF
    let disable_animation: Bool

    var body: some View {
        let displayURL = gif.thumbURL ?? gif.url
        KFAnimatedImage(displayURL)
            .configure { view in
                view.framePreloadCount = 3
            }
            .placeholder {
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
            }
            .imageContext(.note, disable_animation: disable_animation)
            .aspectRatio(contentMode: .fill)
            .frame(height: 120)
            .clipped()
            .cornerRadius(8)
    }
}
