//
//  RelayModels.swift
//  damus
//
//  Created by Bryan Montz on 6/10/23.
//

import Foundation

final class RelayModelCache: ObservableObject {
    private var models = [RelayURL: RelayModel]()
    
    func model(withURL url: RelayURL) -> RelayModel? {
        models[url]
    }

    func model(with_relay_id url_string: RelayURL) -> RelayModel? {
        return model(withURL: url_string)
    }

    func insert(model: RelayModel) {
        models[model.url] = model
        objectWillChange.send()
    }
}
