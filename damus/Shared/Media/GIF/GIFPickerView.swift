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

    @StateObject private var viewModel: GIFPickerViewModel
    @State private var searchText: String = ""
    @FocusState private var isSearchFocused: Bool

    /// Creates a GIF picker bound to the current Damus state.
    init(damus_state: DamusState, onGIFSelected: @escaping (URL) -> Void) {
        self.damus_state = damus_state
        self.onGIFSelected = onGIFSelected
        _viewModel = StateObject(wrappedValue: GIFPickerViewModel(purple: damus_state.purple))
    }

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
                TextField(NSLocalizedString("Search KLIPY", comment: "Placeholder for GIF search field"), text: $searchText)
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

    private func errorView(_ error: ErrorView.UserPresentableError) -> some View {
        VStack {
            ErrorView(damus_state: damus_state, error: error)

            Button(NSLocalizedString("Try Again", comment: "Button to retry loading GIFs")) {
                Task {
                    if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        await viewModel.loadFeatured()
                        return
                    }

                    viewModel.search(query: searchText)
                }
            }
            .buttonStyle(.bordered)
            .padding(.bottom, 20)
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
    let gif: GIFResult
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
    @Published var gifs: [GIFResult] = []
    @Published var isLoading: Bool = false
    @Published var error: ErrorView.UserPresentableError? = nil

    private let api: PurpleGIFAPIClient
    private let featuredPageSize = 30
    private let searchPageSize = 30
    private var currentQuery: String?
    private var pendingQuery: String?
    private var nextPos: String?
    private var currentPage = 1
    private var hasMoreSearchResults = false
    private var searchTask: Task<Void, Never>?

    /// Initializes a GIF picker view model backed by Purple.
    init(purple: DamusPurple) {
        self.api = PurpleGIFAPIClient(purple: purple)
    }

    /// Loads featured GIFs for the initial picker state.
    func loadFeatured() async {
        guard !isLoading else { return }

        isLoading = true
        error = nil
        currentQuery = nil
        currentPage = 1
        hasMoreSearchResults = false

        do {
            let response = try await api.fetchFeatured(limit: featuredPageSize)
            gifs = response.results
            nextPos = response.next
        } catch {
            self.error = makePresentableError(from: error, action: "loading featured GIFs")
        }

        isLoading = false
        await runPendingQueryIfNeeded()
    }

    /// Starts a debounced GIF search.
    func search(query: String) {
        searchTask?.cancel()

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        pendingQuery = trimmedQuery.isEmpty ? nil : trimmedQuery

        guard !trimmedQuery.isEmpty else {
            Task { await loadFeatured() }
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            await performSearch(query: trimmedQuery)
        }
    }

    /// Performs a GIF search request.
    private func performSearch(query: String) async {
        guard !isLoading else {
            pendingQuery = query
            return
        }

        isLoading = true
        error = nil
        currentQuery = query
        pendingQuery = nil
        currentPage = 1
        nextPos = nil
        hasMoreSearchResults = false

        do {
            let response = try await api.search(query: query, page: currentPage, perPage: searchPageSize)
            gifs = response.results
            hasMoreSearchResults = response.results.count >= searchPageSize
        } catch {
            self.error = makePresentableError(from: error, action: "searching GIFs")
        }

        isLoading = false
        await runPendingQueryIfNeeded()
    }

    /// Converts technical GIF loading errors into user-presentable content.
    private func makePresentableError(from error: Error, action: String) -> ErrorView.UserPresentableError {
        if let presentableError = error as? ErrorView.UserPresentableErrorProtocol {
            return presentableError.userPresentableError
        }

        if let gifError = error as? PurpleGIFAPIError {
            return gifError.userPresentableError(action: action, currentQuery: currentQuery)
        }

        return .init(
            user_visible_description: NSLocalizedString("We couldn't load GIFs right now.", comment: "Fallback error shown when the GIF picker fails unexpectedly."),
            tip: NSLocalizedString("Try again in a moment. If the problem keeps happening, copy the technical information and send it to support.", comment: "Fallback advice shown when the GIF picker fails unexpectedly."),
            technical_info: "GIF picker error while \(action): \(String(describing: error))"
        )
    }

    /// Runs the latest queued search after the current load completes.
    private func runPendingQueryIfNeeded() async {
        guard !isLoading else { return }
        guard let pendingQuery, pendingQuery != currentQuery else { return }

        self.pendingQuery = nil
        await performSearch(query: pendingQuery)
    }

    /// Loads the next page of GIF results.
    func loadMore() async {
        guard !isLoading else { return }

        if let query = currentQuery {
            guard hasMoreSearchResults else { return }

            isLoading = true

            do {
                let nextPage = currentPage + 1
                let response = try await api.search(query: query, page: nextPage, perPage: searchPageSize)
                gifs.append(contentsOf: response.results)
                currentPage = nextPage
                hasMoreSearchResults = response.results.count >= searchPageSize
            } catch {
                print("Failed to load more GIFs: \(error)")
            }

            isLoading = false
            return
        }

        guard let nextPos else { return }

        isLoading = true

        do {
            let response = try await api.fetchFeatured(limit: featuredPageSize, pos: nextPos)
            gifs.append(contentsOf: response.results)
            self.nextPos = response.next
        } catch {
            print("Failed to load more GIFs: \(error)")
        }

        isLoading = false
    }
}

