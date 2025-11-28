# Offline Media Upload Plan for Outbox

- **Add Media Queue Layer** – Introduce a `PendingMediaStore` similar to `PendingPostStore`, capturing local file URLs, target hosting info, and note references; persist queue on disk and expose APIs for enqueue/remove/status updates.

- **Offline Composer Flow** – When a user inserts an image while offline, save the image data locally (e.g., in `FileManager`), enqueue a `PendingMedia` record, and reference a temporary `mediaId` in the pending note payload so the note can still be queued/drafted.

- **Upload Orchestrator** – Create a `MediaUploadManager` that monitors reachability; once at least one relay/network link is available, it uploads queued media to the configured host, updates the resulting remote URLs back into the pending note(s), and marks the media item as uploaded (or retries with capped backoff if the host fails).

- **Outbox Integration** – Extend Outbox entries to show media upload status (e.g., “Waiting to upload images”) and block note flush until all associated media URLs are ready; once uploads succeed, swap temporary placeholders in the note JSON with the actual URLs and let the existing `PostBox` flow send the event.

- **User Feedback & Control** – Surface visual indicators in the composer/outbox (progress, retry, delete) for offline media; allow removing/retrying specific assets without discarding the whole note.

- **Testing Strategy** – Add unit tests for the media store and upload manager, plus a UI test that composes a note with an offline image, verifies it appears in the media queue, and drains once network access is simulated.
