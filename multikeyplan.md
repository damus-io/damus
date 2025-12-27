# Multi-Account Profiles Plan

## Storage & Migration
- Store accounts list in `DamusUserDefaults` (MRU order). Model `SavedAccount { pubkey, displayName?, avatarURL?, hasPrivateKey, addedAt }`.
- Keep per-account privkeys in Keychain using a short name (e.g., `pk-<pubkey.prefix16>`) to avoid Keychain length limits.
- Track `activePubkey` separately; never fall back to another account if active is missing.
- Migration: on launch, if only the legacy saved keypair exists, insert it into `AccountsStore`, set active, then clear legacy storage.

## API / Helpers
- `AccountsStore.accounts: [SavedAccount]`, `activeAccount: SavedAccount?`, `activeKeypair: Keypair?`
- `setActive(_ pubkey)`, `addOrUpdate(_ keypair, savePriv: Bool)`, `remove(_ pubkey)`, `keypair(for:)`
- ObservableObject singleton; persist immediately.

## Session & DamusState
- Session derives from `activeKeypair`.
- On switch/remove: `state.close()`, recreate `DamusState`, reconnect relays; show lightweight “switching…” indicator.
- Logout clears only `activePubkey` and in-memory state; accounts stay until removed.
- No auto-switch/fallback on relaunch (addresses #2058).

## Onboarding Guard (fixes root of #2058)
- During onboarding/login, do not write to AccountsStore until user confirms “Save & Login.”
- `isOnboarding` guard prevents scenePhase/resume from flipping accounts mid-flow.
- Provide explicit “Save this account” action after transient login to promote it.

## Settings/Relays/Preferences
- Verify `UserSettingsStore` scoping; if any relays/preferences are global, scope by pubkey (e.g., `{pubkey}:relays`).
- Load per-account relay list on `activePubkey` change.

## UI Flows
- Setup/Login: if accounts exist, show “Choose an account” (MRU) with Switch, Add account (existing key), Create new. Selecting sets active + login notify; no silent switching.
- In-app Settings: “Manage accounts” list (avatar/initials + short npub/name) with Switch, Add, Remove. Removing active forces selecting another or returning to Setup.
- Active indicator: use existing profile/avatar button with subtle ring/badge; tap opens switcher sheet.
- View-only accounts: allow pubkey-only; warn when activating (no posting/reactions).

## Data Isolation Audit
- Audit drafts, mutes, notification state, search history, Kingfisher cache. Key by pubkey if user-visible and per-account; otherwise document shared cache behavior.

## Notifications
- v1: notifications only for active account; document limitation. Cross-account badge routing deferred.

## Ordering
- MRU ordering (recently active floats to top). Manual reordering deferred to later iteration.

## Testing
- Unit: AccountsStore add/update/remove, active switching, migration, view-only handling, missing privkey despite `hasPrivateKey`, MRU ordering, Keychain key naming.
- Concurrency: simultaneous switch attempts.
- Keychain unavailable/device locked scenarios.
- Large list (10+ accounts).
- Manual: fresh install create/add, transient login then promote, switch accounts, remove active/non-active, logout/relaunch (no surprise switch), app-switch during onboarding/key copy (no unintended activation), view-only activation warning, relay reconnect on switch.
- Document iCloud Keychain implications: pubkeys in defaults may sync; privkeys may not—clarify behavior.

## Phases

### MVP (core switching)
- Implement AccountsStore (MRU in UserDefaults, short Keychain keys, activePubkey tracking, migration).
- Wire damusApp/process_login to use AccountsStore.activeKeypair; no auto-fallback; logout clears only active.
- Simple account picker in Setup/Login when accounts exist (list + switch + add/create hooks); view-only warning.
- Onboarding guard: don’t persist until “Save & Login”; transient login stays in-memory; offer “Save this account.”
- Tests: unit for AccountsStore (add/update/remove, active switch, migration, view-only, MRU, missing privkey); manual smoke (create/add, switch, logout/relaunch no surprise swap, transient then promote).

### Phase 2 (integration)
- DamusState lifecycle: close/recreate on switch with reconnect indicator.
- Verify/adjust per-account relays/settings scoping; load relays on active change.
- Settings “Manage accounts” view (switch/add/remove; handle removing active).
- Active indicator on profile/avatar button with switcher sheet.
- Data isolation audit fixes (drafts, mutes, search, notification state); document shared caches.
- Tests: concurrency switching, Keychain unavailable/device locked, large account list.

### Phase 3 (polish)
- UI polish for account switcher (avatars, badges, empty states, errors).
- Notification behavior docs (active-only) and any opt-in handling.
- Manual scenarios: app switch during onboarding, long-lived sessions.
- iCloud Keychain expectation messaging.

### Later
- Manual reordering of accounts.
- Cross-account notification badges/routing.
- Deeper cache partitioning if needed.
