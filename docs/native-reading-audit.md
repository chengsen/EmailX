# Native reading interface audit

The message reading interface uses standard SwiftUI controls and AppKit windows. Message HTML remains untrusted document content rendered through the existing filtered HTMLMailView path. Sender avatars, file icons and the optional mail-client image are content decoration; they are not custom replacements for native buttons.

## Message detail and standalone message windows

The reading pane uses semantic header typography, native bordered reply/menu controls and the existing native segmented body-format picker. Recipients wrap using the shared constrained FlowLayout rather than a non-wrapping three-token row. Full recipient lists remain selectable after expansion; full addresses remain available in native menus. The optional mail-client image now participates in the date row instead of overlaying text. Decorative avatars are excluded from VoiceOver. Loading has a label and failed loading uses ContentUnavailableView with retry.

Standalone message windows install a real NSToolbar. Reply, Archive and Delete are default items; Reply All, Forward and Mark as Spam are available through customization and the header menu. The window controller owns each item's target, so a standalone window cannot operate on a different selected message. Reply/forward resolve only the window's account ID asynchronously from the database, independent of the currently paged message list. Read/unread and flag menu actions likewise resolve their own stored flag instead of guessing from the current list page. Existing undo and source actions are preserved. The toolbar handles focus, overflow, borders and system appearance.

## Attachments

Reading attachments use native bordered buttons, native file-type images, semantic text and explicit filename/size/action accessibility information. Removed handwritten padding inside button labels so the system determines control metrics. Long filenames truncate in the middle with the full filename available in help and accessibility. Shared FlowLayout bounds the item width. Quick Look, EML opening, Save As, Finder reveal and missing-file refetch paths are unchanged.

## Raw source and EML

The raw source sheet preserves read-only selection and Copy/Close controls with native bordered styling. RFC822 text uses the semantic monospaced body font. Failure uses a system empty state. The minimum sheet size allows a narrower display while retaining the larger preferred size. No message source is translated or rewritten.

EML windows already use native titled resizable AppKit windows and semantic SwiftUI headers. Enabled automatic key-view-loop recalculation for the native attachment actions. EML is a read-only document and does not need an empty decorative toolbar. Its existing remote-content blocking and HTML filtering remain unchanged.

## Bulk selection

Bulk operations use ContentUnavailableView and native bordered buttons. Actions wrap instead of relying on a fixed horizontal row, retaining archive/delete undo and junk actions.

## Validation boundaries

Swift parsing and whitespace validation passed for the changed files. An in-memory SQLite check extracted the production messages table and the three controller SQL queries; existing account/flags, changed flags and missing rows passed. Root integration owns the Release build and runtime checks. Visual review still needs long addresses, many attachments, minimum reading-window sizes, toolbar customization/overflow, VoiceOver and increased-contrast appearance. Parsing alone is not runtime acceptance. Mail loading/read flags, remote-content trust, HTML sanitization and attachment IO were not replaced or weakened by this UI work.

Integration runtime validation confirmed production BLOB UUID binding with GRDB. The original string UUID arguments were corrected to typed UUID arguments; standalone reply, flag and read-state actions passed against the isolated app database. See the complete acceptance report for remaining visual and live-account boundaries.
