//
//  GIFPickerView.swift
//  damus
//
//  Created by eric on 12/11/25.
//

import SwiftUI
import Kingfisher

struct GIFPickerView: View {
    @Environment(\.dismiss) var dismiss
    let damus_state: DamusState
    let onGIFSelected: (URL) -> Void

    @StateObject private var viewModel = GIFPickerViewModel()
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                SearchInput
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                Divider()

                if viewModel.isLoading && viewModel.gifs.isEmpty {
                    loadingView
                } else if let error = viewModel.error {
                    errorView(error)
                } else if viewModel.gifs.isEmpty {
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
            await viewModel.loadFeatured()
        }
        .onChange(of: searchText) { newValue in
            viewModel.search(query: newValue)
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
                            if let gifURL = gif.mediumURL ?? gif.fullURL {
                                onGIFSelected(gifURL)
                                dismiss()
                            }
                        }
                        .onAppear {
                            if gif.id == viewModel.gifs.last?.id {
                                Task { await viewModel.loadMore() }
                            }
                        }
                }
            }
            .padding(4)

            if viewModel.isLoading && !viewModel.gifs.isEmpty {
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

    private func errorView(_ error: String) -> some View {
        VStack {
            Spacer()
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.secondary)
            Text(error)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding()
            Button(NSLocalizedString("Try Again", comment: "Button to retry loading GIFs")) {
                Task {
                    if searchText.isEmpty {
                        await viewModel.loadFeatured()
                    } else {
                        viewModel.search(query: searchText)
                    }
                }
            }
            .buttonStyle(.bordered)
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
    let gif: TenorGIFResult
    let disable_animation: Bool

    var body: some View {
        if let previewURL = gif.previewURL {
            KFAnimatedImage(previewURL)
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
        } else {
            Rectangle()
                .fill(Color.secondary.opacity(0.2))
                .frame(height: 120)
                .cornerRadius(8)
        }
    }
}

@MainActor
class GIFPickerViewModel: ObservableObject {
    @Published var gifs: [TenorGIFResult] = []
    @Published var isLoading: Bool = false
    @Published var error: String? = nil

    private let api = TenorAPIClient()
    private var currentQuery: String?
    private var nextPos: String?
    private var searchTask: Task<Void, Never>?

    func loadFeatured() async {
        guard !isLoading else { return }

        isLoading = true
        error = nil
        currentQuery = nil

        do {
            let response = try await api.fetchFeatured()
            gifs = response.results
            nextPos = response.next
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func search(query: String) {
        searchTask?.cancel()

        guard !query.isEmpty else {
            Task { await loadFeatured() }
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(query: query)
        }
    }

    private func performSearch(query: String) async {
        guard !isLoading else { return }

        isLoading = true
        error = nil
        currentQuery = query
        nextPos = nil

        do {
            let response = try await api.search(query: query)
            gifs = response.results
            nextPos = response.next
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }

    func loadMore() async {
        guard !isLoading, let nextPos else { return }

        isLoading = true

        do {
            let response: TenorSearchResponse
            if let query = currentQuery {
                response = try await api.search(query: query, pos: nextPos)
            } else {
                response = try await api.fetchFeatured(pos: nextPos)
            }
            gifs.append(contentsOf: response.results)
            self.nextPos = response.next
        } catch {
            // Don't show error for pagination failures
            print("Failed to load more GIFs: \(error)")
        }

        isLoading = false
    }
}

#Preview {
    GIFPickerView(damus_state: test_damus_state) { url in
        print("Selected GIF: \(url)")
    }
}


