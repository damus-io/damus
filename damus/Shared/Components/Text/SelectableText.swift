//
//  SelectableText.swift
//  damus
//
//  Created by Oleg Abalonski on 2/16/23.
//

import UIKit
import SwiftUI

struct SelectableText: View {
    let damus_state: DamusState
    let event: NostrEvent?
    let attributedString: AttributedString
    let textAlignment: NSTextAlignment
    @State private var selectedTextActionState: SelectedTextActionState = .hide
    @State private var selectedTextHeight: CGFloat = .zero
    @State private var selectedTextWidth: CGFloat = .zero

    let size: EventViewKind

    init(damus_state: DamusState, event: NostrEvent?, attributedString: AttributedString, textAlignment: NSTextAlignment? = nil, size: EventViewKind) {
        self.damus_state = damus_state
        self.event = event
        self.attributedString = attributedString
        self.textAlignment = textAlignment ?? NSTextAlignment.natural
        self.size = size
    }
    
    var body: some View {
        GeometryReader { geo in
            TextViewRepresentable(
                attributedString: attributedString,
                textColor: UIColor.label,
                font: eventviewsize_to_uifont(size),
                fixedWidth: selectedTextWidth,
                textAlignment: self.textAlignment,
                enableHighlighting: self.enableHighlighting(),
                postHighlight: { selectedText in
                    self.selectedTextActionState = .show_highlight_post_view(highlighted_text: selectedText)
                },
                muteWord: { selectedText in
                    self.selectedTextActionState = .show_mute_word_view(highlighted_text: selectedText)
                },
                saveCustomEmoji: { emoji in
                    Task { @MainActor in
                        let store = damus_state.custom_emojis
                        if store.isSaved(emoji) {
                            store.unsave(emoji)
                        } else {
                            store.save(emoji)
                        }
                        // Publish the updated emoji list
                        await publishEmojiList()
                    }
                },
                isCustomEmojiSaved: { emoji in
                    damus_state.custom_emojis.isSaved(emoji)
                },
                height: $selectedTextHeight
            )
            .padding([.leading, .trailing], -1.0)
            .onAppear {
                if geo.size.width == .zero {
                    self.selectedTextHeight = 1000.0
                } else {
                    self.selectedTextWidth = geo.size.width
                }
            }
            .onChange(of: geo.size) { newSize in
                self.selectedTextWidth = newSize.width
            }
        }
        .sheet(isPresented: Binding(get: {
            return self.selectedTextActionState.should_show_highlight_post_view()
        }, set: { newValue in
            self.selectedTextActionState = newValue ? .show_highlight_post_view(highlighted_text: self.selectedTextActionState.highlighted_text() ?? "") : .hide
        })) {
            if let event, case .show_highlight_post_view(let highlighted_text) = self.selectedTextActionState {
                PostView(
                    action: .highlighting(.init(selected_text: highlighted_text, source: .event(event.id))),
                    damus_state: damus_state
                )
                .presentationDragIndicator(.visible)
                .presentationDetents([.height(selectedTextHeight + 450), .medium, .large])
            }
        }
        .sheet(isPresented: Binding(get: {
            return self.selectedTextActionState.should_show_mute_word_view()
        }, set: { newValue in
            self.selectedTextActionState = newValue ? .show_mute_word_view(highlighted_text: self.selectedTextActionState.highlighted_text() ?? "") : .hide
        })) {
            if case .show_mute_word_view(let highlighted_text) = selectedTextActionState {
                AddMuteItemView(state: damus_state, new_text: .constant(highlighted_text))
                    .presentationDragIndicator(.visible)
                    .presentationDetents([.height(300), .medium, .large])
            }
        }
        .frame(height: selectedTextHeight)
    }
    
    func enableHighlighting() -> Bool {
        self.event != nil
    }

    /// Publishes the user's updated emoji list (kind 10030) to relays.
    private func publishEmojiList() async {
        guard let fullKeypair = damus_state.keypair.to_full() else { return }
        let emojis = await MainActor.run { damus_state.custom_emojis.sortedSavedEmojis }
        guard let event = damus_state.custom_emojis.createEmojiListEvent(keypair: fullKeypair, emojis: emojis) else { return }
        await damus_state.nostrNetwork.postbox.send(event)
    }
    
    enum SelectedTextActionState {
        case hide
        case show_highlight_post_view(highlighted_text: String)
        case show_mute_word_view(highlighted_text: String)
        
