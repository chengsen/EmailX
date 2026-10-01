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
