//
//  ContactListPolicy.swift
//  damus
//
//  Policy for protecting users from contact list (kind 3) issues.
//
//  This is a CRITICAL policy that protects against:
//  - Buggy clients that accidentally nuke contact lists
//  - Malicious apps that try to remove all follows
//  - Accidental mass unfollows
//
//  See: https://github.com/nostrability/nostrability/issues/33
//

import Foundation

/// Policy for Kind 3 (contact list) events.
///
/// Contact list events are high-risk because a buggy or malicious client can
/// easily wipe a user's entire social graph. This policy adds safeguards:
///
/// - Empty contact lists always require approval with a strong warning
/// - Significant reductions in contact count require approval
/// - New clients always require approval for contact list changes
///
/// ## Reference
/// This addresses the issues documented in:
/// - https://github.com/damus-io/damus/issues/2238
/// - https://github.com/nostrability/nostrability/issues/33
struct ContactListPolicy: KindPolicy {

    // MARK: - KindPolicy Conformance

    let kind: UInt32 = 3

    func evaluate(event: UnsignedEvent, client: SigningClient) -> PolicyDecision {
        let newContactCount = countContacts(in: event)

        // Empty contact list is ALWAYS suspicious - require approval with warning
        guard newContactCount > 0 else {
            return .requireApproval(context: ApprovalContext(
                client: client,
                event: event,
                risks: [.contactListEmpty],
                summary: "This will remove ALL your follows (\(newContactCount) contacts)"
            ))
        }

        // For now, always require approval for contact list changes from external clients
        // In the future, we can compare against the current contact list to detect
        // suspicious reductions
        //
        // TODO: Compare against current contact list from nostrdb
        // - Load current kind 3 event for user's pubkey
        // - Count existing contacts
        // - If new count < existing * 0.5, flag as suspicious truncation

        return .requireApproval(context: ApprovalContext(
            client: client,
            event: event,
            risks: [],
            summary: "Update contact list to \(newContactCount) follows"
        ))
    }

    // MARK: - Private Helpers

    /// Counts the number of contacts (p-tags) in an event.
    ///
    /// - Parameter event: The unsigned event to analyze.
    /// - Returns: The number of p-tags (pubkey references).
    private func countContacts(in event: UnsignedEvent) -> Int {
        return event.tags.filter { tag in
            guard let tagType = tag.first else { return false }
            return tagType == "p"
        }.count
    }
}

// MARK: - Future Enhancements

/*
 Future improvements for contact list protection:

 1. Compare against current contact list:
    - Load user's current kind 3 event from nostrdb
    - Calculate the diff (added/removed contacts)
    - Flag if more than N contacts removed
    - Show detailed diff in approval UI

 2. Rate limiting:
    - Track frequency of kind 3 updates per client
    - Flag unusually high frequency updates

 3. Contact list backup:
    - Before signing any kind 3, store a backup
    - Provide recovery UI if user's list gets nuked

 4. Trusted client exceptions:
    - Allow power users to whitelist specific clients
    - Internal Damus operations bypass these checks

 Example future implementation:

 func evaluate(event: UnsignedEvent, client: SigningClient) -> PolicyDecision {
     let newContacts = Set(extractPubkeys(from: event))

     // Load current contacts from nostrdb
     guard let currentEvent = loadCurrentContactList() else {
         // No existing contact list - this is likely a new user
         return .approve
     }

     let currentContacts = Set(extractPubkeys(from: currentEvent))
     let removed = currentContacts.subtracting(newContacts)
     let added = newContacts.subtracting(currentContacts)

     // Check for suspicious truncation
     let removalRatio = Double(removed.count) / Double(currentContacts.count)
     if removalRatio > 0.5 && removed.count > 10 {
         return .requireApproval(context: ApprovalContext(
             client: client,
             event: event,
             risks: [.contactListTruncation(removed: removed.count, remaining: newContacts.count)],
             summary: "This will remove \(removed.count) follows"
         ))
     }

     return .approve
 }
 */
