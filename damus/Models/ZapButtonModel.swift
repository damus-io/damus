//
//  ZapButtonModel.swift
//  damus
//
//  Created by Terry Yiu on 6/1/23.
//

import Foundation

class ZapButtonModel: ObservableObject {
    var invoice: String? = nil
    @Published var zapping: String = ""
}
