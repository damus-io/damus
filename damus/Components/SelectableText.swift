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
    
    enum SelectedTextActionState {
        case hide
        case show_highlight_post_view(highlighted_text: String)
        case show_mute_word_view(highlighted_text: String)
        
        func should_show_highlight_post_view() -> Bool {
            guard case .show_highlight_post_view(let highlighted_text) = self else { return false }
            return true
        }
        
        func should_show_mute_word_view() -> Bool {
            guard case .show_mute_word_view(let highlighted_text) = self else { return false }
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

    init(frame: CGRect, textContainer: NSTextContainer?, postHighlight: @escaping (String) -> Void, muteWord: @escaping (String) -> Void) {
        self.postHighlight = postHighlight
        self.muteWord = muteWord
        super.init(frame: frame, textContainer: textContainer)
    }

    required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
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
    
    func getSelectedText() -> String? {
        guard let selectedRange = self.selectedTextRange else { return nil }
        return self.text(in: selectedRange)
    }

    @objc public func highlightText(_ sender: Any?) {
        guard let selectedText = self.getSelectedText() else { return }
        self.postHighlight(selectedText)
    }
    
    @objc public func muteText(_ sender: Any?) {
        guard let selectedText = self.getSelectedText() else { return }
        self.muteWord(selectedText)
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
    @Binding var height: CGFloat

    func makeUIView(context: UIViewRepresentableContext<Self>) -> TextView {
        let view = TextView(frame: .zero, textContainer: nil, postHighlight: postHighlight, muteWord: muteWord)
        view.isEditable = false
        view.dataDetectorTypes = .all
        view.isSelectable = true
        view.backgroundColor = .clear
        view.textContainer.lineFragmentPadding = 0
        view.textContainerInset = .zero
        view.textContainerInset.left = 1.0
        view.textContainerInset.right = 1.0
        view.textAlignment = textAlignment

        let menuController = UIMenuController.shared
        let highlightItem = UIMenuItem(title: "Highlight", action: #selector(view.highlightText(_:)))
        let muteItem = UIMenuItem(title: "Mute", action: #selector(view.muteText(_:)))
        menuController.menuItems = self.enableHighlighting ? [highlightItem, muteItem] : []

        return view
    }

    func updateUIView(_ uiView: TextView, context: UIViewRepresentableContext<Self>) {
        let mutableAttributedString = createNSAttributedString()
        uiView.attributedText = mutableAttributedString
        uiView.textAlignment = self.textAlignment

        let newHeight = mutableAttributedString.height(containerWidth: fixedWidth)

        DispatchQueue.main.async {
            height = newHeight
        }
    }

    func createNSAttributedString() -> NSMutableAttributedString {
        let mutableAttributedString = NSMutableAttributedString(attributedString)
        let myAttribute = [
            NSAttributedString.Key.font: font,
            NSAttributedString.Key.foregroundColor: textColor
        ]

        mutableAttributedString.addAttributes(
            myAttribute,
            range: NSRange.init(location: 0, length: mutableAttributedString.length)
        )

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