        func should_show_highlight_post_view() -> Bool {
            guard case .show_highlight_post_view = self else { return false }
            return true
        }
        
        func should_show_mute_word_view() -> Bool {
            guard case .show_mute_word_view = self else { return false }
            return true
        }
        
        func highlighted_text() -> String? {
            switch self {
                case .hide:
                    return nil
                case .show_mute_word_view(highlighted_text: let highlighted_text):
                    return highlighted_text
                case .show_highlight_post_view(highlighted_text: let highlighted_text):
                    return highlighted_text
            }
        }
    }
}

fileprivate class TextView: UITextView {
    var postHighlight: (String) -> Void
    var muteWord: (String) -> Void
    var saveCustomEmoji: ((CustomEmoji) -> Void)?
    var isCustomEmojiSaved: ((CustomEmoji) -> Bool)?
    private let enableHighlighting: Bool
    private var emojiMenuInteraction: UIContextMenuInteraction?

    init(frame: CGRect, textContainer: NSTextContainer?, postHighlight: @escaping (String) -> Void, muteWord: @escaping (String) -> Void, enableHighlighting: Bool) {
        self.postHighlight = postHighlight
        self.muteWord = muteWord
        self.enableHighlighting = enableHighlighting

        super.init(frame: frame, textContainer: textContainer)

        if enableHighlighting {
            self.delegate = self
        }

        // Add context menu interaction for custom emoji
        let interaction = UIContextMenuInteraction(delegate: self)
        self.addInteraction(interaction)
        self.emojiMenuInteraction = interaction
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Finds the CustomEmojiTextAttachment at the given point, if any.
    func customEmojiAttachment(at point: CGPoint) -> CustomEmojiTextAttachment? {
        guard let attributedText = self.attributedText else { return nil }

        // Convert point to text container coordinates
        let textContainerOffset = CGPoint(
            x: textContainerInset.left,
            y: textContainerInset.top
        )
        let locationInTextContainer = CGPoint(
            x: point.x - textContainerOffset.x,
            y: point.y - textContainerOffset.y
        )

        // Find the character index at this point
        let characterIndex = layoutManager.characterIndex(
            for: locationInTextContainer,
            in: textContainer,
            fractionOfDistanceBetweenInsertionPoints: nil
        )

        guard characterIndex < attributedText.length else { return nil }

        // Check if there's an attachment at this character
        let attachment = attributedText.attribute(.attachment, at: characterIndex, effectiveRange: nil)
        return attachment as? CustomEmojiTextAttachment
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(highlightText(_:)) {
            return true
        }
        
        if action == #selector(muteText(_:)) {
            return true
        }
        
        return super.canPerformAction(action, withSender: sender)
    }
    
    private func getSelectedText() -> String? {
        guard let selectedRange = self.selectedTextRange else { return nil }
        return self.text(in: selectedRange)
    }

    @objc private func highlightText(_ sender: Any?) {
        guard let selectedText = self.getSelectedText() else { return }
        self.postHighlight(selectedText)
    }
    
    @objc private func muteText(_ sender: Any?) {
        guard let selectedText = self.getSelectedText() else { return }
        self.muteWord(selectedText)
    }

}

extension TextView: UITextViewDelegate {
    func textView(_ textView: UITextView, editMenuForTextIn range: NSRange, suggestedActions: [UIMenuElement]) -> UIMenu? {
        guard enableHighlighting,
              let selectedTextRange = self.selectedTextRange,
              let selectedText = self.text(in: selectedTextRange),
              !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let highlightAction = UIAction(title: NSLocalizedString("Highlight", comment: "Context menu action to highlight the selected text as context to draft a new note."), image: UIImage(systemName: "highlighter")) { [weak self] _ in
            self?.postHighlight(selectedText)
        }

        let muteAction = UIAction(title: NSLocalizedString("Mute", comment: "Context menu action to mute the selected word."), image: UIImage(systemName: "speaker.slash")) { [weak self] _ in
            self?.muteWord(selectedText)
        }

        return UIMenu(children: suggestedActions + [highlightAction, muteAction])
    }
}

// MARK: - UIContextMenuInteractionDelegate

extension TextView: UIContextMenuInteractionDelegate {
    /// Provides a context menu when long-pressing on a custom emoji.
    ///
    /// Shows options to copy the emoji image and save/remove from the user's collection.
    func contextMenuInteraction(_ interaction: UIContextMenuInteraction, configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
        guard let emojiAttachment = customEmojiAttachment(at: location) else { return nil }

        let emoji = emojiAttachment.emoji
        let isSaved = isCustomEmojiSaved?(emoji) ?? false

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] _ in
            var actions: [UIMenuElement] = []

