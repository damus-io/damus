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

1. **Always prefer simplicity.** One line of code is better than ten. Ten is better than a hundred. A thousand-line commit will be avoided unless it saves someone's life. Reuse existing code; do not accrue duplicates. Always revisit how existing code can be applied or refactored before writing new code that performs the same function.
2. Commits should be logically distinct and standalone.
3. Code should be human-readable and human-reviewable.
4. Ensure docstring coverage for any code added or modified.
5. Review and follow `.github/pull_request_template.md` when creating PRs for iOS Damus. Include a **line count breakdown** in the PR body showing lines of test code vs non-test code (e.g., "420 lines test, 80 lines implementation") so reviewers can gauge review effort at a glance.
6. Ensure nevernesting: favor early returns and guard clauses over deeply nested conditionals; simplify control flow by exiting early instead of wrapping logic in multiple layers of `if` statements.
7. Before proposing changes, please **review and analyze if a change or upgrade to nostrdb** is beneficial to the change at hand.
8. **Never block the main thread.** All network requests, database queries, and expensive computations must run on background threads/queues. Use `Task { }`, `DispatchQueue.global()`, or Swift concurrency (`async/await`) appropriately. UI updates must dispatch back to `@MainActor`. Never perform blocking work inside SwiftUI view `body` properties. Test for hangs and freezes before submitting.
9. **Prefer actors over locks.** Use Swift actor isolation for thread-safe state instead of `NSLock`, `DispatchSemaphore`, or `os_unfair_lock`. Locks held across `await` points or UI updates cause hangs and frame drops.
10. **Guard against actor reentrancy.** Code inside an actor can suspend at any `await` and re-enter before the first call completes. Never assume actor state is unchanged after an `await`; re-validate or capture state before suspension points.
11. **Handle task cancellation.** Check `Task.isCancelled` or call `try Task.checkCancellation()` in long-running and looping async work. Propagate `CancellationError` through task hierarchies so cancelled network requests, database queries, and background work clean up promptly.
12. **Apply `Sendable` correctly.** Types crossing actor isolation boundaries must conform to `Sendable`. Prefer value types for cross-boundary data. Use `@unchecked Sendable` sparingly and only with a documented justification for why it is safe.
13. **Keep SwiftUI view identity stable.** Use explicit, stable identifiers in `ForEach` — never array indices. Choose the correct property wrapper for the job: `@State` for view-local state, `@Binding` for parent-child data flow, `@Observable`/`@Bindable` for shared state. Avoid redundant state updates that trigger excessive re-renders.
14. **Accessibility.** All interactive elements must have a minimum touch target of 44×44 points. Support Dynamic Type — text must resize with the user's preferred font size. Provide `.accessibilityLabel` and appropriate traits for all interactive and informative elements so VoiceOver users can navigate the app.
15. Cherry-pick commits — when incorporating work from other branches or contributors, use `git cherry-pick` to preserve original authorship rather than copying code manually.
16. Commits containing fixes or refactors for code introduced in the same PR should be rebased so that the fixes are incorporated into the original commit history.
17. Do not fudge CI tests to get a commit or PR to pass. Instead, identify the underlying root cause of CI failure and address that.
18. **Test coverage for new code.** All new features, bug fixes, and behavioral changes must include corresponding test cases. Tests should:
    - Cover the happy path and relevant error paths
    - Be deterministic and not flaky
    - Use real test data where possible (e.g., actual invoice strings from reported issues)
    - Validate edge cases identified during debugging (e.g., boundary conditions like `MAX_PREFIX` limits)
    - Be runnable in CI without manual intervention
19. PRs without test coverage for new code paths will not be merged unless the code is demonstrably untestable (e.g., pure UI layout) and this is documented in the PR description.
20. Having a test that replicates the issue and fails + a fix for that test will increase the odds of merging by 99%.
21. **Run a code-simplifier pass** before submitting PRs. See [`docs/code-simplifier.md`](docs/code-simplifier.md) for the full protocol.
