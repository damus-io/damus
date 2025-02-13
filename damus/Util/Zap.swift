//
//  Zap.swift
//  damus
//
//  Created by William Casarin on 2023-01-15.
//

import Foundation

struct NoteZapTarget: Equatable, Hashable {
    public let note_id: NoteId
    public let author: Pubkey
}

enum ZapTarget: Equatable, Hashable {
    case profile(Pubkey)
    case note(NoteZapTarget)
    
    static func note(id: NoteId, author: Pubkey) -> ZapTarget {
        return .note(NoteZapTarget(note_id: id, author: author))
    }

    var pubkey: Pubkey {
        switch self {
        case .profile(let pk):
            return pk
        case .note(let note_target):
            return note_target.author
        }
    }

    var note_id: NoteId? {
        switch self {
        case .profile:
            return nil
        case .note(let noteZapTarget):
            return noteZapTarget.note_id
        }
    }

    var id: Data {
        switch self {
        case .profile(let pubkey):
            return pubkey.id
        case .note(let noteZapTarget):
            return noteZapTarget.note_id.id
        }
    }
}

struct ZapRequest {
    let ev: NostrEvent
    let marked_hidden: Bool

    var id: ZapRequestId {
        ZapRequestId(from_zap_request: self)
    }

    var is_in_thread: Bool {
        return !self.ev.content.isEmpty && !marked_hidden
    }
    
    init(ev: NostrEvent) {
        self.ev = ev
        self.marked_hidden = ev.tags.first(where: { t in t.count > 0 && t[0].matches_str("hidden") }) != nil
    }
}

enum ExtPendingZapStateType {
    case fetching_invoice
    case done
}

class ExtPendingZapState: Equatable {
    static func == (lhs: ExtPendingZapState, rhs: ExtPendingZapState) -> Bool {
        return lhs.state == rhs.state
    }
    
    var state: ExtPendingZapStateType
    
    init(state: ExtPendingZapStateType) {
        self.state = state
    }
}

enum PendingZapState: Equatable {
    case nwc(NWCPendingZapState)
    case external(ExtPendingZapState)
}


enum NWCStateType: Equatable {
    case fetching_invoice
    case cancel_fetching_invoice
    case postbox_pending(NostrEvent)
    case confirmed
    case failed
}

class NWCPendingZapState: Equatable {
    private(set) var state: NWCStateType
    let url: WalletConnectURL
    
    init(state: NWCStateType, url: WalletConnectURL) {
        self.state = state
        self.url = url
    }
    
    //@discardableResult  -- not discardable, the ZapsDataModel may need to send objectWillChange but we don't force it
    func update_state(state: NWCStateType) -> Bool {
        guard state != self.state else {
            return false
        }
        self.state = state
        return true
    }
    
    static func == (lhs: NWCPendingZapState, rhs: NWCPendingZapState) -> Bool {
        return lhs.state == rhs.state && lhs.url == rhs.url
    }
}

class PendingZap {
    let amount_msat: Int64
    let target: ZapTarget
    let request: ZapRequest
    let type: ZapType
    private(set) var state: PendingZapState
    
    init(amount_msat: Int64, target: ZapTarget, request: MakeZapRequest, type: ZapType, state: PendingZapState) {
        self.amount_msat = amount_msat
        self.target = target
        self.request = request.private_inner_request
        self.type = type
        self.state = state
    }
    
    @discardableResult
    func update_state(model: ZapsDataModel, state: PendingZapState) -> Bool {
        guard self.state != state else {
            return false
        }
        
        self.state = state
        model.objectWillChange.send()
        return true
    }
}

struct ZapRequestId: Equatable, Hashable {
    let reqid: NoteId

    init(from_zap_request: ZapRequest) {
        self.reqid = from_zap_request.ev.id
    }

    init(from_zap: Zapping) {
        self.reqid = from_zap.request.ev.id
    }
    
    init(from_makezap: MakeZapRequest) {
        self.reqid = from_makezap.private_inner_request.ev.id
    }
    
    init(from_pending: PendingZap) {
        self.reqid = from_pending.request.ev.id
    }
}

