//
//  Zap.swift
//  damus
//
//  Created by William Casarin on 2023-01-15.
//

import Foundation

enum ZapSource {
    case author(String)
    // TODO: anonymous
    //case anonymous
}

public struct NoteZapTarget: Equatable {
    public let note_id: String
    public let author: String
}

public enum ZapTarget: Equatable {
    case profile(String)
    case note(NoteZapTarget)
    
    public static func note(id: String, author: String) -> ZapTarget {
        return .note(NoteZapTarget(note_id: id, author: author))
    }
    
    var pubkey: String {
        switch self {
        case .profile(let pk):
            return pk
        case .note(let note_target):
            return note_target.author
        }
    }
    
    var id: String {
        switch self {
        case .note(let note_target):
            return note_target.note_id
        case .profile(let pk):
            return pk
        }
    }
}

struct ZapRequest {
    let ev: NostrEvent
}

struct Zap {
    public let event: NostrEvent
    public let invoice: ZapInvoice
    public let zapper: String /// zap authorizer
    public let target: ZapTarget
    public let request: ZapRequest
    
    public static func from_zap_event(zap_ev: NostrEvent, zapper: String) -> Zap? {
        /// Make sure that we only create a zap event if it is authorized by the profile or event
        guard zapper == zap_ev.pubkey else {
            return nil
        }
        guard let bolt11_str = event_tag(zap_ev, name: "bolt11") else {
            return nil
        }
        guard let bolt11 = decode_bolt11(bolt11_str) else {
            return nil
        }
        /// Any amount invoices are not allowed
        guard let zap_invoice = invoice_to_zap_invoice(bolt11) else {
            return nil
        }
        // Some endpoints don't have this, let's skip the check for now. We're mostly trusting the zapper anyways
        /*
        guard let preimage = event_tag(zap_ev, name: "preimage") else {
            return nil
        }
        guard preimage_matches_invoice(preimage, inv: zap_invoice) else {
            return nil
        }
         */
        guard let desc = get_zap_description(zap_ev, inv_desc: zap_invoice.description) else {
            return nil
        }
        guard let zap_req = decode_nostr_event_json(desc) else {
            return nil
        }
        guard let target = determine_zap_target(zap_req) else {
            return nil
        }
        
        return Zap(event: zap_ev, invoice: zap_invoice, zapper: zapper, target: target, request: ZapRequest(ev: zap_req))
    }
}

/// Fetches the description from either the invoice, or tags, depending on the type of invoice
func get_zap_description(_ ev: NostrEvent, inv_desc: InvoiceDescription) -> String? {
    switch inv_desc {
    case .description(let string):
        return string
    case .description_hash(let deschash):
        guard let desc = event_tag(ev, name: "description") else {
            return nil
        }
        guard let data = desc.data(using: .utf8) else {
            return nil
        }
        guard sha256(data) == deschash else {
            return nil
        }
        
        return desc
    }
}

func invoice_to_zap_invoice(_ invoice: Invoice) -> ZapInvoice? {
    guard case .specific(let amt) = invoice.amount else {
        return nil
    }
    
    return ZapInvoice(description: invoice.description, amount: amt, string: invoice.string, expiry: invoice.expiry, payment_hash: invoice.payment_hash, created_at: invoice.created_at)
}

func preimage_matches_invoice<T>(_ preimage: String, inv: LightningInvoice<T>) -> Bool {
    guard let raw_preimage = hex_decode(preimage) else {
        return false
    }
    
    let hashed = sha256(Data(raw_preimage))
    
    return inv.payment_hash == hashed
}

func determine_zap_target(_ ev: NostrEvent) -> ZapTarget? {
    guard let ptag = event_tag(ev, name: "p") else {
        return nil
    }
    
    if let etag = event_tag(ev, name: "e") {
        return ZapTarget.note(id: etag, author: ptag)
    }
    
    return .profile(ptag)
}
                   
