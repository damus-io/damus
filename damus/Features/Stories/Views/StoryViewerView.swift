//
//  StoryViewerView.swift
//  damus
//
//  Created by William Casarin on 2026-05-11.
//

import SwiftUI
import Kingfisher

struct StoryViewerView: View {
    let damus_state: DamusState
    @StateObject private var model: StoryViewerModel

    init(damus_state: DamusState, stories: [Story], startAuthorIndex: Int, onDismiss: @escaping () -> Void) {
        self.damus_state = damus_state
        self._model = StateObject(wrappedValue: StoryViewerModel(stories: stories, startAuthorIndex: startAuthorIndex, onDismiss: onDismiss))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let story = model.currentStory, let slide = model.currentSlide {
                VStack(spacing: 0) {
                    progressBars(slides: story.slides)
                        .frame(height: 2.5)
                        .padding(.horizontal, 8)
                        .padding(.top, 8)

                    header(author: story.author)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)

                    Spacer()
                    slideImage(slide: slide)
                    Spacer()
                }
            }

            HStack(spacing: 0) {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.previousSlide() }
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { model.nextSlide() }
            }
        }
        .gesture(
            DragGesture()
                .onEnded { val in
                    let dy = val.translation.height
                    let dx = val.translation.width
                    if dy > 100 {
                        model.onDismiss()
                    } else if dx > 80 {
                        model.previousAuthor()
                    } else if dx < -80 {
                        model.nextAuthor()
                    }
                }
        )
        .task(id: "\(model.authorIndex)-\(model.slideIndex)") {
            await model.runCurrentSlide()
        }
        .statusBarHidden(true)
    }

    @ViewBuilder
    private func progressBars(slides: [StorySlide]) -> some View {
        HStack(spacing: 4) {
            ForEach(slides.indices, id: \.self) { i in
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.3))
                        Capsule()
                            .fill(Color.white)
                            .frame(width: geo.size.width * model.fillFraction(at: i))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func header(author: Pubkey) -> some View {
        HStack(spacing: 10) {
            ProfilePicView(
                pubkey: author,
                size: 32,
                highlight: .none,
                profiles: damus_state.profiles,
                disable_animation: damus_state.settings.disable_animation,
                damusState: damus_state
            )

            ProfileName(pubkey: author, damus: damus_state, show_nip5_domain: false)
                .foregroundColor(.white)

            Spacer()

            Button(action: model.onDismiss) {
                Image(systemName: "xmark")
                    .foregroundColor(.white)
                    .font(.title3)
                    .padding(6)
            }
        }
    }

    @ViewBuilder
    private func slideImage(slide: StorySlide) -> some View {
        KFAnimatedImage(slide.imeta.url)
            .imageContext(.note, disable_animation: damus_state.settings.disable_animation)
            .configure { view in
                view.framePreloadCount = 3
            }
            .scaledToFit()
    }
}
