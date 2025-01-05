//
//  PresentFullScreenItemNotify.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-11-01.
//

struct PresentFullScreenItemNotify: Notify {
    typealias Payload = FullScreenItem
    var payload: Payload
}

extension NotifyHandler {
    static var present_full_screen_item: NotifyHandler<PresentFullScreenItemNotify> {
        .init()
    }
}

extension Notifications {
    static func present_full_screen_item(_ item: FullScreenItem) -> Notifications<PresentFullScreenItemNotify> {
        .init(.init(payload: item))
    }
}

/// Tell the app to present an item in full screen. Use this when presenting items coming from a timeline or any lazy stack.
///
/// ## Usage notes
///
/// Use this instead of `.damus_full_screen_cover` when the source view is on a lazy stack or timeline.
///
/// The reason is that when using a full screen modifier in those scenarios, the full screen view may abruptly disappear.
/// One example is when showing videos from the timeline in full screen, where changing the orientation of the device (landscape/portrait)
/// can cause the source view to be unloaded by the lazy stack, making your full screen overlay to simply disappear, causing a feeling of flakiness to the app
///
/// ## Implementation notes
///
/// The requests from this function will be received and handled at the top level app view (`ContentView`), which contains a `.damus_full_screen_cover`.
///
func present(full_screen_item: FullScreenItem) {
    notify(.present_full_screen_item(full_screen_item))
}

