# Cutting a TestFlight build without a GUI

The goal: trigger a TestFlight build by talking to an agentic session on the
studio Mac, from anywhere, with no Xcode window, no Organizer, and no clicking.

Short answer: **yes, and the Xcode Cloud path is the one to use.** Everything
needed is already configured except an App Store Connect API key. Once that key
exists, cutting a build is one HTTP request that Apple's builders service, and
the Mac does not even need to be awake.

There is also a local archive-and-upload path, which works but needs a
distribution certificate this machine does not currently have.

Either way there is a **second step**: both Xcode Cloud workflows stop after
archiving — their own descriptions say they "will NOT publish to TestFlight
groups". Getting a build to testers is a separate App Store Connect call, which
is what `devtools/release/testflight-distribute.py` does. So the full headless
release is two commands, not one.

## The two paths

|                        | Xcode Cloud (recommended)          | Local archive                       |
| ---------------------- | ---------------------------------- | ----------------------------------- |
| Script                 | `devtools/release/xcode-cloud-build.py` | `devtools/release/testflight-upload.sh` |
| Needs the Mac awake    | no                                 | yes                                 |
| Needs a distribution cert locally | no                      | yes — see below                     |
| Build time             | Apple's builders                   | ~2.5 min archive on this Mac        |
| dSYMs to Sentry        | already automatic                  | script does it if `SENTRY_AUTH_TOKEN` is set |
| Signing                | Apple manages it                   | cloud-managed cert, created on first run |
| Pushes to testers      | no — needs step two                | no — needs step two                 |
| Failure surface        | one API call                       | Xcode toolchain, keychain, nix env, network |

### Why Xcode Cloud wins here

Xcode Cloud is already fully wired up for damus and has three enabled
workflows: `PR check`, `Experimental build workflow`, and `Release candidate
build workflow`. `ci_scripts/ci_post_xcodebuild.sh` already runs there and
already uploads dSYMs to Sentry. The remote path therefore reuses a pipeline
that is known-good, rather than standing up a second, subtly different one on
one particular laptop.

It also removes the whole class of failures that come from the Mac being a
laptop: asleep, on a different network, mid-OS-update, or with another agent
session holding the shared DerivedData.

```sh
export ASC_KEY_ID=...  ASC_ISSUER_ID=...

# what can we run?
./devtools/release/xcode-cloud-build.py --list

# cut a release candidate off master and wait for it
./devtools/release/xcode-cloud-build.py "Release candidate build workflow" \
    --branch master --wait
```

`--dry-run` resolves the product, workflow, and branch ids and prints the
`POST /v1/ciBuildRuns` body without starting anything. Use it first.

### The local path

`devtools/release/testflight-upload.sh` archives, exports, and optionally
uploads, all from a plain shell. It defaults to exporting locally; uploading
requires an explicit `--upload` because an upload permanently consumes a build
number in App Store Connect and cannot be undone.

```sh
export ASC_KEY_ID=...  ASC_ISSUER_ID=...

./devtools/release/testflight-upload.sh                    # archive + export, no upload
./devtools/release/testflight-upload.sh --upload --internal-only
```

`--internal-only` sets `testFlightInternalTestingOnly`, which makes the build
ineligible for external TestFlight and the App Store. Use it for anything that
is not a real release candidate.

## Step two: actually pushing to TestFlight

Uploading a build makes it exist in App Store Connect. It does **not** put it in
front of anyone — that needs a group release, which neither Xcode Cloud workflow
does on purpose.

```sh
export ASC_KEY_ID=...  ASC_ISSUER_ID=...

# what is uploaded, and what groups exist
./devtools/release/testflight-distribute.py --list

# notes plus the internal group, on the newest build
./devtools/release/testflight-distribute.py --group Internal \
    --notes-file /tmp/whats-new.txt --wait
```

`Internal` (`b99dead7-12a5-4ca8-b4fa-06aebbf7e677`) is the group to release to.
`--wait` sits through the post-upload processing, which a build must clear before
it can be distributed at all.

Three things about this step that are easy to get wrong:

- **Two groups are both named `Beta Testers`** (`eff35341...` without a public
  link, `144cd6b4...` with one). The script refuses an ambiguous name and makes
  you pass an id, rather than silently picking one and mailing a build to the
  wrong set of people.
