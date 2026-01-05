//
//  LongformPreview.swift
//  damus
//
//  Created by William Casarin on 2023-06-01.
//

import SwiftUI
import Kingfisher

struct LongformPreviewBody: View {
    let state: DamusState
    let event: LongformEvent
    let options: EventViewOptions
    let header: Bool
    let sepiaEnabled: Bool
    @State var blur_images: Bool = true

    @ObservedObject var artifacts: NoteArtifactsModel
    @Environment(\.colorScheme) var colorScheme

    init(state: DamusState, ev: LongformEvent, options: EventViewOptions, header: Bool, sepiaEnabled: Bool = false) {
        self.state = state
        self.event = ev
        self.options = options
        self.header = header
        self.sepiaEnabled = sepiaEnabled

        self._artifacts = ObservedObject(wrappedValue: state.events.get_cache_data(ev.event.id).artifacts_model)
    }

    init(state: DamusState, ev: NostrEvent, options: EventViewOptions, header: Bool, sepiaEnabled: Bool = false) {
        self.state = state
        self.event = LongformEvent.parse(from: ev)
        self.options = options
        self.header = header
        self.sepiaEnabled = sepiaEnabled

        self._artifacts = ObservedObject(wrappedValue: state.events.get_cache_data(ev.id).artifacts_model)
    }

    /// Formats word count for display.
    func Words(_ words: Int) -> Text {
        let wordCount = pluralizedString(key: "word_count", count: words)
        return Text(wordCount)
    }

    /// Formats estimated read time for display.
    func ReadTime(_ minutes: Int) -> Text {
        let readTime = pluralizedString(key: "read_time", count: minutes)
        return Text(readTime)
    }
    
    var truncate: Bool {
        return options.contains(.truncate_content)
    }
    
    var truncate_very_short: Bool {
        return options.contains(.truncate_content_very_short)
    }
    
    func truncatedText(content: CompatibleText) -> some View {
        Group {
            if truncate_very_short {
                TruncatedText(text: content, maxChars: 140, show_show_more_button: !options.contains(.no_show_more))
                    .font(header ? .body : .caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 10)
            }
            else if truncate {
                TruncatedText(text: content, show_show_more_button: !options.contains(.no_show_more))
                    .font(header ? .body : .caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 10)
            } else {
                content.text
                    .font(header ? .body : .caption)
                    .foregroundColor(.gray)
                    .padding(.horizontal, 10)
            }
        }
    }
    
    func Placeholder(url: URL) -> some View {
        Group {
            if let meta = state.events.lookup_img_metadata(url: url),
               case .processed(let blurhash) = meta.state {
                Image(uiImage: blurhash)
                    .resizable()
                    .frame(maxWidth: .infinity, maxHeight: header ? .infinity : 150)
            } else {
                DamusColors.adaptableWhite
            }
        }
    }
    
    func titleImage(url: URL) -> some View {
        KFAnimatedImage(url)
            .callbackQueue(.dispatch(.global(qos:.background)))
            .backgroundDecode(true)
            .imageContext(.note, disable_animation: state.settings.disable_animation)
            .image_fade(duration: 0.25)
            .cancelOnDisappear(true)
            .configure { view in
                view.framePreloadCount = 3
            }
            .background {
                Placeholder(url: url)
            }
            .aspectRatio(contentMode: .fill)
            .frame(maxWidth: .infinity, maxHeight: header ? .infinity : 150)
            .kfClickable()
            .cornerRadius(1)
    }

    var body: some View {
        // In full article view with sepia, wrap in full-width container for seamless background
        let fullWidthSepia = !truncate && sepiaEnabled

        if fullWidthSepia {
            // Full-width sepia background container
            MainContent
                .padding(.horizontal)
                .frame(maxWidth: .infinity)
                .background(DamusColors.sepiaBackground(for: colorScheme))
                .foregroundStyle(DamusColors.sepiaText(for: colorScheme))
        } else {
            Group {
                if options.contains(.wide) {
                    Main.padding(.horizontal)
                } else {
                    Main
                }
            }
        }
    }

    /// Content without card styling - for use in full-width sepia container
    var MainContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let url = event.image {
                if (self.options.contains(.no_media)) {
                    EmptyView()
                } else if !blur_images || (!blur_images && !state.settings.media_previews) {
                    titleImage(url: url)
                } else if blur_images || (blur_images && !state.settings.media_previews) {
                    ZStack {
                        titleImage(url: url)
                        BlurOverlayView(blur_images: $blur_images, artifacts: nil, size: nil, damus_state: nil, parentView: .longFormView)
                    }
                }
            }

            Text(event.title ?? NSLocalizedString("Untitled", comment: "Title of longform event if it is untitled."))
                .font(header ? .title : .headline)
                .padding(.horizontal, 10)
                .padding(.top, 5)

