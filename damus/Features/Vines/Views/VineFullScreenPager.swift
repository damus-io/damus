//
//  VineFullScreenPager.swift
//  damus
//
//  Extracted from PostingTimelineView.swift on 2026-02-10.
//

import SwiftUI

/// Vertical-swipe pager that wraps a rotated `TabView` for full-screen Vine playback.
struct VineFullScreenPager: View {
    @ObservedObject var model: VineFeedModel
    let damus_state: DamusState
    let onClose: () -> Void
    @State private var selection: Int

    init(model: VineFeedModel, damus_state: DamusState, initialIndex: Int, onClose: @escaping () -> Void) {
        self._model = ObservedObject(wrappedValue: model)
        self.damus_state = damus_state
        self._selection = State(initialValue: initialIndex)
        self.onClose = onClose
    }

    var body: some View {
        GeometryReader { geo in
            TabView(selection: $selection) {
                ForEach(Array(model.vines.enumerated()), id: \.1.id) { index, vine in
                    VineFullScreenPage(vine: vine, damus_state: damus_state)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .rotationEffect(.degrees(-90))
                        .tag(index)
                }
            }
            .frame(width: geo.size.height, height: geo.size.width)
            .rotationEffect(.degrees(90))
            .tabViewStyle(.page(indexDisplayMode: .never))
            .offset(x: (geo.size.width - geo.size.height) / 2, y: (geo.size.height - geo.size.width) / 2)
        }
        .background(Color.black.ignoresSafeArea())
        .environment(\.view_layer_context, .full_screen_layer)
        .overlay(alignment: .topTrailing) {
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(.white)
                    .padding()
            }
            .accessibilityLabel(Text(NSLocalizedString("Close", comment: "Close button label for Vine full-screen player.")))
        }
        .onAppear {
            model.noteAppeared(at: selection)
        }
        .onChange(of: selection) { idx in
            model.noteAppeared(at: idx)
        }
    }
}