enum Zapping {
    case zap(Zap)
    case pending(PendingZap)
    
    var is_pending: Bool {
        switch self {
        case .zap:
            return false
        case .pending:
            return true
        }
    }
    
    var is_paid: Bool {
        switch self {
        case .zap:
            // we have a zap so this is proof of payment
            return true
        case .pending(let pzap):
            switch pzap.state {
            case .external:
                // It could be but we don't know. We have to wait for a zap to know.
                return false
            case .nwc(let nwc_state):
                // nwc confirmed that we have a payment, but we might not have zap yet
                return nwc_state.state == .confirmed
            }
        }
    }
    
    var is_private: Bool {
        switch self {
        case .zap(let zap):
            return zap.private_request != nil
        case .pending(let pzap):
            return pzap.type == .priv
        }
    }
    
    var amount: Int64 {
        switch self {
        case .zap(let zap):
            return zap.invoice.amount
        case .pending(let pzap):
            return pzap.amount_msat
        }
    }
    
    var target: ZapTarget {
        switch self {
        case .zap(let zap):
            return zap.target
        case .pending(let pzap):
            return pzap.target
        }
    }
    
    var request: ZapRequest {
        switch self {
        case .zap(let zap):
            return zap.request
        case .pending(let pzap):
            return pzap.request
        }
    }
    
    var created_at: UInt32 {
        switch self {
        case .zap(let zap):
            return zap.event.created_at
        case .pending(let pzap):
            // pending zaps are created right away
            return pzap.request.ev.created_at
        }
    }
    
    var event: NostrEvent? {
        switch self {
        case .zap(let zap):
            return zap.event
        case .pending:
            // pending zaps don't have a zap event
            return nil
        }
    }
    
    var is_in_thread: Bool {
        switch self {
        case .zap(let zap):
            return zap.request.is_in_thread
        case .pending(let pzap):
            return pzap.request.is_in_thread
        }
    }
    
    var is_anon: Bool {
        switch self {
        case .zap(let zap):
            return zap.is_anon
        case .pending(let pzap):
            return pzap.type == .anon
        }
    }
}

struct Zap {
    public let event: NostrEvent
    public let invoice: ZapInvoice
    public let zapper: Pubkey /// zap authorizer
    public let target: ZapTarget
    public let raw_request: ZapRequest
    public let is_anon: Bool
    public let private_request: ZapRequest?
    
    var request: ZapRequest {
        return private_request ?? self.raw_request
    }
    
