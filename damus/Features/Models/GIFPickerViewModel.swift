//
//  GIFPickerViewModel.swift
//  damus
//
//  Drives the GIF picker UI with pluggable providers.
//

import Foundation

@MainActor
final class GIFPickerViewModel: ObservableObject {
    enum Provider: String, CaseIterable, Identifiable {
        case nostr
        case tenor

        var id: String { rawValue }

        var title: String {
            switch self {
            case .nostr: return "Nostr"
            case .tenor: return "Tenor"
            }
        }
    }

    @Published var searchText: String = ""
    @Published var items: [GIFPickerItem] = []
    @Published var isLoading: Bool = false
    @Published var error: String?
    @Published var activeProvider: Provider {
        didSet {
            Task {
                await loadFeatured()
            }
        }
    }

    private let nostrProvider: NostrGIFProvider
    private let tenorProvider: TenorGIFProvider
    private var loadTask: Task<Void, Never>?

    init(damusState: DamusState, defaultProvider: Provider = .nostr) {
        self.nostrProvider = NostrGIFProvider(damusState: damusState)
        self.tenorProvider = TenorGIFProvider()
        self.activeProvider = defaultProvider

        loadTask = Task {
            await loadFeatured()
        }
    }

    func loadFeatured() async {
        loadTask?.cancel()
        loadTask = Task {
            await fetchResults { [self] in
                switch self.activeProvider {
                case .nostr:
                    return try await self.nostrProvider.featured(limit: 30)
                case .tenor:
                    return try await self.tenorProvider.featured(limit: 30)
                }
            }
        }
        await loadTask?.value
    }

    func performSearch() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            await loadFeatured()
            return
        }

        loadTask?.cancel()
        loadTask = Task {
            await fetchResults { [self] in
                switch self.activeProvider {
                case .nostr:
                    return try await self.nostrProvider.search(query: trimmed, limit: 30)
                case .tenor:
                    return try await self.tenorProvider.search(query: trimmed, limit: 30)
                }
            }
        }
        await loadTask?.value
    }

    func clearSearch() {
        searchText = ""
        Task {
            await loadFeatured()
        }
    }

    private func fetchResults(
        _ producer: @escaping () async throws -> [GIFPickerItem]
    ) async {
        isLoading = true
        error = nil

        do {
            let results = try await producer()
            items = results
        } catch {
            items = []
            if Task.isCancelled { return }
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}
