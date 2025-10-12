//
//  PollEventViewFactory.swift
//  damus
//
//  Created by ChatGPT on 2025-04-11.
//

import SwiftUI

extension PollEventViewFactory {
    static func registerAppBuilder() {
        builder = { damus, event, poll, options in
            AnyView(PollEventView(damus: damus, event: event, poll: poll, options: options))
        }
    }
}