- **External groups are not instant.** The first build of a new version needs
  Beta App Review approval before external testers receive it. The submission
  can be automated; Apple's approval cannot, so an external release is never
  fully unattended on the first build of a version.
- **Export compliance must already be answered** or distribution is rejected.
  The script warns rather than answering for you — it is a legal declaration
  about the app, not a checkbox to automate. Recent damus builds are all
  "does not use non-exempt encryption".

## Build numbers: Xcode Cloud owns them

Worth knowing before worrying about burning one. `CURRENT_PROJECT_VERSION` is
`1` in the project and is not what ships: **App Store Connect build numbers are
Xcode Cloud's own run counter.** Builds 1332, 1331, 1330 in App Store Connect
are runs 1332, 1331, 1330. Failed runs skip a number and produce no build, so a
run that never starts costs nothing — the counter moves, no TestFlight build
exists.

For the local path there is no such counter, so either bump the project version
deliberately or pass `--manage-version` and let App Store Connect assign the
next one.

## One-time setup

### 1. An App Store Connect API key (required, and the only real blocker)

This is what makes the whole thing possible: an API key replaces the Apple ID
password entirely, so nothing ever prompts for 2FA. There is no way to do this
headlessly with an Apple ID.

In App Store Connect → Users and Access → Integrations → App Store Connect API,
mint a **Team key** with the **App Manager** role (Admin also works; Developer
does not — it cannot create distribution certificates, and cannot start Xcode
Cloud builds). Then:

```sh
mkdir -p ~/.appstoreconnect/private_keys
mv ~/Downloads/AuthKey_XXXXXXXXXX.p8 ~/.appstoreconnect/private_keys/
chmod 600 ~/.appstoreconnect/private_keys/AuthKey_XXXXXXXXXX.p8
```

That directory is where `xcodebuild`, `altool`, and these scripts all look by
default. Note the `.p8` is downloadable exactly once; Apple will not re-issue
it. A team may hold several keys, so losing one means minting a replacement and
revoking the old one, not losing access.

Both scripts read `ASC_KEY_ID` and `ASC_ISSUER_ID` from the environment. Put
them somewhere a non-interactive shell will pick up — the issuer id is the same
for every key in the team and neither value is secret on its own; the `.p8` is
the secret.

### 2. A distribution certificate (local path only)

This machine currently holds only an `Apple Development` identity, so the
export step fails with:

```
error: exportArchive No signing certificate "iOS Distribution" found
```

`testflight-upload.sh` passes `-allowProvisioningUpdates` with the API key,
which per Apple's own `xcodebuild -help` will "create provisioning profiles and
managed cloud signing certificates as necessary". So the first run with a real
key should mint an `Apple Distribution` certificate and the four App Store
profiles by itself.

Two things to know before that first run: an Apple Distribution certificate is
account-wide state, and a team is limited to a small number of them, so it is
worth checking Certificates, Identifiers & Profiles first rather than
discovering the limit at the worst moment. This step is also the one part of
the local path that has not been executed end to end — see below.

## What was actually tested

Verified on this Mac (Xcode 26.6, build 17F113):

- **Archiving is fully headless.** `xcodebuild archive` with the `damus` scheme,
  `Release` config, and `-destination 'generic/platform=iOS'` produced a
  complete 373 MB `.xcarchive` with all four bundles and all four dSYMs, in
  about 2.5 minutes, from a non-interactive shell. No GUI, no prompts.
- **The login keychain is not a blocker.** It is configured `no-timeout` and was
  readable from a non-interactive shell; `codesign` used the
  `Apple Development` identity without a prompt. No `security unlock-keychain`
  was needed. Worth re-checking over a real ssh session, since this was tested
  from an agent shell inside a logged-in GUI session — a genuinely
  console-less login may behave differently.
- **The nix dev shell must be scrubbed.** Both scripts do this; without it
  `xcodebuild` is not even on `PATH`, and the C targets die on
  `-index-store-path`. See `AGENTS.md`.
- **Export is where it stops today.** `-exportArchive` with
  `method: app-store-connect` fails on the missing distribution certificate, as
  quoted above.
- **The Xcode Cloud path works end to end with a real key.** The API key
  resolves the product and all four workflows, `--branch master` resolves to the
  right git reference, `POST /v1/ciBuildRuns` starts a build, and the poll
  reports `PENDING → RUNNING → COMPLETE` with the right exit code. The product
  and workflow ids matched what had been read out of Xcode's local cache
  exactly.