func decode_bolt11(_ s: String) -> Invoice? {
    var bs = blocks()
    bs.num_blocks = 0
    blocks_init(&bs)
    
    let bytes = s.utf8CString
    let _ = bytes.withUnsafeBufferPointer { p in
        damus_parse_content(&bs, p.baseAddress)
    }
    
    guard bs.num_blocks == 1 else {
        blocks_free(&bs)
        return nil
    }
    
    let block = bs.blocks[0]
    
    guard let converted = convert_block(block, tags: []) else {
        blocks_free(&bs)
        return nil
    }
    
    guard case .invoice(let invoice) = converted else {
        blocks_free(&bs)
        return nil
    }
    
    blocks_free(&bs)
    return invoice
}

func event_tag(_ ev: NostrEvent, name: String) -> String? {
    for tag in ev.tags {
        if tag.count >= 2 && tag[0] == name {
            return tag[1]
        }
    }
    
    return nil
}

func decode_nostr_event_json(_ desc: String) -> NostrEvent? {
    let decoder = JSONDecoder()
    guard let dat = desc.data(using: .utf8) else {
        return nil
    }
    guard let ev = try? decoder.decode(NostrEvent.self, from: dat) else {
        return nil
    }
    
    return ev
}

func decode_zap_request(_ desc: String) -> ZapRequest? {
    let decoder = JSONDecoder()
    guard let jsonData = desc.data(using: .utf8) else {
        return nil
    }
    guard let jsonArray = try? JSONSerialization.jsonObject(with: jsonData) as? [[Any]] else {
        return nil
    }
    
    for array in jsonArray {
        guard array.count == 2 else {
            continue
        }
        let mkey = array.first.flatMap { $0 as? String }
        if let key = mkey, key == "application/nostr" {
            guard let dat = try? JSONSerialization.data(withJSONObject: array[1], options: []) else {
                return nil
            }
            
            guard let zap_req = try? decoder.decode(NostrEvent.self, from: dat) else {
                return nil
            }
            
            guard zap_req.kind == 9734 else {
                return nil
            }
            
            /// Ensure the signature on the zap request is correct
            guard case .ok = validate_event(ev: zap_req) else {
                return nil
            }
            
            return ZapRequest(ev: zap_req)
        }
    }
    
    return nil
}



func fetch_zapper_from_lnurl(_ lnurl: String) async -> String? {
    guard let endpoint = await fetch_static_payreq(lnurl) else {
        return nil
    }
    
    guard let allows = endpoint.allowsNostr, allows else {
        return nil
    }
    
    guard let key = endpoint.nostrPubkey, key.count == 64 else {
        return nil
    }
    
    return endpoint.nostrPubkey
}

func decode_lnurl(_ lnurl: String) -> URL? {
    guard let decoded = try? bech32_decode(lnurl) else {
        return nil
    }
    guard decoded.hrp == "lnurl" else {
        return nil
    }
    guard let url = URL(string: String(decoding: decoded.data, as: UTF8.self)) else {
        return nil
    }
    return url
}

func fetch_static_payreq(_ lnurl: String) async -> LNUrlPayRequest? {
    guard let url = decode_lnurl(lnurl) else {
        return nil
    }
    
    guard let ret = try? await URLSession.shared.data(from: url) else {
        return nil
    }
    
    let json_str = String(decoding: ret.0, as: UTF8.self)
    
    guard let endpoint: LNUrlPayRequest = decode_json(json_str) else {
        return nil
    }
    
    return endpoint
}

func fetch_zap_invoice(_ payreq: LNUrlPayRequest, zapreq: NostrEvent, sats: Int) async -> String? {
    guard var base_url = payreq.callback.flatMap({ URLComponents(string: $0) }) else {
        return nil
    }
    
    let zappable = payreq.allowsNostr ?? false
    let amount: Int64 = Int64(sats) * 1000
    
    var query = [URLQueryItem(name: "amount", value: "\(amount)")]
    
    if zappable {
        if let json = encode_json(zapreq) {
            print("zapreq json: \(json)")
            query.append(URLQueryItem(name: "nostr", value: json))
        }
    }
    
    base_url.queryItems = query
    
    guard let url = base_url.url else {
        return nil
    }
    
    print("url \(url)")
    
    guard let ret = try? await URLSession.shared.data(from: url) else {
        return nil
    }
    
    let json_str = String(decoding: ret.0, as: UTF8.self)
    guard let result: LNUrlPayResponse = decode_json(json_str) else {
        print("fetch_zap_invoice error: \(json_str)")
        return nil
    }
    
    return result.pr
}
