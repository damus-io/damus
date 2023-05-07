//
//  SignalModel.swift
//  damus
//
//  Created by William Casarin on 2022-05-24.
//

import Foundation


class SignalModel: ObservableObject {
    @Published var signal: Int
    @Published var max_signal: Int
    
    init() {
        self.signal = 0
        self.max_signal = 0
    }
    
    init(signal: Int, max_signal: Int) {
        self.signal = signal
        self.max_signal = max_signal
    }
}
