//
//  ZapType.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-24.
//

import Foundation

enum ZapType: String, StringCodable {
    case pub
    case anon
    case priv
    case non_zap
    
    init?(from string: String) {
        guard let v = ZapType(rawValue: string) else {
            return nil
        }
        
        self = v
    }
    
    func to_string() -> String {
        return self.rawValue
    }
    
}

extension ZapTarget {
    /// Whether this zap is aimed at a note that came out of a gift wrap.
    ///
    /// Asked of the database rather than carried on the target, because ``NdbNote/is_rumor`` is
    /// nostrdb's `NDB_NOTE_FLAG_RUMOR` and nostrdb is the only thing that sets it. A boolean threaded
    /// down from whichever view built the target would be a second copy of the answer, and the next
    /// zap entry point somebody adds would default to the wrong one; a lookup keys every caller,
    /// present and future, off the one unforgeable fact.
    ///
    /// A profile zap has no note to be private about, and a note we cannot find is one we are not
    /// displaying — every read path in the app treats a note it does not hold as nothing at all, and
    /// this is not the place to invent a different rule.
    func isPrivateNote(ndb: Ndb) -> Bool {
        guard let note_id = self.note_id else { return false }
        return (try? ndb.lookup_note(note_id, borrow: { note -> Bool in
            switch note {
            case .some(let note): return note.is_rumor
            case .none: return false
            }
        })) ?? false
    }
}

extension ZapType {
    /// The type a zap at `target` is actually sent as, which is not always the type that was asked
    /// for.
    ///
    /// **A zap at a rumor is always private.** A public zap request carries the sender's pubkey and
    /// comment in the clear, and an anonymous one carries the comment; both end up inside the kind-9735
    /// receipt the recipient's LNURL server publishes. On a note only two people have, that hands an
    /// observer the comment and — for a public zap — the fact that this particular person is talking to
    /// the note's author, which is precisely what the gift wrap around the note was for. ``priv``
    /// encrypts sender and comment to the recipient, so the receipt says only that somebody paid.
    ///
    /// **Except ``non_zap``, which is left alone.** It is not a weaker private zap, it is a plain
    /// lightning payment: ``fetch_zap_invoice(_:zapreq:msats:zap_type:comment:)`` never sends the zap
    /// request to the callback for one, so no receipt is published and nothing whatever reaches a
    /// relay. Forcing it to ``priv`` would make the *more* private choice leak more, which is the kind
    /// of mistake a rule stated as "always force private" invites and a rule stated as "publish less"
    /// does not.
    ///
    /// What this cannot hide is the receipt's `e` tag: the LNURL server publishes it, naming the
    /// rumor's id and the recipient. That id resolves for nobody, and an observer has no way to tell it
    /// from any other note they do not happen to hold, so the cost is small and it is taken knowingly —
    /// the alternative on the table was no zap at all.
    ///
    /// Applied in ``send_zap(damus_state:target:lnurl:is_custom:comment:amount_sats:zap_type:)``, the
    /// single funnel every zap in the app passes through, so no picker, setting or new entry point can
    /// route around it. The UI that stops the user *choosing* another type is a courtesy on top of
    /// this, not the enforcement.
    static func forced(on target: ZapTarget, requested: ZapType, ndb: Ndb) -> ZapType {
        guard requested != .non_zap, target.isPrivateNote(ndb: ndb) else { return requested }
        return .priv
    }
}
