//
//  RelayModels.swift
//  damus
//
//  Created by Bryan Montz on 6/10/23.
//

import Foundation

final class RelayModelCache {
    private var models = Set<RelayModel>()
    
    func model(withURL url: URL) -> RelayModel? {
        models.first(where: { model in model.url == url })
    }
    
    func model(with_relay_id url_string: String) -> RelayModel? {
        guard let url = RelayURL(url_string) else {
            return nil
        }
        return model(withURL: url.url)
    }
    
    func insert(model: RelayModel) {
        if let matching_model = self.model(withURL: model.url) {
            models.remove(matching_model)
        }
        models.insert(model)
    }
}