- **The API key auth path is wired through correctly.** Re-running the export
  with `-allowProvisioningUpdates -authenticationKeyPath/-ID/-IssuerID` and a
  deliberately invalid key changed the failure from a purely local "no profiles
  found" to `Communication with Apple failed`, and the distribution log shows
  Xcode built an account from the key and made a real request:

  ```
  App Store Connect request for store configuration failed for account
  API Key <identifier: ...; issuer: ...>: Unable to authenticate with
  App Store Connect
  ```

  So the flags are accepted and reach Apple; only a valid key is missing.
- **The API client works.** `devtools/release/asc_api.py` signs an ES256 JWT
  with `openssl` and no pip dependencies (the stock python3 here has neither
  `cryptography` nor `PyJWT`), and App Store Connect parses it — a throwaway
  key returns a clean `401 NOT_AUTHORIZED` rather than a malformed-token error.

- **Distribution reads and guards are live-tested.** `--list` enumerates real
  builds and groups; the ambiguous-`Beta Testers` guard, the unknown-group
  error, the expired-build refusal, and the unknown-build-number error were all
  exercised against the live API.

Still not tested:

- **The local path's signing.** Automatic creation of the distribution
  certificate and App Store profiles, and therefore the `destination: upload`
  export, have never run — the local path is still only proven as far as the
  archive. The Xcode Cloud path made it unnecessary to push further.
- **External group distribution** and Beta App Review submission.

## Uploading: which tool

`xcodebuild -exportArchive` with `destination: upload` in the export options
plist is the first-party answer, and what both scripts use. It needs no extra
tooling and takes the same API key as the rest of the flow.

For the record, the alternatives:

- `xcrun altool --upload-app` still works and is not going away. Its deprecation
  was **notarization only** — the notary service stopped accepting altool
  uploads on 1 November 2023, which does not affect App Store uploads. The
  altool shipped in Xcode 26.6 is version 26.40.1 and has gained new commands
  (asset packs), so it is still actively maintained. It supports API-key auth
  via `--api-key`/`--api-issuer`. A reasonable fallback if `destination: upload`
  ever misbehaves.
- `xcrun iTMSTransporter` is present and is what the layers above ultimately
  call. No reason to use it directly.
- fastlane's `pilot`/`deliver` would work, but would mean adding fastlane and a
  Ruby toolchain for no gain — the system Ruby here is 2.6.10, so it would want
  a managed Ruby too. Not worth it for one upload command.

One caveat that bit nothing here but is worth knowing: `xcrun altool
--generate-jwt` hung indefinitely with no output in a non-interactive shell.
`asc_api.py` mints its own token instead, which is why it does not shell out to
altool.

## A gotcha that will happen again

The first API-triggered build failed in nine seconds with `startedDate: null`,
zero actions, and no build produced. That signature — created, never started —
means the run never got a builder, and the two causes here were **a stale Xcode
version pinned in the workflow** and **lapsed GitHub authorization**. The repo
record showed `lastAccessedDate` three months old, which is the tell.

Neither is visible as an error in the API response, so if a triggered build dies
instantly, check the workflow's Xcode version and re-authorize the SCM
connection in App Store Connect before debugging anything else. Both need the
web UI; neither can be fixed from here.

## Where it can still stop and wait for a human

For the remote-from-a-bar use case, these are the places the flow is not
unattended:

1. **Minting the API key.** One-time, needs a browser and a person. Cannot be
   automated. Done.
2. **A stale Xcode version or lapsed SCM auth**, per the section above. Both are
   web-UI fixes and both present as an instant build failure. This is the most
   likely thing to strand a remote release, because nothing warns you until you
   try.
3. **Export compliance**, if a build comes up with it unanswered. Deliberately
   not automated — it is a declaration about the app.
4. **Beta App Review**, for the first build of a version going to external
   testers. The submission is automatable; Apple's approval is not.
5. **The first local-path run**, if it creates a distribution certificate. Worth
   watching once rather than discovering a certificate-limit error remotely.
   Moot while the Xcode Cloud path is the one in use.

Nothing else prompts. Given the key, the full flow is two non-interactive
commands:

```sh
./devtools/release/xcode-cloud-build.py "Release candidate build workflow" \
    --branch master --wait
./devtools/release/testflight-distribute.py --group Internal \
    --notes-file whats-new.txt --wait
```
