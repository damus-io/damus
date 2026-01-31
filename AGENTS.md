# Agents

## Damus Overview

Damus is an iOS client built around a local relay model ([damus-io/damus#3204](https://github.com/damus-io/damus/pull/3204)) to keep interactions snappy and resilient. The app operates on `nostrdb` ([source](https://github.com/damus-io/damus/tree/master/nostrdb)), and agents working on Damus should maximize usage of `nostrdb` facilities whenever possible.

## Codebase Layout

- `damus/` contains the SwiftUI app. Key subdirectories: `Core` (protocol, storage, networking, nostr primitives), `Features` (feature-specific flows like Timeline, Wallet, Purple), `Shared` (reusable UI components and utilities), `Models`, and localized resources (`*.lproj`, `en-US.xcloc`).
- `nostrdb/` hosts the embedded database. Swift bindings (`Ndb.swift`, iterators) wrap a C/LMDB core; prefer these abstractions when working with persistence or queries.
- `damus-c/` bridges C helpers (e.g., WASM runner) into Swift; check `damus-Bridging-Header.h` before adding new bridges.
- `nostrscript/` contains AssemblyScript sources compiled to WASM via the top-level `Makefile`.
- Tests live in `damusTests/` (unit/snapshot coverage) and `damusUITests/` (UI smoke tests). Keep them running before submitting changes.

## Development Workflow

- Use `just build` / `just test` for simulator builds and the primary test suite (requires `xcbeautify`). Update or add `just` recipes if new repeatable workflows emerge.
- Xcode project is `damus.xcodeproj`; the main scheme is `damus`. Ensure new targets or resources integrate cleanly with this scheme.
- Rebuild WASM helpers with `make` when touching `nostrscript/` sources.
- Follow `docs/DEV_TIPS.md` for debugging (enabling Info logging, staging push notification settings) and keep tips updated when discovering new workflows.

## Testing Expectations

- Provide a concrete test report in each PR (see `.github/pull_request_template.md`). Document devices, OS versions, and scenarios exercised.
- Add or update unit tests in `damusTests/` alongside feature changes, especially when touching parsing, storage, or replay logic.
- UI regressions should include `damusUITests/` coverage or rationale when automation is impractical.
- Snapshot fixtures under `damusTests/__Snapshots__` must be regenerated deliberately; explain updates in commit messages.

## Contribution Standards

- Sign all commits (`git commit -s`) and include appropriate `Changelog-*`, `Closes:`, or `Fixes:` tags as described in `docs/CONTRIBUTING.md`.
- Keep patches scoped: one logical change per commit, ensuring the app builds and runs after each step.
- Favor Swift-first solutions that lean on `nostrdb` types (`Ndb`, `NdbNote`, iterators) before introducing new storage mechanisms.
- Update documentation when workflows change, especially this file, `README.md`, or developer notes.

## Agent Requirements

1. Code should tend toward simplicity.
2. Commits should be logically distinct.
3. Commits should be standalone.
4. Code should be human readable.
5. Code should be human reviewable.
6. Ensure docstring coverage for any code added, or modified.
7. Review and follow `pull_request_template.md` when creating PRs for iOS Damus.
8. Ensure nevernesting: favor early returns and guard clauses over deeply nested conditionals; simplify control flow by exiting early instead of wrapping logic in multiple layers of `if` statements.
9. Before proposing changes, please **review and analyze if a change or upgrade to nostrdb** is beneficial to the change at hand.
10. **Never block the main thread**: All network requests, database queries, and expensive computations must run on background threads/queues. Use `Task { }`, `DispatchQueue.global()`, or Swift concurrency (`async/await`) appropriately. UI updates must dispatch back to `@MainActor`. Test for hangs and freezes before submitting.
11. Cherry-pick commits — when incorporating work from other branches or contributors, use git cherry-pick to preserve original authorship rather than copying code manually.
12. Commits which have code which contain fixes or refactors which were introduced in the same PR should be rebased such that the fixes are added to the original code history.
13. Verify that existing code that can do the job is not ignored (in lieu of creating code that performs the same function of existing code).
14. Do not accrue duplicate code. Always revisit how existing code can be applied and/or refactored in solving new issues.
15. Always prefer simplicity One line of code is better than ten. Ten is better than a hundred. A commit with ten thousand lines of code is not reviewable by a human developer. A thousand line commit will be avoided unless it saves someone's life.
16. Do not fudge CI tests, to get a commit or PR to pass. Instead identify the underlying root cause of CI failure, and address that.
