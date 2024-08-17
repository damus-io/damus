//
//  DraftsModel.swift
//  damus
//
//  Created by Terry Yiu on 2/12/23.
//

import Foundation

class DraftArtifacts: Equatable {
    var content: NSMutableAttributedString
    var media: [UploadedMedia]
    
    init(content: NSMutableAttributedString = NSMutableAttributedString(string: ""), media: [UploadedMedia] = []) {
        self.content = content
        self.media = media
    }
    
    static func == (lhs: DraftArtifacts, rhs: DraftArtifacts) -> Bool {
        return (
            lhs.media == rhs.media &&
            lhs.content.string == rhs.content.string    // Comparing the text content is not perfect but acceptable in this case because attributes for our post editor are determined purely from text content
        )
    }
}

class Drafts: ObservableObject {
    @Published var post: DraftArtifacts? = nil
    @Published var replies: [NostrEvent: DraftArtifacts] = [:]
    @Published var quotes: [NostrEvent: DraftArtifacts] = [:]
    @Published var highlights: [HighlightSource: DraftArtifacts] = [:]
}
