//
//  NostrEvent+.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-17.
//

import Foundation

func make_zap_request_event(keypair: FullKeypair, content: String, relays: [RelayDescriptor], target: ZapTarget, zap_type: ZapType) -> MakeZapRequest? {
    var tags = zap_target_to_tags(target)
    var relay_tag = ["relays"]
    relay_tag.append(contentsOf: relays.map { $0.url.id })
    tags.append(relay_tag)
    
    var kp = keypair
    
    let now = UInt32(Date().timeIntervalSince1970)

    var privzap_req: PrivateZapRequest?
    
    var message = content
    switch zap_type {
    case .pub:
        break
    case .non_zap:
        break
    case .anon:
        tags.append(["anon"])
        kp = generate_new_keypair()
    case .priv:
        guard let priv_kp = generate_private_keypair(our_privkey: keypair.privkey, id: NoteId(target.id), created_at: now) else {
            return nil
        }
        kp = priv_kp
        guard let privreq = make_private_zap_request_event(identity: keypair, enc_key: kp, target: target, message: message) else {
            return nil
        }
        tags.append(["anon", privreq.enc])
        message = ""
        privzap_req = privreq
    }
    
    guard let ev = NostrEvent(content: message, keypair: kp.to_keypair(), kind: 9734, tags: tags, createdAt: now) else {
        return nil
    }
    let zapreq = ZapRequest(ev: ev)
    if let privzap_req {
        return .priv(zapreq, privzap_req)
    } else {
        return .normal(zapreq)
    }
}

func zap_target_to_tags(_ target: ZapTarget) -> [[String]] {
    switch target {
    case .profile(let pk):
        return [["p", pk.hex()]]
    case .note(let note_target):
        return [["e", note_target.note_id.hex()],
                ["p", note_target.author.hex()]]
    }
}

struct PrivateZapRequest {
    let req: ZapRequest
    let enc: String
}

func make_private_zap_request_event(identity: FullKeypair, enc_key: FullKeypair, target: ZapTarget, message: String) -> PrivateZapRequest? {
    // target tags must be the same as zap request target tags
    let tags = zap_target_to_tags(target)
    
    guard let note = NostrEvent(content: message, keypair: identity.to_keypair(), kind: 9733, tags: tags),
          let note_json = encode_json(note),
          let enc = encrypt_message(message: note_json, privkey: enc_key.privkey, to_pk: target.pubkey, encoding: .bech32)
    else {
        return nil
    }
    
    return PrivateZapRequest(req: ZapRequest(ev: note), enc: enc)
}

func decrypt_private_zap(our_privkey: Privkey, zapreq: NostrEvent, target: ZapTarget) -> NostrEvent? {
    guard let anon_tag = zapreq.tags.first(where: { t in
        t.count >= 2 && t[0].matches_str("anon")
    }) else {
        return nil
    }
    
    let enc_note = anon_tag[1].string()

    var note = decrypt_note(our_privkey: our_privkey, their_pubkey: zapreq.pubkey, enc_note: enc_note, encoding: .bech32)
    
    // check to see if the private note was from us
    if note == nil {
        guard let our_private_keypair = generate_private_keypair(our_privkey: our_privkey, id: NoteId(target.id), created_at: zapreq.created_at) else {
            return nil
        }
        // use our private keypair and their pubkey to get the shared secret
        note = decrypt_note(our_privkey: our_private_keypair.privkey, their_pubkey: target.pubkey, enc_note: enc_note, encoding: .bech32)
    }
    
    guard let note else {
        return nil
    }
        
    guard note.kind == 9733 else {
        return nil
    }
    
    let zr_etag = zapreq.referenced_ids.first
    let note_etag = note.referenced_ids.first
    
    guard zr_etag == note_etag else {
        return nil
    }
    
    let zr_ptag = zapreq.referenced_pubkeys.first
    let note_ptag = note.referenced_pubkeys.first
    
    guard let zr_ptag, let note_ptag, zr_ptag == note_ptag else {
        return nil
    }
    
    guard validate_event(ev: note) == .ok else {
        return nil
    }
    
    return note
}

enum MakeZapRequest {
    case priv(ZapRequest, PrivateZapRequest)
    case normal(ZapRequest)
    
    var private_inner_request: ZapRequest {
        switch self {
        case .priv(_, let pzr):
            return pzr.req
        case .normal(let zr):
            return zr
        }
    }
    
    var potentially_anon_outer_request: ZapRequest {
        switch self {
        case .priv(let zr, _):
            return zr
        case .normal(let zr):
            return zr
        }
    }
}

func make_first_contact_event(keypair: Keypair) -> NostrEvent? {
    let bootstrap_relays = load_bootstrap_relays(pubkey: keypair.pubkey)
    let rw_relay_info = RelayInfo(read: true, write: true)
    var relays: [String: RelayInfo] = [:]
    
    for relay in bootstrap_relays {
        relays[relay] = rw_relay_info
    }
    
    let relay_json = encode_json(relays)!
    let damus_pubkey = "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"
    let tags = [
        ["p", damus_pubkey],
        ["p", keypair.pubkey.hex()] // you're a friend of yourself!
    ]
    return NostrEvent(content: relay_json, keypair: keypair, kind: NostrKind.contacts.rawValue, tags: tags)
}

func make_metadata_event(keypair: FullKeypair, metadata: Profile) -> NostrEvent? {
    guard let metadata_json = encode_json(metadata) else {
        return nil
    }
    return NostrEvent(content: metadata_json, keypair: keypair.to_keypair(), kind: NostrKind.metadata.rawValue, tags: [])

}