            if let image = emojiAttachment.image {
                actions.append(self?.makeCopyImageAction(image: image) ?? UIAction(title: "") { _ in })
            }

            actions.append(self?.makeSaveEmojiAction(emoji: emoji, isSaved: isSaved) ?? UIAction(title: "") { _ in })

            return UIMenu(title: ":\(emoji.shortcode):", children: actions)
        }
    }

    /// Creates an action to copy the emoji image to clipboard.
    private func makeCopyImageAction(image: UIImage) -> UIAction {
        UIAction(
            title: NSLocalizedString("Copy Image", comment: "Context menu action to copy an image"),
            image: UIImage(systemName: "doc.on.doc")
        ) { _ in
            UIPasteboard.general.image = image
        }
    }

    /// Creates an action to save or remove the emoji from the user's collection.
    private func makeSaveEmojiAction(emoji: CustomEmoji, isSaved: Bool) -> UIAction {
        let title = isSaved
            ? NSLocalizedString("Remove from My Emojis", comment: "Context menu action to remove a custom emoji from saved collection")
            : NSLocalizedString("Save to My Emojis", comment: "Context menu action to save a custom emoji to collection")
        let imageName = isSaved ? "star.slash" : "star"
        let attributes: UIMenuElement.Attributes = isSaved ? .destructive : []

        return UIAction(title: title, image: UIImage(systemName: imageName), attributes: attributes) { [weak self] _ in
            self?.saveCustomEmoji?(emoji)
        }
    }
}

fileprivate struct TextViewRepresentable: UIViewRepresentable {

    let attributedString: AttributedString
    let textColor: UIColor
    let font: UIFont
    let fixedWidth: CGFloat
    let textAlignment: NSTextAlignment
    let enableHighlighting: Bool
    let postHighlight: (String) -> Void
    let muteWord: (String) -> Void
    let saveCustomEmoji: ((CustomEmoji) -> Void)?
    let isCustomEmojiSaved: ((CustomEmoji) -> Bool)?
    @Binding var height: CGFloat

    func makeUIView(context: UIViewRepresentableContext<Self>) -> TextView {
        let view = TextView(frame: .zero, textContainer: nil, postHighlight: postHighlight, muteWord: muteWord, enableHighlighting: enableHighlighting)
        view.isEditable = false
        view.dataDetectorTypes = .all
        view.isSelectable = true
        view.backgroundColor = .clear
        view.textContainer.lineFragmentPadding = 0
        view.textContainerInset = .zero
        view.textContainerInset.left = 1.0
        view.textContainerInset.right = 1.0
        view.textAlignment = textAlignment
        view.saveCustomEmoji = saveCustomEmoji
        view.isCustomEmojiSaved = isCustomEmojiSaved

        return view
    }

    func updateUIView(_ uiView: TextView, context: UIViewRepresentableContext<Self>) {
        let mutableAttributedString = createNSAttributedString()
        uiView.attributedText = mutableAttributedString
        uiView.textAlignment = self.textAlignment
        uiView.saveCustomEmoji = saveCustomEmoji
        uiView.isCustomEmojiSaved = isCustomEmojiSaved

        let newHeight = mutableAttributedString.height(containerWidth: fixedWidth)

        DispatchQueue.main.async {
            height = newHeight
        }
    }

    func createNSAttributedString() -> NSMutableAttributedString {
        let mutableAttributedString = NSMutableAttributedString(attributedString)
        let fullRange = NSRange(location: 0, length: mutableAttributedString.length)

        // Apply font to entire range
        mutableAttributedString.addAttribute(.font, value: font, range: fullRange)

        // Apply default foreground color only to ranges that don't already have one
        mutableAttributedString.enumerateAttribute(
            .foregroundColor,
            in: fullRange,
            options: []
        ) { value, range, _ in
            if value == nil {
                mutableAttributedString.addAttribute(.foregroundColor, value: textColor, range: range)
            }
        }

        return mutableAttributedString
    }
}

fileprivate extension NSAttributedString {

    func height(containerWidth: CGFloat) -> CGFloat {

        let rect = self.boundingRect(
            with: CGSize.init(width: containerWidth, height: CGFloat.greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil
        )

        return ceil(rect.size.height)
    }
}
