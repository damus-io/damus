# Testing the resumable TUS upload client

`damus/Shared/Media/Upload/Tus/` is a hand-rolled [tus 1.0.0][spec] client used
to push large videos straight to the hosting provider, bypassing Damus
infrastructure. Because the interesting behaviour is a *negotiation* — the
server is the authority on how many bytes it has — the tests run against a real
tus server rather than a mock that would agree with whatever the client did.

[spec]: https://tus.io/protocols/resumable-upload

## Running a local server

Either works; the tests default to `http://127.0.0.1:1080/files/`.

```sh
tusd -host 127.0.0.1 -port 1080 -upload-dir /tmp/tusd-data
docker run -p 1080:1080 tusproject/tusd
```

Point elsewhere (a Bunny Stream library, say) with `TUS_TEST_ENDPOINT`.

## The ordinary test run

```sh
xcodebuild -project damus.xcodeproj -scheme damus \
  -destination 'platform=iOS Simulator,id=<UDID>' \
  -only-testing:damusTests/TusProtocolTests \
  -only-testing:damusTests/TusUploadStoreTests \
  -only-testing:damusTests/TusUploadClientTests \
  test-without-building
```

- `TusProtocolTests` — request construction, `Upload-Metadata` encoding,
  response parsing, retry classification, backoff. Pure; no server needed.
- `TusUploadStoreTests` — durability of the resume record: round trip, hostile
  upload ids, tolerance of a half-written file, and re-anchoring the source path
  when the app container's UUID changes across installs.
- `TusUploadClientTests` — end to end against the server. **Skips** rather than
  fails when no server is reachable, so CI stays green.

## The large-file soak

Opt in with a size in megabytes. Interrupts the upload three times at increasing
offsets and asserts each resume picks up where it left off:

```sh
TEST_RUNNER_TUS_LARGE_FILE_MB=850 xcodebuild ... \
  -only-testing:damusTests/TusUploadClientTests/testLargeFileSurvivesRepeatedInterruptions \
  test-without-building
```

## The process-kill verification

This is the one that proves the feature. A resume that only survives a `pause()`
is not worth much; what has to survive is the process going away. That cannot be
done inside a single test process, so it is two runs with a `kill -9` between
them, and phase B knows nothing about phase A except what it finds on disk.

```sh
# 1. start an 850 MB upload and block
TEST_RUNNER_TUS_KILL_TEST_MB=850 xcodebuild ... \
  -only-testing:damusTests/TusProcessKillTests/testPhaseA_startLargeUploadAndBlockUntilKilled \
  test-without-building &

# 2. once the log shows enough confirmed bytes, kill the app outright
xcrun simctl terminate <UDID> com.jb55.damus2

# 3. a cold process resumes from the record that survived
TEST_RUNNER_TUS_KILL_TEST_MB=850 xcodebuild ... \
  -only-testing:damusTests/TusProcessKillTests/testPhaseB_resumeAfterProcessKill \
  test-without-building
```

Phase A prints `TUS-KILL-TEST: offset=<n>/<total>` as it goes, which is what the
driver polls to decide when to kill. Phase B asserts that the surviving record
still reads `.uploading`, that progress never drops below the offset at the
kill, and that the server's finished copy matches the source file by SHA-256.

Phase A is *expected* to fail when it is killed — and it deliberately fails if
it is **not** killed, which is what catches a file too small to span the kill.

### Interpreting a failure

- `no record survived the kill` — the store never got written; look at
  `TusUploadStore.save` and the phase A log.
- `phase A finished; nothing to resume` — the file uploaded faster than the
  driver's poll. Use a bigger `TUS_KILL_TEST_MB`.
- `restarted from scratch instead of resuming at <n>` — the real regression this
  whole file exists to catch.

## What is not covered here

Airplane mode. A simulator has no radio to turn off, so the tests substitute
transport failure (stopping the tus server mid-upload) which exercises the same
retry and re-`HEAD` path. Verifying the real thing needs a device.
