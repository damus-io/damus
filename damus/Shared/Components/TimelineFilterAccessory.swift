//
//  TimelineFilterAccessory.swift
//  damus
//

import SwiftUI

/// One timeline tab's filter selector: its labelled options, paired with a
/// binding to the state they drive.
///
/// The accessory attaches to the `TabView`, which lives in ``ContentView``, but
/// each filter's state belongs to a tab root. ``ContentView`` therefore hoists
/// the three filter states and describes the selected tab's filter as one of
/// these cases, which is all the accessory needs in order to draw the right
/// control for whichever tab is showing.
///
/// The cases wrap bindings of three unrelated enums, which is why this is an
/// enum and not a generic: the accessory switches once, then hands each case to
/// the same generic control.
enum TimelineFilterSelection {
    case notes(Binding<FilterState>)
    case dms(Binding<DMType>)
    case notifications(Binding<NotificationFilterState>)
}

/// The timeline filter selector, as the tab view's bottom Liquid Glass accessory.
///
/// This is the iOS 26 home for the filter that pre-26 sits in a ``CustomPicker``
/// at the top of the tab: putting it down beside the tab bar means changing
/// filter no longer means reaching all the way to the top of the screen. Exactly
/// one of the two is ever on screen — see
/// ``timelineFilterLivesInTabViewAccessory``.
///
/// Reached through ``SwiftUI/View/timelineFilterAccessory(_:)``, which owns the
/// `#available` guard. This type is iOS 26-only because
/// `@Environment(\.tabViewBottomAccessoryPlacement)` is.
@available(iOS 26.0, *)
struct TimelineFilterAccessory: View {
    let filter: TimelineFilterSelection

    var body: some View {
        switch filter {
        case .notes(let selection):
            TimelineFilterAccessoryControl(options: FilterState.timeline_filter_options, selection: selection)
        case .dms(let selection):
            TimelineFilterAccessoryControl(options: DMType.timeline_filter_options, selection: selection)
        case .notifications(let selection):
            TimelineFilterAccessoryControl(options: NotificationFilterState.timeline_filter_options, selection: selection)
        }
    }
}

/// The control the accessory draws, for any of the filter enums.
///
/// The accessory gets two placements and has to render for both, because
/// `.tabBarMinimizeBehavior(.onScrollDown)` is applied to the same `TabView` and
/// so normal scrolling hits each of them:
///
/// - `.expanded` — the accessory has a full-width row of its own above the tab
///   bar, which is room to show every option at once.
/// - `.inline` — the tab bar has minimized on scroll and the accessory shares
///   that row with it, leaving room for little more than the current option, so
///   a menu keeps the others one tap away.
///
/// A `nil` placement means the environment has no opinion, which we treat as the
/// full-width case.
@available(iOS 26.0, *)
private struct TimelineFilterAccessoryControl<Selection: Hashable>: View {
    let options: [(String, Selection)]
    @Binding var selection: Selection
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement

    var body: some View {
        switch placement {
        case .inline:
            Menu {
                Picker(Self.control_label, selection: $selection) {
                    ForEach(self.options, id: \.1) { (label, option) in
                        Text(label).tag(option)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Text(self.selected_label)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                }
            }
            .accessibilityLabel(Self.control_label)
            .accessibilityIdentifier(AppAccessibilityIdentifiers.main_timeline_filter_accessory.rawValue)
        default:
            HStack(spacing: 4) {
                ForEach(self.options, id: \.1) { (label, option) in
                    self.option_button(label: label, option: option)
                }
            }
            .padding(.horizontal, 6)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Self.control_label)
            .accessibilityIdentifier(AppAccessibilityIdentifiers.main_timeline_filter_accessory.rawValue)
        }
    }

    /// One option in the expanded placement.
    ///
    /// Deliberately not a segmented `Picker`: the accessory is already a glass
    /// capsule, and a segmented control brings a track of its own, which reads as
    /// a pill inside a pill directly above the tab bar's. Selected-behind-a-soft-
    /// capsule is what the tab bar right below does, so the two rows match.
    private func option_button(label: String, option: Selection) -> some View {
        let selected = option == self.selection

        return Button {
            self.selection = option
        } label: {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(selected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background {
                    if selected {
                        Capsule().fill(.quaternary)
                    }
                }
        }
        .buttonStyle(.plain)
        // A hand-rolled control has to say what a `Picker` would say for itself,
        // so VoiceOver announces the current filter and not just four buttons.
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    /// The label of the selected option, which is all the inline placement shows.
    private var selected_label: String {
        self.options.first(where: { $0.1 == self.selection })?.0 ?? ""
    }

    private static var control_label: String {
        NSLocalizedString("Timeline filter", comment: "Accessibility label for the control that filters what a timeline shows.")
    }
}