    public static func from_zap_event(zap_ev: NostrEvent, zapper: Pubkey, our_privkey: Privkey?) -> Zap? {
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
        guard let zap_req = get_zap_request(zap_ev) else {
            return nil
        }

        guard validate_event(ev: zap_req) == .ok else {
            return nil
        }
        
        guard let target = determine_zap_target(zap_req) else {
            return nil
        }
        
        let private_request = our_privkey.flatMap {
            decrypt_private_zap(our_privkey: $0, zapreq: zap_req, target: target)
        }
        
        let is_anon = private_request == nil && event_is_anonymous(ev: zap_req)
        let preq = private_request.map { pr in ZapRequest(ev: pr) }
        
        return Zap(event: zap_ev, invoice: zap_invoice, zapper: zapper, target: target, raw_request: ZapRequest(ev: zap_req), is_anon: is_anon, private_request: preq)
    }
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

func event_is_anonymous(ev: NostrEvent) -> Bool {
    return ev.known_kind == .zap_request && event_has_tag(ev: ev, tag: "anon")
}

func event_has_tag(ev: NostrEvent, tag: String) -> Bool {
    for t in ev.tags {
        if t.count >= 1 && t[0].matches_str(tag) {
            return true
        }
    }
    
    return false
}

func get_zap_request(_ ev: NostrEvent) -> NostrEvent? {
    guard let desc = event_tag(ev, name: "description") else {
        return nil
    }

    return decode_nostr_event_json(desc)
}

func invoice_to_zap_invoice(_ invoice: Invoice) -> ZapInvoice? {
    guard case .specific(let amt) = invoice.amount else {
        return nil
    }
    
    return ZapInvoice(description: invoice.description, amount: amt, string: invoice.string, expiry: invoice.expiry, created_at: invoice.created_at)
}

func determine_zap_target(_ ev: NostrEvent) -> ZapTarget? {
    guard let ptag = ev.referenced_pubkeys.first else {
        return nil
    }
    
    if let etag = ev.referenced_ids.first {
        return ZapTarget.note(id: etag, author: ptag)
    }
    
    return .profile(ptag)
}

extension UnsafePointer<CChar> {
    func as_str() -> String {
        String(cString: self)
    }
}

func decode_bolt11(_ s: String) -> Invoice? {
    let bytes = s.utf8CString
    var bolt11_ptr: UnsafeMutablePointer<bolt11>?

    let _ = bytes.withUnsafeBufferPointer { p in
        bolt11_ptr = bolt11_decode(nil, p.baseAddress, nil)
    }

    guard let bolt11 = maybe_pointee(bolt11_ptr) else {
        return nil
    }

    var amount: Amount = .any
    var desc: InvoiceDescription = .description("")
    if let amt = maybe_pointee(bolt11.msat) {
        amount = .specific(Int64(amt.millisatoshis))
    }
    let expiry = bolt11.expiry
    let created_at = bolt11.timestamp

    if var deschash = maybe_pointee(bolt11.description_hash) {
        let data = Data(bytes: &deschash.u, count: 32)
        desc = .description_hash(data)
    } else {
        desc = .description(bolt11.description.as_str())
    }

    let invoice = Invoice(description: desc, amount: amount, string: s, expiry: expiry, created_at: created_at)

    tal_free(bolt11_ptr)

    return invoice
}

func event_tag(_ ev: NostrEvent, name: String) -> String? {
    for tag in ev.tags {
        if tag.count >= 2 && tag[0].matches_str(name) {
            return tag[1].string()
        }
    }
    
    return nil
}

func decode_nostr_event_json(_ desc: String) -> NostrEvent? {
    return NostrEvent.owned_from_json(json: desc)
}


func fetch_zapper_from_lnurl(lnurls: LNUrls, pubkey: Pubkey, lnurl: String) async -> Pubkey? {
    guard let endpoint = await lnurls.lookup_or_fetch(pubkey: pubkey, lnurl: lnurl),
          let allows = endpoint.allowsNostr, allows,
          let key = endpoint.nostrPubkey,
          let pk = hex_decode_pubkey(key)
    else {
        return nil
    }
    
    return pk
}

func fetch_zap_invoice(_ payreq: LNUrlPayRequest, zapreq: NostrEvent?, msats: Int64, zap_type: ZapType, comment: String?) async -> String? {
    guard var base_url = payreq.callback.flatMap({ URLComponents(string: $0) }) else {
        return nil
    }
    
    let zappable = payreq.allowsNostr ?? false
    
    var query = [URLQueryItem(name: "amount", value: "\(msats)")]
    
    if zappable && zap_type != .non_zap, let json = encode_json(zapreq) {
        print("zapreq json: \(json)")
        query.append(URLQueryItem(name: "nostr", value: json))
    }
   
    // add a lud12 comment as well if we have it
    if zap_type != .priv, let comment, let limit = payreq.commentAllowed, limit != 0 {
        let limited_comment = String(comment.prefix(limit))
        query.append(URLQueryItem(name: "comment", value: limited_comment))
    }
    
    base_url.queryItems = query
    
    guard let url = base_url.url else {
        return nil
    }
    
    print("url \(url)")
    
    var ret: (Data, URLResponse)? = nil
    do {
        ret = try await URLSession.shared.data(from: url)
    } catch {
        print(error.localizedDescription)
        return nil
    }
    
    guard let ret else {
        return nil
    }
    
    let json_str = String(decoding: ret.0, as: UTF8.self)
    guard let result: LNUrlPayResponse = decode_json(json_str) else {
        print("fetch_zap_invoice error: \(json_str)")
        return nil
    }
    
    // make sure it's the correct amount
    guard let bolt11 = decode_bolt11(result.pr),
          .specific(msats) == bolt11.amount
    else {
        return nil
    }
    
    return result.pr
}
