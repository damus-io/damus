//
//  GIFPickerView.swift
//  damus
//
//  GIF picker interface for selecting GIFs from Nostr or Tenor.
//

import SwiftUI
import Kingfisher

struct GIFPickerView: View {
    @StateObject private var viewModel: GIFPickerViewModel
    @Environment(\.dismiss) var dismiss

    let onSelect: (GIFPickerItem) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    init(damusState: DamusState, onSelect: @escaping (GIFPickerItem) -> Void) {
        _viewModel = StateObject(wrappedValue: GIFPickerViewModel(damusState: damusState))
        self.onSelect = onSelect
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                providerPicker
                    .padding(.top, 12)
                    .padding(.horizontal)
                searchBar

                if let error = viewModel.error {
                    Text(error)
                        .foregroundColor(.red)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                if viewModel.isLoading && viewModel.items.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        if viewModel.items.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 42))
                                    .foregroundColor(.secondary)
                                Text("No GIFs found")
                                    .font(.footnote)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, minHeight: 200)
                            .padding()
                        } else {
                            LazyVGrid(columns: columns, spacing: 8) {
                                ForEach(viewModel.items) { item in
                                    GIFCell(item: item) {
                                        onSelect(item)
                                        dismiss()
                                    }
                                }
                            }
                            .padding(8)
                        }
                    }
                }
            }
            .navigationTitle("Select GIF")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var providerPicker: some View {
        Picker("Provider", selection: $viewModel.activeProvider) {
            ForEach(GIFPickerViewModel.Provider.allCases) { provider in
                Text(provider.title).tag(provider)
            }
        }
        .pickerStyle(.segmented)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)

            TextField("Search GIFs...", text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .autocapitalization(.none)
                .disableAutocorrection(true)
                .onSubmit {
                    Task {
                        await viewModel.performSearch()
                    }
                }

            if !viewModel.searchText.isEmpty {
                Button(action: {
                    viewModel.clearSearch()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.gray)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

private struct GIFCell: View {
    let item: GIFPickerItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            if let previewURL = item.previewURL {
                KFAnimatedImage(previewURL)
                    .imageContext(.note, disable_animation: false)
                    .configure { view in
                        view.framePreloadCount = 3
                    }
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .clipped()
                    .cornerRadius(8)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 150)
                    .cornerRadius(8)
                    .overlay(
                        VStack(spacing: 6) {
                            Image(systemName: "photo")
                                .foregroundColor(.gray)
                            Text(item.displayTitle)
                                .font(.caption)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.gray)
                        }
                        .padding(8)
                    )
            }
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomLeading) {
            if let attribution = item.attribution {
                Text(attribution)
                    .font(.caption2)
                    .padding(4)
                    .background(Color.black.opacity(0.5))
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .padding(6)
            }
        }
    }
}

#Preview {
    GIFPickerView(damusState: test_damus_state) { item in
        print("Selected: \(item.displayTitle)")
    }
}
