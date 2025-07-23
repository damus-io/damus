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
    
    init(signal: Int = 0, max_signal: Int = 0) {
        self.signal = signal
        self.max_signal = max_signal
    }
}
