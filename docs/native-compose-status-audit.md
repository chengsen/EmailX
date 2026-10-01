# Compose and status UI audit — 2026-10-02

The compose window uses its existing window-local NSToolbar for sending, attachment selection, text mode and signature selection. The editor remains a native NSTextView. Formatting acts on the editor selection through a standard accessory bar; it is intentionally not merged into message-level toolbar actions.

| Surface | Native implementation and result |
| --- | --- |
| Header fields | Existing Grid, native TextField and account Picker retained. Recipient suggestions use bordered Buttons, not custom glass. No fixed label width or token background is introduced. |
| Formatting accessory | Existing accessoryBarAction buttons and native font Pickers retained. A native horizontal ScrollView prevents controls from being clipped at the minimum compose width. Buttons have explicit accessibility names, and selection-dependent controls disable until the text view is available. Selection observation uses a stable optional text-view identity rather than allocating a temporary NSTextView. |
| Link insertion | Native grouped Form, TextFields and standard Cancel/Insert sheet actions. Existing URL validation and selection insertion semantics remain intact. |
| Attachments | Existing file-type icons, semantic fonts, FlowLayout and native bordered remove buttons retained. Shared FlowLayout now proposes the available width during both measurement and placement, allowing long filenames/recipient labels to compress instead of escaping the row. An unspecified width reports the measured row width rather than zero. |
| Attachment picker and drop | NSOpenPanel stays asynchronous and bound to the owning draft window. Existing security access and deferred data reads remain intact. Drop guidance uses a native GroupBox and Label instead of a drawn rounded outline. |
| Compose errors and empty state | Existing semantic, selectable send-error text and ContentUnavailableView retained. |
| Authentication and error notices | Native GroupBox, Label and bordered actions replace custom glass/border layers. Error details wrap and remain selectable rather than truncating at two lines. OAuth retry, cancellation handling and error expiry behavior remain intact. |
| Offline and failed queue | Noninteractive status uses a standard Label; failed-action menu uses a native bordered Menu. Status text can wrap. Retry/discard actions and queue scheduling remain intact. |
| Remote content permission | Native GroupBox and bordered split-action Menu replace custom glass. ViewThatFits provides a stacked arrangement at narrow widths. Per-message loading and explicit sender trust remain separate actions. |
| Debug log | Native List replaces the custom ScrollView/LazyVStack. Standard accessory controls now carry accessibility names. The manually drawn resize grip and gesture are removed; the parent uses VSplitView. Saved height supplies an initial ideal size, not a locked frame. Filtering, copy, clear, context menu and auto-scroll are retained. |

## Verification

- `xcrun swiftc -frontend -parse` succeeded for the modified Swift files.
- `scripts/verify-compose-toolbar.sh` passed native installation, actions and menus, reactive state, two hosted windows, enabled/disabled Cmd+Return, and native overflow items.
- A literal audit found no `glassEffect`, glass button style, hand-drawn rounded rectangle or fixed point-size font in the owned compose/status/debug surfaces.
- No String Catalog keys were added. Existing localized labels are reused.

The probe proves the native toolbar bridge and window isolation, not live SMTP delivery or a full visual/accessibility pass. The parent integration build and runtime checks cover the application as a whole; live-account delivery, VoiceOver, narrow-width interaction and system appearance checks require separate acceptance evidence. Custom flow layout remains a geometry helper because SwiftUI has no native wrapping attachment container; its upgrade trigger is a platform wrapping layout with equivalent interaction and accessibility.

## Strict acceptance follow-up

The acceptance branch additionally corrects these concrete defects:

- Recipient suggestions are computed from user editing and from entering the field, not from unfocused programmatic prefill. Native suggestion buttons explicitly expose the full name and email as one accessible label.
- Each compose attachment exposes its full filename and byte-count description as accessible information; its removal action exposes the filename as a value rather than relying on a VoiceOver hint. The native removal button uses regular sizing and a minimum 20-point symbol region.
- Large attachment batches now use a native vertical ViewThatFits and ScrollView with a maximum 140-point viewport. All attachments remain in the scroll content rather than being omitted or clipped; the parent acceptance simulation measures both a natural-height single item and multirow batches.
- Formatting icon controls and the Cc/Bcc toggle have minimum 20-point symbol regions in their native button styles. This is a region inside the native button, not a claim that all measured targets are 28 points; integration AX-frame measurements determine the actual target size.
- Text-color action restores the active editor as first responder and resets the shared color panel to the native `changeColor:` responder chain with no persistent draft target. A direct AppKit probe confirmed selected text is colored without changing unselected text or the other draft. Standalone CLI/app probes did not establish key/main windows, so active-window responder routing remains an integration UI check.
- Send errors and status notices post native accessibility announcements. Offline/reconnected and newly failed queue transitions are announced without announcing each repeated sync sweep. Existing localized strings are reused.

Apple references reviewed for this pass: [Keyboards](https://developer.apple.com/design/human-interface-guidelines/keyboards), [Focus and selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection), [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars), [Show Borders](https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityshowborders), and [native accessibility announcements](https://developer.apple.com/documentation/accessibility/accessibilitynotification/announcement). Native bordered controls retain system focus and borders; the Show Borders guidance applies to custom interactive controls and does not require drawing a second border around system buttons.

RichTextEditor type-checking with an isolated logging stub, Swift parsing of affected files, `git diff --check`, and the existing compose-toolbar probe passed. No system preferences, private APIs, production test flags, or localization keys were added.

## UI interaction follow-up

The next acceptance round replaces duplicated compose header alternatives with a single native ScrollView. Headers are limited to 35 percent of content height (220-point maximum), attachments to 20 percent (140 maximum), and long send errors to 10 percent (100 maximum). ComposeWindowController now sets contentMinSize rather than counting toolbar chrome inside the 560 by 400 minimum.

Production rich and plain editors reuse the localized Message body accessibility label. Link insertion uses NSTextView.insertText so native delegate validation, one-step Undo/Redo and selection restoration are retained; bare HTTP(S) schemes cannot be inserted. The production editor interaction probe runs real asynchronous AppKit windows and verifies shared nil-target NSColorPanel routing between drafts. It does not claim mouse-driven color picker acceptance.

Recipient suggestions retain native button roles and keyboard focus. Arrow keys choose candidates, Return commits, Escape returns to input, and returning input restores the native field editor caret at the end so further recipients do not replace existing addresses. The header owns shared focus for recipient and subject fields. Full evidence and current limits are in ui-interaction-acceptance-2026-10-02.md.
