## Code Search

Use `semble search` to find code by describing what it does or naming a symbol/identifier, instead of grep:

​```bash
semble search "authentication flow" ./my-project
semble search "save_pretrained" ./my-project
semble search "save model to disk" ./my-project --top-k 10
​```

Use `semble find-related` to discover code similar to a known location (pass `file_path` and `line` from a prior search result):

​```bash
semble find-related src/auth.py 42 ./my-project
​```

`path` defaults to the current directory when omitted; git URLs are accepted.

If `semble` is not on `$PATH`, use `uvx --from "semble[mcp]" semble` in its place.

## Workflow

1. Start with `semble search` to find relevant chunks.
2. Inspect full files only when the returned chunk is not enough context.
3. Optionally use `semble find-related` with a promising result's `file_path` and `line` to discover related implementations.
4. Use grep only when you need exhaustive literal matches or quick confirmation of an exact string.
## Localization

Use Apple String Catalogs in `MyEmail/Resources/Localizable.xcstrings`; preserve existing translations. Localize SwiftUI literals and use `String(localized:)` for dynamic strings and AppKit labels. Use native catalog plural variations and Foundation formatting. Do not translate mail content, contact names, attachment filenames, or custom folder names; use `Folder.localizedName` for role-based folder labels. The Settings language picker contains only system, zh-Hans, and en, and saves native app-scoped `AppleLanguages` preferences for the next launch.

## Performance and delivery

Do not rebuild existing FTS at startup. Index format changes and data backfills require additive one-time migrations; preserve queued actions and search integrity. Metadata flags/scores must not reindex unchanged text. Keep MIME decoding and attachment IO off MainActor and preserve per-account connection serialization. Detailed folder metadata is paged; preserve full sorting/thread semantics and historical reachability. Keep IDLE, 60-second STATUS, wake/network recovery and 5-minute fallback; verify overlap coalescing and other-account IDLE survival when changing scheduling. Use the executable checks documented in `docs/performance-verification-2026-10-01.md`; isolated fixtures are not live-account acceptance.

## Native macOS interface

Compose actions belong to each draft window's native NSToolbar; keep editor selection formatting in its accessory bar. Verify window isolation, enabled state and Cmd+Return using `scripts/verify-compose-toolbar.sh` after changing the bridge. Prefer native bordered controls for attachment and recipient actions rather than handwritten glass or border overlays. The app icon is `EmailXAppIcon.icon`; native asset compilation and the built bundle must select it. Preserve the original icon assets for recovery. Use APIs available on the macOS target; a cross-platform SwiftUI symbol is not evidence of macOS availability. Full build and runtime checks remain necessary after UI branch integration.

Native UI inventory and acceptance boundaries are in `docs/native-ui-completion-2026-10-02.md`. Run `scripts/verify-native-ui.sh` after changing shared wrapping geometry or native message cells. Keep independent reading-window UUID query arguments typed as UUID (GRDB stores them as BLOB), and preserve per-window action ownership. Prefer system split views and grouped forms to drawn controls. Runtime UI fixtures must use a separate bundle ID/container and production-compatible UUID storage; do not touch live mail accounts for fixture validation.
