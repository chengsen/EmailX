# EmailX

<img src="MyEmail/Assets.xcassets/AppIcon.appiconset/icon_128@2x.png" width="64" alt="EmailX icon">

EmailX is a native macOS email client focused on local-first operation, low overhead, and correctness under load — multiple accounts, large archives, unstable networks, and external clients modifying the mailbox in parallel.

Inspired by MailMate and Thunderbird. No AI, no tabs, no Liquid Glass.

## Requirements

- macOS 27.0.1 or later
- arm64 or x86_64

## Features

- **Multi-account** — Gmail (OAuth2 + PKCE) and generic IMAP/SMTP with password
- **Unified Inbox** — virtual aggregation of all account inboxes in one view
- **Two layouts** — Wide (NavigationSplitView) and Classic (HSplitView) with persistent state
- **Offline-capable** — full read/compose/search while offline; actions queued and replayed on reconnect
- **Full-text search** — FTS5, instant, across all accounts and folders
- **IDLE push** — real-time delivery on INBOX and selected folder; STATUS polling on others
- **Customizable toolbar and columns** — NSToolbar bridge, per-column width and visibility
- **HTML rendering** — WKWebView with JavaScript disabled, remote content blocked by default
- **Local-only** — no telemetry, no cloud sync, no developer servers

## Language

In **Settings → General → Language**, choose **Follow macOS**, **简体中文**, or **English**. The choice is saved immediately and takes effect on the next launch. Following macOS removes the application language override. Existing Russian resources remain available through system language selection.

Localization uses Apple String Catalogs, native plural rules, and system date/byte formatting. Message content and user-defined names remain unchanged. See [localization notes](docs/localization.md).

## Tech Stack

| Layer | Technology |
|-------|------------|
| UI | SwiftUI + `@Observable`, `NSToolbar` bridge |
| Persistence | GRDB.swift (SQLite, WAL, ValueObservation) |
| Full-text search | FTS5 via GRDB |
| IMAP / SMTP | Pinned SwiftMail integration in `Vendor/SwiftMail` + IMAPRawClient (NWConnection) |
| MIME parsing | SwiftEmailParser |
| HTML rendering | WKWebView, JS disabled |
| OAuth2 | ASWebAuthenticationSession + PKCE (RFC 8252) |
| Keychain | `kSecAttrAccessibleAfterFirstUnlock` |

## Building

Open `MyEmail.xcodeproj` in Xcode 27+ and build the `MyEmail` scheme.

SwiftMail is pinned locally with the integration changes required by this application's synchronization and raw-message APIs. See `Vendor/SwiftMail/EMAILX-PATCHES.md` for its upstream revision. Preserve the original license when distributing.

Before a first build, copy `MyEmail/App/Secrets.swift.template` to `MyEmail/App/Secrets.swift`. The file is ignored by Git. Placeholder values permit compilation but do not enable Gmail OAuth; configure your own OAuth client before using Gmail sign-in.

To build a signed distributable DMG:

```sh
scripts/build-dmg.sh
```

## Project Structure

```
MyEmail/
├── App/          # Entry point, AppState, app-level setup
├── Models/       # GRDB records (Message, Account, Folder, …)
├── Services/     # SyncService, IMAPService, SMTPService, AuthService, …
├── Views/        # SwiftUI views and subcomponents
├── Utilities/    # IMAP-UTF-7, HTML sanitizer, logging, …
└── Shared/       # Cross-cutting types and extensions
```

## Logging

All runtime logs are written via `LogService`. Press **⌥⌘Y** to open the debug log panel — no Xcode or Console.app needed.

## License

MIT — see [LICENSE](LICENSE).

## Privacy

All data stays on your device. See [PRIVACY_POLICY.md](PRIVACY_POLICY.md) for details.
