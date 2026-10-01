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

## Follow-up keyboard, accessibility and constrained-window audit

AppKit's accessibilityChildren automatically gathers accessible descendants. The previous summary cell ignored nine NSViews, but a runtime probe found nine promoted NSCell/image elements under the cell, including Circle, flag and repeated field text. The summary cell now exposes one complete label and an explicitly empty child list; the table's native row/cell selection semantics remain intact. The existing native UI probe checks the child list before and after recycling, and verifies the complete long subject remains in the accessibility label.

The list lacked Return/Enter activation. A minimal NSTableView subclass handles unmodified Return and keypad Enter for the currently keyboard-selected row, preserving normal AppKit navigation and native type selection. The probe activates row 1 through both key events and verifies selection remains at row 1. A production subject-width constraint and a 280-point constrained AppKit container prevent long subjects from extending beyond the summary cell.

Standalone message toolbar and menu actions previously validated unconditionally. The loaded reading view now reports availability to its own window controller; message actions start disabled, become enabled only when a message loads and remain disabled for a missing message. Account/read/flag queries still bind UUID through GRDB; the native UUID representation must not be replaced with uuidString bindings.

Header and attachment FlowLayouts previously grew without a viewport limit and could consume the entire reading pane. They now use a single native vertical ScrollView, preserving all document text and attachment controls without replacing the active content tree when it grows. Header and attachment maximum heights are 220 and 140 points; the reading pane further restricts them to 35 and 20 percent of available height, retaining room for the message body. Short attachments take their measured height instead of filling the limit.

The isolated layout probe compiled the production MessageHeaderBar and AttachmentStripView, with models/environment/services stubbed only to avoid live data. At both 280 and 500 points wide, a 100-line subject and 100 recipients stayed within a 134-point header limit; one attachment measured 48 points high while 100 long filenames stayed within an 84-point viewport. The regression probe is scripts/verify-reading-layout.sh with scripts/verification/reading-layout.py; it reads the production views on execution and creates temporary compile inputs, rather than keeping a separate copy of the UI. It proves layout bounds, not real mail/network behavior or VoiceOver speech.

The keyboard and cell checks pass through scripts/verify-native-ui.sh. Apple reference criteria: [AppKit accessibilityChildren](https://developer.apple.com/documentation/AppKit/NSAccessibility-c.protocol/accessibilityChildren), [Keyboard accessibility](https://developer.apple.com/design/human-interface-guidelines/keyboards/) and [Native toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars/). Root integration owns Release compilation and the isolated application check of actual toolbar enabled state, native selection and scrolling. Global accessibility preferences were not changed.

EML now uses the same proportional header and attachment viewports. The production EML header is measured directly by exposing its private struct only in a temporary compile input; mail parsing is stubbed, and HTML rendering/security is not tested by this sizing check. The expanded fixture measured unrestricted 100-line message headers at 2404 points; unrestricted EML headers measured 7909 points at 280 width and 5123 points at 500 width. Each constrained native header viewport measured 134 points while preserving the content in its scrollable document. A single attachment remained 48 points high; 100 attachments stayed within an 84-point viewport. This demonstrates the actual overflow defect and its bounded layout correction rather than testing a duplicate layout implementation.

## Complete minimum-window layout and interaction follow-up

The reading regression fixture now compiles the complete production MessageDetailView and EmlViewerView, plus the real RemoteContentBanner and native header/attachment controls. Only mail models, services and the HTML renderer are isolated stubs; the renderer stub supplies a native NSView to measure the rectangle allocated to the document. An actual fixture NSWindow is constrained to an outer frame of 500 by 400 points with a unified NSToolbar; its content area is 500 by 334 points. The fixture does not operate another application or change global preferences.

With a long header, 100 attachments, both body formats and the remote-content notice, the original 40/25-percent proportions left only 41 points for message body content. The corrected 35/20 proportions leave 74 points; EML body space increases from 115 to 148 points. The regression check requires at least 70 points for the native document rectangle and verifies it stays inside the content area. Small attachments still use their natural 48-point height. This is minimum-viewport layout acceptance, not proof of rendered HTML, mail reception or assistive-technology acceptance.

The initial ViewThatFits approach duplicated stateful content across two alternative trees. Expanding recipients or resizing across the fit boundary could replace the AddressListRow state and keyboard-focused control. Headers and attachment areas now keep a single native ScrollView mounted, with natural content height and a bounded viewport. No truncation or recipient/attachment removal is used to achieve the bounds.

A direct in-process NSAccessibilityProtocol query on NSHostingView returns only its root and cannot validate SwiftUI's rendered accessibility children. That query is not kept as a passing test. CUA screen capture currently fails with SCStream -3811, and Full Keyboard Access is off in the fixture process. This run did not change that setting or claim that real Tab navigation, scrolling to an offscreen attachment, menu focus or VoiceOver speech were exercised. Those remaining interaction checks require an operational supported UI capture path or user acceptance. The fixture's native layout checks are sufficient to establish the sizing correction, while the single-tree change preserves state structurally.
