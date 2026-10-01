#!/bin/bash
set -euo pipefail
repo_root="$(cd "$(dirname "$0")/.." && pwd)"
probe_dir="$(mktemp -d "${TMPDIR:-/tmp}/emailx-settings-toolbar.XXXXXX")"
trap 'rm -rf "$probe_dir"' EXIT
xcrun swiftc \
  "$repo_root/MyEmail/App/SettingsWindowController.swift" \
  "$repo_root/MyEmail/Views/Settings/SettingsSplitView.swift" \
  "$repo_root/scripts/verification/settings-toolbar.swift" \
  -o "$probe_dir/SettingsToolbarProbe"
"$probe_dir/SettingsToolbarProbe"
