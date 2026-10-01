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
