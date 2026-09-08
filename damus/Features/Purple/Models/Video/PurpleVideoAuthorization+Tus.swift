//
//  PurpleVideoAuthorization+Tus.swift
//  damus
//
//  How a Purple authorization is handed to the TUS upload client.
//
//  This is one computed property in its own file on purpose: it contradicts a
//  doc comment in `TusUploadClient.swift`, and keeping it isolated makes the
//  disagreement a one-file revert if the evidence below turns out to be wrong.
//

import Foundation

extension PurpleVideoAuthorization {
    /// Where `TusUploadClient` should start this upload.
    ///
    /// **`.create(endpoint:)`, not `.uploadURL(_:)`** — and that contradicts
    /// `TusDestination.uploadURL`'s own doc comment, which says "this is the
    /// Purple/Bunny case: the authorization endpoint creates the video object
    /// and hands us its URL". The video *object*, yes. The TUS *upload
    /// resource*, no. Three things say so:
    ///
    /// - `tus_endpoint` is the same `https://video.bunnycdn.com/tusupload` for
    ///   every video the API authorizes. It carries no guid, so it cannot be
    ///   one video's upload resource.
    /// - `docs/bunny-stream-spike/tus-protocol-transcript.log` records the
    ///   provider answering a `POST` to that endpoint with `201` and a
    ///   **relative** `Location: /tusupload/<32-hex>` — a value that is not the
    ///   guid, and that has to be resolved against the endpoint.
    /// - `TusResponse.location(from:relativeTo:)` exists to resolve exactly
    ///   that relative header, and `TusRequest.creation`'s header-merging path
    ///   would be dead code for its only real consumer if `.uploadURL` were
    ///   right.
    ///
    /// The `tusHeaders` that go with this are already in the shape
    /// `TusUploadClient.enqueue(headers:)` wants, and are validated by
    /// `PurpleVideoWire` to carry all four keys the provider requires.
    var tusDestination: TusDestination {
        .create(endpoint: tusEndpoint)
    }
}
