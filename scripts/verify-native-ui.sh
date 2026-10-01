#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/emailx-native-ui.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT
xcrun swiftc -parse-as-library MyEmail/Views/MessageListNSCells.swift MyEmail/Utilities/FlowLayout.swift scripts/verification/native-ui.swift -o "$probe_dir/probe"
"$probe_dir/probe"
