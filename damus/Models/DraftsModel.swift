//
//  DraftsModel.swift
//  damus
//
//  Created by Terry Yiu on 2/12/23.
//

import Foundation

class DraftArtifacts {
    var content: NSMutableAttributedString
    var media: [UploadedMedia]
    
    init(content: NSMutableAttributedString = NSMutableAttributedString(string: ""), media: [UploadedMedia] = []) {
        self.content = content
        self.media = media
    }
}

class Drafts: ObservableObject {
    @Published var post: DraftArtifacts? = nil
    @Published var replies: [NostrEvent: DraftArtifacts] = [:]
    @Published var quotes: [NostrEvent: DraftArtifacts] = [:]
}
