# Cutting a TestFlight build without a GUI

The goal: trigger a TestFlight build by talking to an agentic session on the
studio Mac, from anywhere, with no Xcode window, no Organizer, and no clicking.

Short answer: **yes, and the Xcode Cloud path is the one to use.** This has now
been done end to end: build 1335 was triggered, built, uploaded and released to
the `Internal` TestFlight group entirely from the command line, without opening
Xcode. Cutting a build is one HTTP request that Apple's builders service, so the
Mac does not even need to be awake.

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
| Signing                | Apple manages it                   | cloud-managed cert, created on first run |
| Pushes to testers      | no — needs step two                | no — needs step two                 |
| Failure surface        | one API call                       | Xcode toolchain, keychain, nix env, network |

### Why Xcode Cloud wins here

Xcode Cloud is already fully wired up for damus and has three enabled
workflows: `PR check`, `Experimental build workflow`, and `Release candidate
build workflow`. The remote path therefore reuses a pipeline that is
known-good, rather than standing up a second, subtly different one on one
particular laptop.

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
Notes are written to **every locale the build has**, because a locale left blank
renders as no release notes at all for testers who see it. That matters here:
damus's `primaryLocale` is **`en-CA`**, not `en-US`, and App Store Connect shows
the primary locale — writing only `en-US` produces a build whose notes look
empty, which is what happened to build 1338 before this was fixed. `--locale`
narrows it to one when you want that.
`--wait` sits through the post-upload processing, which a build must clear before
it can be distributed at all.

Three things about this step that are easy to get wrong:

- **Two groups are both named `Beta Testers`** (`eff35341...` without a public
  link, `144cd6b4...` with one). The script refuses an ambiguous name and makes
  you pass an id, rather than silently picking one and mailing a build to the
  wrong set of people.
- **Only the release-candidate workflow produces externally-distributable
  builds.** This is the trap. `Experimental build workflow` and `PR check`
  archive with `buildDistributionAudience: INTERNAL_ONLY`, and that is baked
  into the build — it shows as `buildAudienceType: INTERNAL_ONLY` and can
  *never* be added to an external group, no matter what you do to it
  afterwards. Only `Release candidate build workflow` archives as
  `APP_STORE_ELIGIBLE`. `--list` prints the audience per build, and the script
  refuses an internal-only build with an explanation instead of letting you
  chase a review or permissions problem that does not exist. The local path's
  equivalent knob is `--internal-only`.
- **External groups may not be instant.** A version that has never cleared Beta
  App Review needs it before external testers get the build; a later build of an
  already-approved version is normally accepted without a fresh submission.
  `--submit-for-review` submits when Apple asks for it. The submission is
  automatable; approval is not.
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

### Which commit is in which build

Because Apple assigns the number, nothing in the repository says what went into
build 1338 — and the answer is perishable. The commit lives on the Xcode Cloud
*run*, never on the build, and Apple keeps only the last handful of runs: at
the time of writing the product listed six, back to 1333, so **builds 1332 and
earlier can no longer be mapped through the API at all**.

So this is recorded automatically, in two places, as annotated `build/<number>`
git tags:

1. **`ci_scripts/ci_post_xcodebuild.sh`**, on the builder, at the one moment
   both halves are known. Tags `$CI_COMMIT` as `build/$CI_BUILD_NUMBER` and
   pushes it, for any archive action that is not a pull request build. This
   catches builds however they were started — the script, the web UI, a branch
   push — and needs no Mac.
2. **`xcode-cloud-build.py`**, whenever it is already waiting for a build. Same
   tag, from the App Store Connect side, pushed to whichever remote points at
   the upstream repository. Belt and braces for the hook, and the half that
   works without a push token.

Whichever gets there first wins; the other reports the tag as already written.
Then the questions answer themselves:

```sh
git show build/1338                 # the commit that shipped as 1338
git log build/1337..build/1338      # what a tester got between two builds
git tag --contains <sha>            # which builds carry this fix
git describe --match 'build/*'      # the last build at or before HEAD
```

`devtools/release/tag-builds.py` is the manual backstop, for auditing the
mapping or repairing it:

```sh
./devtools/release/tag-builds.py --list     # what ASC knows, what is tagged
./devtools/release/tag-builds.py --push     # write and push what is missing
./devtools/release/tag-builds.py --build 1332 --commit 6a1c0de9f2b1
```

That last form records a build whose run has already aged out, where nothing
automatic can help any more.

**The mapping is read, not guessed.** `/v1/ciProducts/<p>/buildRuns` carries
`sourceCommit.commitSha`, and `/v1/ciBuildRuns/<run>/builds` names the build
that run actually produced. Going through the second hop rather than assuming
build number == run number is what makes it right for the two cases that keep
happening here: run 1334 started, `FAILED`, and produced no build, while 1337
and 1338 both report `FAILED` and produced perfectly good builds.

#### The hook cannot be allowed to fail

`ci_post_xcodebuild.sh` runs after the archive action and **before Xcode Cloud
uploads the archive**, so a non-zero exit throws away a finished build. This is
the same file, at the same path, that discarded every build for three months
when the Sentry install inside it failed under `set -eu` (296f3bddd4f8). So the
new one has no `set -e`, tolerates every failure individually, never lets git
prompt for a credential (`GIT_TERMINAL_PROMPT=0`, or a missing credential hangs
the archive until the run times out), and ends in an unconditional `exit 0`. A
missing tag is a footnote; a discarded release build is a wasted evening.

#### The push token

