# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Damus is a decentralized, censorship-resistant social network client for the Nostr protocol, built natively for iOS/macOS using SwiftUI. It's a hybrid Swift + C architecture optimized for performance.

**Supported Platforms:** iOS 16.0+, macOS 13.0+

## Build & Development Commands

### Building
```bash
# Build the project (requires xcbeautify)
just build

# Or using xcodebuild directly
xcodebuild -scheme damus -sdk iphoneos -destination 'platform=iOS Simulator,OS=18.2,name=iPhone 16' -quiet
```

### Testing
```bash
# Run all tests
just test

# Or using xcodebuild directly
xcodebuild test -scheme damus -destination 'platform=iOS Simulator,OS=18.2,name=iPhone 16' -quiet
```

### NostrScript (WebAssembly)
```bash
# Compile TypeScript to WASM
make nostrscript/primal.wasm

# Clean WASM files
make clean
```

### Opening the Project
Open `damus.xcodeproj` in Xcode. The project uses Swift Package Manager for dependencies.

## High-Level Architecture

### Core Architectural Pattern: Hybrid C + Swift

Damus uses a unique architecture combining:
- **NostrDB (C library)**: High-performance local database and event processing engine
- **Swift/SwiftUI**: Business logic, UI, and high-level orchestration

This hybrid approach provides order-of-magnitude performance improvements over pure Swift implementations.

### DamusState: The Central State Container

**Location:** `damus/Core/Storage/DamusState.swift`

`DamusState` is the heart of the application - a centralized state container holding all app-wide state:
- User keypair and authentication
- Event cache, profile cache, DM state
- Network manager, relay pool
- NostrDB instance
- All feature-specific managers (Zaps, Bookmarks, Contacts, etc.)

**Critical Pattern:** `DamusState` is created once in `ContentView.connect()` and passed down through the entire view hierarchy. Never instantiate a new `DamusState` - always use the existing one.

### NostrDB: The C Database Layer

**Location:** `nostrdb/`

NostrDB is a custom-built, high-performance C library that serves as the local database:

**Key Responsibilities:**
- LMDB-based persistent storage
- Multi-threaded event ingestion pipeline (4 ingest threads + 1 writer thread)
- Full-text search
- Memory-mapped event access (zero-copy reads)
- Content parsing into structured blocks (text, mentions, URLs, hashtags)
- Transaction-based MVCC access

**Swift Integration Pattern:**
```swift
// Safe transaction wrapper - auto-closes on scope exit
if let profile_txn = damus_state.ndb.lookup_profile(pubkey) {
    let profile = profile_txn.unsafeUnownedValue
    // Use profile...
} // Transaction automatically closed
```

**Important:** Always use transaction wrappers. Never hold raw NDB pointers across suspension points or outside transaction scopes.

**Database Lifecycle:**
- NDB closes when app enters background (see `ContentView.onChange(of: scenePhase)`)
- NDB reopens when app returns to foreground
- Uses shared app group container: `group.com.damus`

### Networking Architecture

**Three-layer network stack:**

1. **RelayConnection** - Individual WebSocket connection to a relay
2. **RelayPool** - Manages multiple RelayConnection instances, routes requests
3. **NostrNetworkManager** - High-level abstraction with PostBox and SubscriptionManager

**Event Flow:**
```
Relay WebSocket → RelayConnection
    → RelayPool.handle_event()
    → ndb.process_event() (C library)
    → LMDB storage
    → Subscription callbacks
    → UI updates
```

**Key Pattern:** All events from relays are automatically sent to NostrDB for local storage. Never bypass the RelayPool.

### View Architecture

Pure SwiftUI with:
- `NavigationStack` for programmatic routing (iOS 16+)
- `NavigationCoordinator` manages navigation state
- All views receive `damus_state: DamusState` parameter
- Sheet-based modals via `Sheets` enum
- Full-screen presentations via `FullScreenItem` enum

### Feature-Based Organization

**Location:** `damus/Features/`

Code is organized by feature, not by layer (MVC/MVVM):
- `Timeline/` - Home feed
- `Profile/` - User profiles
- `DMs/` - Direct messaging
- `Posting/` - Note composition
- `Zaps/` - Lightning payments
- `Purple/` - Premium subscription
- `Settings/` - App configuration
- `Search/`, `Notifications/`, `Wallet/`, `Relays/`, etc.

Each feature contains its own Views, Models, and utilities. Features communicate via:
- Notifications (NotificationCenter-based)
- Shared DamusState

### Notification-Based Communication

**Location:** `damus/Notify/Notify.swift`

Features communicate via typed notifications:
```swift
// Send notification
notify(.follow(target))

// Receive notification
.onReceive(handle_notify(.follow)) { target in
    handle_follow_notif(state: state, target: target)
}
```

Common notifications: `.post`, `.follow`, `.unfollow`, `.mute`, `.zapping`, `.broadcast`

### Dual Event Model

Two representations of Nostr events:

1. **NdbNote** (from NostrDB)
   - Memory-mapped from LMDB
   - Zero-copy access
   - C-based representation
   - Use for reading existing events

2. **NostrEvent** (Swift struct)
   - JSON serializable
   - Use for creating new events
   - Converted to NdbNote after ingestion

## Important Development Patterns

### Pattern 1: Always Pass DamusState
Every view and model should receive `DamusState` as a parameter. Don't create separate state managers.

### Pattern 2: Use NDB Transactions Safely
Always access NostrDB through transaction wrappers. The `NdbTxn` wrapper auto-closes on scope exit.

