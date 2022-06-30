//
//  DirectMessagesModel.swift
//  damus
//
//  Created by William Casarin on 2022-06-29.
//

import Foundation

class DirectMessagesModel: ObservableObject {
    @Published var events: [(String, [NostrEvent])] = []
    @Published var loading: Bool = false
    
    
}
