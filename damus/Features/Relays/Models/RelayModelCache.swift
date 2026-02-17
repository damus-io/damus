//
//  RelayModels.swift
//  damus
//
//  Created by Bryan Montz on 6/10/23.
//

import Foundation

/// Stores information, metadata, and logs about different relays. Generally used as a singleton.
///
/// # Discussion
///
/// This class is primarily used as a shared singleton in `DamusState`, to allow other parts of the app to access information, metadata, and logs about relays without having to fetch it themselves.
///
/// For example, it is used by `RelayView` to supplement information about the relay without having to fetch those again from the network, as well as to display logs collected throughout the use of the app.
final class RelayModelCache: ObservableObject {
    private var models = [RelayURL: RelayModel]()
    private let lock = NSLock()

    func model(withURL url: RelayURL) -> RelayModel? {
        lock.lock()
        defer { lock.unlock() }
        return models[url]
    }

    func model(with_relay_id url_string: RelayURL) -> RelayModel? {
        return model(withURL: url_string)
    }

    func insert(model: RelayModel) {
        lock.lock()
        models[model.url] = model
        lock.unlock()
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
}
