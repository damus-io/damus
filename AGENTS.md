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

## Submission Format

Submit work as **topic branches** — a single branch containing a series of logically ordered commits addressing one coherent theme (e.g., "bug fixes", "zap improvements", "thread safety"). Submit each topic branch as one PR with instructions to review commit-by-commit.

### Commit ordering

- Each commit must build, pass tests, and be independently bisectable.
- Earlier commits in the series are foundations; later commits build on them.
- A reviewer can merge any prefix of the series — commit N must not depend on commit N+1.
- Order by: infrastructure first, then features, then polish.

### Topic scope

Group related changes into one branch. Do not mix unrelated features. A "zap improvements" branch should not contain accessibility fixes for the profile screen.

### PR description for a series

The PR body should list each commit with a one-line summary and its line count breakdown, so reviewers know the size and scope of each step:

```
## Commits (review commit-by-commit)

1. `abc1234` — nip57: include lnurl param in callback (8 impl, 0 test)
2. `def5678` — Add rate limit retry with backoff (45 impl, 12 test)
3. `ghi9012` — Add NWC timeout handling (30 impl, 25 test)

Total: 83 impl, 37 test
```

## Agent Requirements

### Code quality

1. **Always prefer simplicity.** One line of code is better than ten. Ten is better than a hundred. The fewer lines of code, the greater the merge probability. Reuse existing code; do not accrue duplicates. Always revisit how existing code can be applied or refactored before writing new code that performs the same function.
2. **Commits must be logically distinct, standalone, and ordered.** Each commit in a series must build and pass tests independently. A reviewer can merge any prefix of the series. Later commits may depend on earlier ones, but never the reverse. Do not mix unrelated changes in one commit.
3. Code should be human-readable and human-reviewable.
4. Add docstrings only for non-obvious behavior and public APIs where the intent is not self-evident.
5. Ensure nevernesting: favor early returns and guard clauses over deeply nested conditionals.
6. Before proposing changes, **review and analyze if a change or upgrade to nostrdb** is beneficial to the change at hand.
7. **Do not duplicate existing work.** Before writing new infrastructure (views, managers, utilities), search the codebase and open PRs for existing implementations. If a PR already provides the functionality, depend on it rather than reimplementing.

### Swift and iOS standards

8. **Never block the main thread.** All network requests, database queries, and expensive computations must run on background threads/queues. UI updates must dispatch back to `@MainActor`. Never perform blocking work inside SwiftUI view `body` properties. Test for hangs and freezes before submitting.
9. **Follow the Swift coding standards** in [`docs/code-simplifier.md`](docs/code-simplifier.md) covering: actor isolation over locks, actor reentrancy guards, task cancellation, `Sendable` correctness, SwiftUI view identity, accessibility (44pt touch targets, Dynamic Type, VoiceOver), memory/lifecycle management, and Xcode project hygiene.
10. **Run a code-simplifier pass** before submitting. See [`docs/code-simplifier.md`](docs/code-simplifier.md) for the full protocol.

### Git workflow

11. Review and follow `.github/pull_request_template.md` when creating PRs. For topic branches with multiple commits, include a **per-commit line count table** in the PR body so reviewers can gauge effort at each step.
12. Cherry-pick commits — when incorporating work from other branches, use `git cherry-pick` to preserve original authorship rather than copying code manually.
13. Before final submission, squash fixup commits into the original commit they correct. Temporary fixups during review are fine, but the final series must not contain standalone "fix" commits.
14. Do not fudge CI tests to get a commit or PR to pass. Identify the underlying root cause and address that.

### Testing

15. **Test coverage for new code.** All new features, bug fixes, and behavioral changes must include corresponding test cases. Tests must:
    - Include at least one assertion that can fail (`XCTAssert*`, `XCTFail`, or project-standard helper). `print()` is not an assertion. `fulfill()` alone is not an assertion.
    - Test the code that actually ships, not code you removed. Do not write tests that exercise deleted code paths or reference removed APIs.
    - Use `do/catch` only around throwing code. Failable initializers (`init?`) return `nil` — they do not throw.
    - Use `XCTSkip` when a test requires a compile flag. Do not silently `print("skipped")`.
    - Meet the same thread-safety standards as production code. No data races in tests.
    - Cover the happy path and relevant error paths.
    - Be deterministic, not flaky.
    - Use real test data where possible.
    - Be runnable in CI without manual intervention.
16. PRs without test coverage for new code paths will not be merged unless the code is demonstrably untestable (e.g., pure UI layout) and this is documented in the PR description.
17. **Bug fix commits must include a regression test that fails before the fix and passes after.** This is not optional. A test that only passes proves nothing about the fix.
18. **Pre-submit test audit.** Before marking a PR ready for review, verify every test:
    1. Revert the fix, run the test, and capture the failure output. Re-apply the fix, run the test, and capture the pass output. Include both results in the audit. If the test does not fail without the fix, it proves nothing — rewrite it.
    2. Does every test have at least one assertion that can fail?
    3. Does the test reference any API or behavior this PR removes? If so, rewrite it.
    4. Are there `do/catch` blocks around non-throwing code? Remove them.
    5. Are there `#if FLAG` blocks that silently skip? Replace with `XCTSkip`.