private extension PurpleGIFAPIError {
    /// Converts Purple GIF API failures into a reusable user-presentable error.
    func userPresentableError(action: String, currentQuery: String?) -> ErrorView.UserPresentableError {
        let queryContext = currentQuery.map { "query=\($0)" } ?? "featured"

        switch self {
        case .unauthorized:
            return .init(
                user_visible_description: NSLocalizedString("You need an active Purple subscription to use GIF search.", comment: "Error shown when the user is not authorized to use the GIF picker."),
                tip: NSLocalizedString("Make sure you're signed in with the right account and that your Purple subscription is active, then try again.", comment: "Advice shown when GIF picker access is denied."),
                technical_info: "GIF picker unauthorized while \(action); context=\(queryContext)"
            )
        case .invalidURL:
            return .init(
                user_visible_description: NSLocalizedString("The GIF service is misconfigured.", comment: "Error shown when the GIF picker generated an invalid URL."),
                tip: NSLocalizedString("Try again later. If this keeps happening, copy the technical information and send it to support.", comment: "Advice shown when the GIF picker URL is invalid."),
                technical_info: "GIF picker invalid URL while \(action); context=\(queryContext)"
            )
        case .invalidResponse:
            return .init(
                user_visible_description: NSLocalizedString("The GIF service returned an unexpected response.", comment: "Error shown when the GIF picker receives an invalid server response."),
                tip: NSLocalizedString("Try again in a moment. If it keeps happening, copy the technical information and send it to support.", comment: "Advice shown when the GIF picker receives an invalid server response."),
                technical_info: "GIF picker invalid response while \(action); context=\(queryContext)"
            )
        case .decodingError(let decodingError, let rawResponse):
            let responseText = rawResponse ?? "<unavailable>"
            return .init(
                user_visible_description: NSLocalizedString("We couldn't understand the GIF data from the server.", comment: "Error shown when GIF response parsing fails."),
                tip: NSLocalizedString("Try again in a moment. If the problem continues, copy the technical information and send it to support.", comment: "Advice shown when GIF response parsing fails."),
                technical_info: "GIF picker decoding error while \(action); context=\(queryContext); error=\(String(describing: decodingError)); response=\(responseText)"
            )
        case .networkError(let networkError):
            return .init(
                user_visible_description: NSLocalizedString("We couldn't reach the GIF service.", comment: "Error shown when GIF loading fails because of a network issue."),
                tip: NSLocalizedString("Check your internet connection and try again.", comment: "Advice shown when GIF loading fails because of a network issue."),
                technical_info: "GIF picker network error while \(action); context=\(queryContext); error=\(String(describing: networkError))"
            )
        case .upstreamError(let statusCode, let message):
            return .init(
                user_visible_description: NSLocalizedString("The GIF service is temporarily unavailable.", comment: "Error shown when the upstream GIF service fails."),
                tip: NSLocalizedString("Try again in a moment. If the problem keeps happening, copy the technical information and send it to support.", comment: "Advice shown when the upstream GIF service fails."),
                technical_info: "GIF picker upstream error while \(action); context=\(queryContext); status=\(statusCode); message=\(message ?? "none")"
            )
        }
    }
}

#Preview {
    GIFPickerView(damus_state: test_damus_state) { url in
        print("Selected GIF: \(url)")
    }
}
