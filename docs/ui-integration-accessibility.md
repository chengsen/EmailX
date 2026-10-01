# UI integration accessibility review

This review covers the integrated macOS 27 branch's recipient fields, recipient suggestions, message and compose attachments, status notices, and window keyboard-loop configuration. It does not certify every screen or any real mail account.

## Changes

Attachment preview and removal now use native bordered buttons instead of custom glass surfaces. The compose attachment container no longer adds glass around both its static description and its button. Native button styling supplies control boundaries and keyboard behavior, including the system Show Borders presentation; these controls no longer need a second handwritten border implementation.

Message attachment buttons expose the complete filename and formatted size to accessibility and offer the complete filename as a pointer help string. Decorative file icons are excluded. The action hint distinguishes EML opening from Quick Look. While a missing attachment is being downloaded, the button is disabled to prevent repeated preview requests.

Compose removal buttons expose “Remove attachment” and the relevant filename instead of an unlabeled cross icon. Error-dismiss buttons similarly expose the action and the error title. Existing catalog translations are reused.

Recipient suggestions use native bordered buttons instead of plain buttons within a custom glass panel. Escape closes suggestions; choosing one restores input focus. Recipient fields retain native editable text behavior and provide distinct To, Cc and Bcc labels. Suggestion buttons remain available through the native keyboard focus loop and VoiceOver. Arrow-key autocomplete selection is not introduced; the text field keeps its standard caret navigation.

Main, compose, settings and detached message windows already enable automatic key-view-loop recalculation. Existing remote-content, offline and error notices already read `accessibilityShowBorders` for their custom status surfaces. Their authentication, queue and remote-image permission actions are unchanged.

## Verification and limitations

Swift frontend parsing and `git diff --check` pass for the modified files. These checks establish source syntax and patch cleanliness, not accessibility-tree or rendering correctness. The complete integrated build supplies type-check validation separately.

Runtime acceptance must still exercise Tab and Shift-Tab traversal with keyboard navigation enabled, Space activation of preview/removal/suggestion buttons, Escape dismissal and restored recipient focus, VoiceOver action labels and filename announcements, Show Borders and contrast settings, long filenames, multiple attachment rows, and missing-file download recovery. Screen-capture access was unavailable in the preceding review; no visual or VoiceOver walkthrough is claimed here. Error banners retain their existing eight-second timeout; lengthy announcements and timing remain part of the manual review.
