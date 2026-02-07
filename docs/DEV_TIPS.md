# Dev tips

A collection of tips when developing or testing Damus.

## Logging

- Info and debug messages must be activated in the macOS Console to become visible, they are not visible by default. To activate, go to Console > Action > Include Info Messages.

## Testing push notifications

- Dev builds (i.e. anything that isn't an official build from TestFlight or AppStore) only work with the development/sandbox APNS environment. If testing push notifications on a local damus build, ensure that:
  - Damus is configured to use the "staging" push notifications environment, under Settings > Developer settings.
  - Ensure that Nostr events are sent to `wss://notify-staging.damus.io`.

## GitHub Actions CI

A CI workflow is included at `.github/workflows/ci.yml` to validate pull requests.

### What it does

- **Triggers:** Runs on push and pull request to `master` and `main` branches.
- **Runner:** Uses `macos-14` with Xcode 15 (via `maxim-lobanov/setup-xcode`).
- **Build:** Compiles the `damus` scheme for iOS Simulator (iPhone 15) without code signing.

### Usage

The workflow runs automatically on PRs. To manually trigger, push to `master` or create a PR.

### Troubleshooting

- If the build fails due to Xcode version, update the `xcode-version` input in the workflow file.
- For first-time fork contributors, a maintainer must approve the workflow run.
