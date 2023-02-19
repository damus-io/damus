//
//  RepostsModel.swift
//  damus
//
//  Created by Terry Yiu on 1/22/23.
//

import Foundation

final class RepostsModel: EventsModel {
    
    init(state: DamusState, target: String) {
        super.init(state: state, target: target, kind: .boost)
    }
}
