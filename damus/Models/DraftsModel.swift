//
//  DraftsModel.swift
//  damus
//
//  Created by Terry Yiu on 2/12/23.
//

import Foundation

class Drafts: ObservableObject {
    @Published var post: String = ""
    @Published var replies: [NostrEvent: String] = [:]
}