            if let summary = event.summary {
                truncatedText(content: CompatibleText(stringLiteral: summary))
            }

            if let labels = event.labels {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(labels, id: \.self) { label in
                            Text(label)
                                .font(.caption)
                                .foregroundColor(DamusColors.sepiaText(for: colorScheme).opacity(0.7))
                                .padding(EdgeInsets(top: 5, leading: 15, bottom: 5, trailing: 15))
                                .background(DamusColors.sepiaText(for: colorScheme).opacity(0.1))
                                .cornerRadius(20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(DamusColors.sepiaText(for: colorScheme).opacity(0.3), lineWidth: 1)
                                )
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .padding(10)
            }

            if case .loaded(let arts) = artifacts.state,
               case .longform(let longform) = arts
            {
                HStack(spacing: 8) {
                    ReadTime(longform.estimatedReadTimeMinutes)
                    Text("·")
                    Words(longform.words)
                }
                .font(.footnote)
                .foregroundColor(.gray)
                .padding([.horizontal, .bottom], 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var Main: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let url = event.image {
                if (self.options.contains(.no_media)) {
                    EmptyView()
                } else if !blur_images || (!blur_images && !state.settings.media_previews) {
                    titleImage(url: url)
                } else if blur_images || (blur_images && !state.settings.media_previews) {
                    ZStack {
                        titleImage(url: url)
                        BlurOverlayView(blur_images: $blur_images, artifacts: nil, size: nil, damus_state: nil, parentView: .longFormView)
                    }
                }
            }
            
            Text(event.title ?? NSLocalizedString("Untitled", comment: "Title of longform event if it is untitled."))
                .font(header ? .title : .headline)
                .padding(.horizontal, 10)
                .padding(.top, 5)
            
            if let summary = event.summary {
                truncatedText(content: CompatibleText(stringLiteral: summary))
            }
            
            if let labels = event.labels {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(labels, id: \.self) { label in
                            // In full article view with sepia, use subtle sepia-tinted tag styling
                            let useSepiaTags = !truncate && sepiaEnabled
                            Text(label)
                                .font(.caption)
                                .foregroundColor(useSepiaTags ? DamusColors.sepiaText(for: colorScheme).opacity(0.7) : .gray)
                                .padding(EdgeInsets(top: 5, leading: 15, bottom: 5, trailing: 15))
                                .background(useSepiaTags ? DamusColors.sepiaText(for: colorScheme).opacity(0.1) : DamusColors.neutral1)
                                .cornerRadius(20)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 20)
                                        .stroke(useSepiaTags ? DamusColors.sepiaText(for: colorScheme).opacity(0.3) : DamusColors.neutral3, lineWidth: 1)
                                )
                        }
                    }
                }
                .scrollIndicators(.hidden)
                .padding(10)
            }

            
            if case .loaded(let arts) = artifacts.state,
               case .longform(let longform) = arts
            {
                HStack(spacing: 8) {
                    ReadTime(longform.estimatedReadTimeMinutes)
                    Text("·")
                    Words(longform.words)
                }
                .font(.footnote)
                .foregroundColor(.gray)
                .padding([.horizontal, .bottom], 10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        // Only show card styling when content is truncated (preview mode)
        // In full article view, use sepia background if enabled, otherwise clear
        .background(truncate ? DamusColors.neutral3 : (sepiaEnabled ? DamusColors.sepiaBackground(for: colorScheme) : Color.clear))
        .foregroundStyle(truncate ? Color.primary : (sepiaEnabled ? DamusColors.sepiaText(for: colorScheme) : Color.primary))
        .cornerRadius(truncate ? 10 : 0)
        .overlay(
            truncate ?
                RoundedRectangle(cornerRadius: 10)
                    .stroke(DamusColors.neutral1, lineWidth: 1)
                : nil
        )
        .padding(.top, truncate ? 10 : 0)
        .onAppear {
            blur_images = should_blur_images(settings: state.settings, contacts: state.contacts, ev: event.event, our_pubkey: state.pubkey)
        }
    }
}

struct LongformPreview: View {
    let state: DamusState
    let event: LongformEvent
    let options: EventViewOptions

    init(state: DamusState, ev: NostrEvent, options: EventViewOptions) {
        self.state = state
        self.event = LongformEvent.parse(from: ev)
        self.options = options.union(.no_mentions)
    }

    var body: some View {
        EventShell(state: state, event: event.event, options: options) {
            LongformPreviewBody(state: state, ev: event, options: options, header: false)
        }
    }
}

struct LongformPreview_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            LongformPreview(state: test_damus_state, ev: test_longform_event.event, options: [])

            LongformPreview(state: test_damus_state, ev: test_longform_event.event, options: [.wide])
        }
        .frame(height: 400)
    }
}
