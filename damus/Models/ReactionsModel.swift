//
//  LikesModel.swift
//  damus
//
//  Created by William Casarin on 2023-01-11.
//

import Foundation


final class ReactionsModel: EventsModel {
    
    init(state: DamusState, target: String) {
        super.init(state: state, target: target, kind: .like)
    }
}
