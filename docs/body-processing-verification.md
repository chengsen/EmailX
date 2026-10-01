# MIME decoding and attachment IO verification

Message body decoding, MIME header extraction, attachment writes, attachment re-fetch writes, quarantine metadata, and the existing UIDVALIDITY attachment directory cleanup run on Swift's concurrent executor. The callers retain their per-account command serialization and commit database changes only after the awaited file operation succeeds. The whole-message parser remains in use for IMAP compatibility; this change removes main actor blocking, but does not establish a lower peak memory bound for large messages.

After building an arm64 Release app with Xcode 27, run:

```sh
./scripts/verify-body-processing.sh build/PerformanceDerivedData
```

The optional argument selects the existing DerivedData directory. With no argument the script uses `build/DerivedData`. It reuses the build's SwiftEmailParser and GRDB objects, compiles the actual production processing helper and attachment model in Swift 6 with default main actor isolation, and runs a temporary standalone executable. The probe supplies only a service identity and a no-op logger; it does not initialize the app, database, account, network, or user preferences. Generated mail and attachment files live in a fresh temporary directory and are removed after the run.

The fixture contains two 16 MiB binary attachments with the same filename, one inline CID attachment, an encoded Chinese subject, sender headers and a plain body. Assertions check decoded headers/body, exact attachment bytes, filename sanitization and collision handling, CID/inline metadata, quarantine attributes, re-fetch overwrite behavior, propagation of file IO errors, and directory cleanup. A main actor task continues ticking while MIME processing and attachment writes execute; the probe fails if either operation prevents that task from progressing.

This verifies executor responsiveness and preservation of the isolated processing behavior. It does not measure complete app startup, WebKit rendering, network latency, live-account synchronization, database transaction timing, or production peak memory. The heartbeat count and elapsed time are diagnostic samples, not a guaranteed responsiveness or throughput threshold.
