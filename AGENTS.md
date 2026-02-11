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

## Crash Investigation Standards

When addressing production crashes reported via TestFlight or crash logs:

### Gold Standard: Local Reproduction ✅

1. Reproduce the crash locally in your development environment
2. Write a test that crashes before the fix is applied
3. Apply the fix
4. Verify the test passes
5. Document the crash scenario and fix in the PR

→ **This meets jb55's "99% merge odds" requirement:**
> "actually having a test that replicates the issue and fails + a fix for that test will increase the odds of merging by 99%"

**Example:** A crash in profile loading that can be triggered by loading a specific malformed profile JSON.

### When Direct Reproduction Is Impossible ⚠️

Some crashes cannot be reproduced in test environments due to:
- **Race conditions** (timing-dependent, hard to trigger deterministically)
- **XCTest limitations** (crashes kill the test process before assertions run)
- **Hardware-specific issues** (memory pressure, device-specific bugs)
- **Production-only state** (specific database corruption, network conditions)

**In these cases, follow the pragmatic approach:**

1. **Link production evidence**
   - Reference the issue number (e.g., #3560)
   - Include crash logs, stack traces, affected device counts
   - Document crash location and frequency

2. **Prove the protection mechanism works**
   - Write tests showing the vulnerability exists (prove the race window)
   - Write tests proving your fix closes the vulnerability
   - Document why direct crash testing isn't feasible

3. **Show how the fix closes the vulnerability window**
   - Explain the crash scenario step-by-step
   - Show what happens WITHOUT your fix (crash path)
   - Show what happens WITH your fix (safe failure path)
   - Prove timing/ordering guarantees if applicable

4. **Plan production monitoring**
   - Note that crash elimination must be verified in TestFlight
   - Consider adding telemetry if appropriate
   - Plan follow-up if crash persists

**Example:** PR #3615 (snapshot marker protocol)
- **Cannot crash in XCTest** (process dies, can't test crashes directly)
- **But proves:** Marker timing closes 10-550ms race window
- **Links:** Issue #3560 (production mdb_page_search+232 crashes in DamusNotificationService)
- **Tests:** `testMarkerProtocol_PreventsProductionCrashScenario()` proves protection works
- **Therefore:** Satisfies pragmatic interpretation of requirement

### Unacceptable Approaches ❌

- Fixing without understanding the root cause
- Guess-and-hope changes based only on stack traces
- No tests whatsoever
- No link to production evidence or issue tracking
- "Let's see if this helps" without analysis

### Crash Investigation Checklist

When working on a crash fix:

- [ ] Link to production evidence (issue number, crash logs)
- [ ] Explain root cause analysis
- [ ] Either reproduce locally OR explain why reproduction is impossible
- [ ] Write tests (either crash reproduction or protection mechanism proof)
- [ ] Document the crash scenario clearly
- [ ] Show before/after behavior
- [ ] Plan production verification

This balances the **ideal** (direct crash reproduction) with **reality** (some crashes can't be reproduced in test environments, but fixes can still be proven correct).
