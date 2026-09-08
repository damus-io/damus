//
//  PurpleVideoRoutes.swift
//  damus
//
//  Every URL the hosted-video API is reached at, built in one pure place.
//
//  This is not ceremony. Every one of these routes is NIP-98 authenticated,
//  and a NIP-98 401 in practice comes from the signed `u` tag not matching the
//  URL that was actually requested — a trailing slash, an unencoded guid, a
//  query parameter appended after the event was signed. Building the URL here,
//  once, and signing the very same value is what makes that class of bug
//  impossible; keeping it free of `URLSession` is what makes it testable.
//

import Foundation

enum PurpleVideoRoutes {
    /// `POST /video` — authorize one upload.
    ///
    /// No trailing slash: express matches `/video` and `/video/` differently
    /// enough that a redirect would drop the `Authorization` header.
    static func authorize(base: URL) -> URL {
        base.appendingPathComponent("video", isDirectory: false)
    }

    /// `GET`/`DELETE /video/{id}` — one video's status, or its deletion.
    ///
    /// - Throws: `PurpleVideoAPIError.invalidVideoID` for an id that cannot be
    ///   a single safe path component. A guid is semi-public by design (it is
    ///   the playback URL, and a non-owner gets a deliberate 404 rather than a
    ///   403), but that is no reason to let one walk out of our own base path.
    static func video(base: URL, id: PurpleVideoID) throws -> URL {
        guard isUsableAsPathComponent(id) else {
            throw PurpleVideoAPIError.invalidVideoID(id)
        }
        return authorize(base: base).appendingPathComponent(id, isDirectory: false)
    }

    /// Whether an id is safe to append as exactly one path component.
    ///
    /// `%` is refused rather than escaped: an id that already contains a
    /// percent-escape would be double-encoded here and would then not match
    /// what the server stored.
    private static func isUsableAsPathComponent(_ id: PurpleVideoID) -> Bool {
        guard !id.isEmpty, id != ".", id != ".." else { return false }
        let forbidden = CharacterSet(charactersIn: "/\\%")
        guard id.rangeOfCharacter(from: forbidden) == nil else { return false }
        guard !id.contains("..") else { return false }
        return true
    }
}
