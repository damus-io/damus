//
//  ConnectivitySignalEnvironment.swift
//  damus
//
//  Created by OpenAI Codex on 2025-01-04.
//

import SwiftUI

private struct ConnectivitySignalKey: EnvironmentKey {
    static let defaultValue: SignalModel? = nil
}

extension EnvironmentValues {
    var connectivitySignal: SignalModel? {
        get { self[ConnectivitySignalKey.self] }
        set { self[ConnectivitySignalKey.self] = newValue }
    }
}