### Pattern 3: Query NostrDB First
Use NDB's native query capabilities instead of in-memory filtering for performance:
```swift
// Good: Query NDB directly
let notes = damus_state.ndb.query(filter: filter)

// Bad: Load everything, then filter in Swift
let all = loadAllNotes().filter { ... }
```

### Pattern 4: Relay Pool Abstraction
Never directly access WebSockets. Always use RelayPool which handles:
- Relay selection (read vs write relays)
- Automatic retries
- NDB synchronization
- Connection management

### Pattern 5: Content Blocks
NostrDB pre-parses note content into structured blocks during ingestion. Use these blocks instead of re-parsing:
```swift
if let blocks = note.blocks(ndb: damus_state.ndb) {
    // Iterate pre-parsed blocks: text, mentions, URLs, hashtags
}
```

## Nostr Implementation Details

### NIP Support
Damus implements: NIP-01 (basic protocol), NIP-04 (encrypted DMs), NIP-08 (mentions), NIP-10 (reply conventions), NIP-12 (hashtags), NIP-19 (bech32 IDs), NIP-21 (nostr: URI), NIP-25 (reactions), NIP-42 (relay auth), NIP-56 (reporting), NIP-65 (relay lists)

See README.md for full list with links.

### Key Types
- **Pubkey** - Public key (32 bytes)
- **Privkey** - Private key (32 bytes)
- **NoteId** - Event ID (32 bytes)
- **Keypair** - Holds pubkey + optional privkey
- **NostrFilter** - Query filter for events
- **NostrKind** - Event type enum (metadata, text_note, etc.)

### Relay Management
User relay lists are managed via NIP-65. The `RelayFilters` system allows per-timeline relay filtering.

## Translation & Localization

All user-facing strings must have comments for translators:
```swift
// With comment parameter
Text("Hello", comment: "Greeting shown on launch")

// Or using NSLocalizedString
NSLocalizedString("Post", comment: "Button to publish a note")
```

Translations managed via Transifex: https://explore.transifex.com/damus/damus-ios/

## Git Workflow & Commit Guidelines

### Commit Message Format
- Use imperative mood: "Add feature" not "Added feature" or "Adds feature"
- Keep commits focused on one logical change
- Reference issues: `Closes: https://github.com/damus-io/damus/issues/1234`
- For bug fixes: `Fixes: abc123def456 ("Description of broken commit")`

### Sign Your Commits
```bash
git commit -s
```

This adds `Signed-off-by:` line certifying you have rights to submit the code.

### User-Facing Changes
Include changelog tags in commit messages:
```
Changelog-Added: Cool new feature
Changelog-Fixed: Notes not appearing on profile
Changelog-Changed: Heart button to shaka
Changelog-Removed: Old deprecated feature
```

### Patch Guidelines
- One logical change per commit
- Separate bug fixes from new features
- Build must succeed after each commit (for git bisect)
- Include patch changelogs between versions

See `docs/CONTRIBUTING.md` for detailed patch submission guidelines (follows Linux kernel style).

## Special Considerations

### Purple Subscription
Damus Purple is the premium subscription tier with exclusive features. Code is in `damus/Features/Purple/`. Features should gracefully degrade when Purple is not active.

### Lightning Integration
Native Lightning support via:
- **LNURL** - Lightning addresses and payment requests
- **NWC (Nostr Wallet Connect)** - Remote wallet control
- **Zaps** - Nostr-native Lightning payments (NIP-57)

Wallet state managed in `damus_state.wallet`.

### Testing
Test files in `damusTests/` directory. Run tests with `just test` or via Xcode.

### Developer Mode
Enable in Settings for additional debugging features and tips reset.

### Image Caching
Kingfisher is used for image loading/caching with custom cache path in shared container.

## Common Gotchas

1. **Background Database Access:** NDB is closed when app backgrounds. Don't hold transactions across app lifecycle changes.

2. **Transaction Lifetime:** Never store `unsafeUnownedValue` references beyond transaction scope.

3. **Relay Connections:** RelayPool automatically reconnects. Don't implement manual reconnection logic.

4. **Event Validation:** NostrDB validates events on ingestion. Invalid events are rejected automatically.

5. **Memory-Mapped Notes:** NdbNote data is memory-mapped from disk. It's fast but tied to transaction lifetime.

## Project Structure Reference

```
damus/
├── damus/
│   ├── Core/           # Core infrastructure
│   │   ├── Nostr/      # Nostr protocol implementation
│   │   ├── Networking/ # Network layer
│   │   ├── NIPs/       # Nostr Improvement Proposals
│   │   ├── Storage/    # DamusState and persistence
│   │   └── Types/      # Core type definitions
│   ├── Features/       # Feature-based organization (26+ features)
│   ├── Models/         # Shared models
│   ├── Views/          # Shared views
│   ├── Shared/         # Shared utilities
│   ├── Notify/         # Notification system
│   └── ContentView.swift  # Root view and app coordinator
├── nostrdb/            # C database library (LMDB + ingester)
├── damus-c/            # C utilities
├── flatbuffers/        # Profile serialization
├── nostrscript/        # WebAssembly scripting
├── damusTests/         # Unit tests
└── DamusNotificationService/  # Push notification extension
```

## Resources

- Nostr Protocol: https://github.com/fiatjaf/nostr
- NIPs (Nostr Implementation Possibilities): https://github.com/nostr-protocol/nips
- Damus Website: https://damus.io
- Issues: https://github.com/damus-io/damus/issues
- Mailing Lists: https://damus.io/list/dev (dev), https://damus.io/list/patches (patches)
