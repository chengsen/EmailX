#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/emailx-native-layout.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT
xcrun swiftc -parse-as-library MyEmail/Models/ComposeAttachment.swift MyEmail/Utilities/FormatHelpers.swift MyEmail/Utilities/FlowLayout.swift MyEmail/Views/ComposeAttachmentsStripView.swift MyEmail/Views/ComposeHeaderFields.swift scripts/verification/native-layout.swift -o "$probe_dir/probe"
"$probe_dir/probe"