Pushing from the builder needs a credential the checkout does not have. Set a
GitHub token with `contents:write` as a **secret** environment variable named
`GITHUB_TAG_PUSH_TOKEN` on each workflow that archives. Xcode Cloud environment
variables are UI-only — `CiWorkflow` has no `environmentVariables` attribute in
the App Store Connect API, so this cannot be scripted:

> App Store Connect → Xcode Cloud → Manage Workflows → *(workflow)* →
> Environment → Add variable, tick **Secret**.

Until that exists the hook still tries the checkout's own credentials and says
in the build log whether it worked, so the first build after this lands will
answer whether a token is needed at all. If the push fails, the tag exists only
on the builder and dies with it — `tag-builds.py --push` recovers it, as long
as it is run before the run ages out.

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

Both scripts read `ASC_KEY_ID` and `ASC_ISSUER_ID` from the environment. The
issuer id is the same for every key in the team, and neither value is secret on
its own — the `.p8` is the secret.

`.envrc` sources a gitignored `.privenv`, so direnv supplies them and the
scripts run with no env prefix. Create one per worktree:

```sh
cat > .privenv <<'ENV'
export ASC_KEY_ID=...
export ASC_ISSUER_ID=...
export ASC_KEY_PATH=$HOME/projects/damus/ios-deploy-keys/AuthKey_....p8
ENV
chmod 600 .privenv
direnv allow
```

The `source .privenv || :` in `.envrc` is a no-op where the file is absent, so
checkouts without credentials are unaffected. Note direnv only watches files it
loads with `dotenv`/`source_env`; with plain `source` you need `direnv allow`
again after editing `.privenv`.

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
- **The whole chain ran for real.** Build 1335 was triggered from the command
  line on the `headless-release` branch, succeeded on Apple's builders, uploaded
  to App Store Connect, and was then given What to Test notes and released to
  the `Internal` group — all without opening Xcode. It was the first successful
  Xcode Cloud build since 2026-06-03.

Still not tested:

- **External group distribution.** Only the `Internal` group has been released
  to, and it could not have been otherwise: build 1335 came from the
  experimental workflow, so it is `INTERNAL_ONLY` and is permanently ineligible
  for external groups. Proving the external path needs a build from the
  release-candidate workflow — which is a real 1.18 release candidate, so it
  belongs to the release, not to this spike.
- **The local path's signing.** Automatic creation of the distribution
  certificate and App Store profiles, and therefore the `destination: upload`
  export, have never run — the local path is still only proven as far as the
  archive. The Xcode Cloud path made it unnecessary to push further.

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

## Why no Xcode Cloud build has succeeded since June

The first real API-triggered build, 1334, archived cleanly and even produced an
`app-store.zip` export — then failed anyway, because the post-build hook
`ci_scripts/ci_post_xcodebuild.sh` exited 1:

```
Installation path: /usr/local/bin/sentry-cli
sudo: a terminal is required to read the password
sudo: a password is required
```

The sentry-cli installer defaults to `/usr/local/bin`, which it can only write
with `sudo`, and an Xcode Cloud builder has no tty to take a password. Under
`set -eu` that aborted the script, which failed the whole action, which meant
the finished archive was never uploaded to App Store Connect.

Two things made this worse than it looks. The install ran *before* the
`SENTRY_AUTH_TOKEN` check, so the script failed even with Sentry entirely
unconfigured — every one of its careful `warning: ... skipping` guards was
unreachable dead code. And it failed *after* a successful archive, so the build
looked like a compile problem rather than a five-line shell bug.

The hook landed 2026-04-30 and the last successful build was 2026-06-03, which
is consistent with this having quietly blocked releases ever since.

The hook has been removed rather than fixed — that was the call. Note the
Sentry SDK is still linked into the app, so crash reports still arrive; they
will just be unsymbolicated, because nothing uploads dSYMs any more. Removing
the SDK, or restoring dSYM uploads by setting `INSTALL_DIR` to somewhere
writable, are both separate decisions.

## Where it can still stop and wait for a human

For the remote-from-a-bar use case, these are the places the flow is not
unattended:

1. **Minting the API key.** One-time, needs a browser and a person. Cannot be
   automated. Done.
2. **A stale Xcode version or lapsed SCM auth**, per the section above. Both are
   web-UI fixes and both present as an instant build failure. This is the most
   likely thing to strand a remote release, because nothing warns you until you
   try.
3. **Export compliance** — fixed at the source, so this should no longer stop
   anyone. `ITSAppUsesNonExemptEncryption` was absent from the project, so every
   build arrived unanswered and had to be clicked by hand before it could reach
   testers. It is declared in `damus/Info.plist` now, and future builds arrive
   pre-answered. The scripts still only warn and never answer it: it is a
   declaration about the app, not a checkbox to automate.
4. **Beta App Review**, for the first build of a version going to external
   testers. The submission is automatable; Apple's approval is not.
5. **The first local-path run**, if it creates a distribution certificate. Worth
   watching once rather than discovering a certificate-limit error remotely.
   Moot while the Xcode Cloud path is the one in use.
6. **The `GITHUB_TAG_PUSH_TOKEN` secret**, one-time, per archiving workflow. Not
   in the release path at all — without it a build still cuts and still ships,
   it just may not manage to push its `build/<number>` tag from the builder.
   Xcode Cloud environment variables have no API, so a person has to set it.

Nothing else prompts. Given the key, the full flow is two non-interactive
commands:

```sh
./devtools/release/xcode-cloud-build.py "Release candidate build workflow" \
    --branch master --wait
./devtools/release/testflight-distribute.py --group Internal \
    --notes-file whats-new.txt --wait
```
