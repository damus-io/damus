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
    let nip05: String?
    let picture: String?
    let lud06: String?
    let lud16: String?
}

func create_account_to_metadata(_ model: CreateAccountModel) -> NostrMetadata {
    return NostrMetadata(display_name: model.real_name, name: model.nick_name, about: model.about, website: nil, nip05: nil, picture: nil, lud06: nil, lud16: nil)
}
