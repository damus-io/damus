//
//  NostrMetadata.swift
//  damus
//
//  Created by William Casarin on 2022-05-21.
//

import Foundation


struct NostrMetadata: Codable {
    let display_name: String?
    let name: String?
    let about: String?
    let website: String?
    let picture: String?
}

func account_to_metadata(_ model: AccountModel) -> NostrMetadata {
    return NostrMetadata(display_name: model.real_name, name: model.nick_name, about: model.about, website: model.picture, picture: model.picture)
}
