//
//  CustomizeZapModel.swift
//  damus
//
//  Created by William Casarin on 2023-06-22.
//

import Foundation


class CustomizeZapModel: ObservableObject {
    @Published var comment: String = ""
    @Published var custom_amount: String = ""
    @Published var custom_amount_sats: Int? = nil
    @Published var zap_type: ZapType = .pub
    @Published var invoice: String = ""
    @Published var error: String? = nil
    @Published var zapping: Bool = false
    @Published var show_zap_types: Bool = false
    
    init() {
    }
    
    func set_defaults(settings: UserSettingsStore) {
        self.zap_type = settings.default_zap_type
        self.custom_amount = String(settings.default_zap_amount)
        self.custom_amount_sats = settings.default_zap_amount
    }
}
