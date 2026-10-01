#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/emailx-compose-toolbar.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT
xcrun swiftc -parse-as-library MyEmail/Views/ComposeToolbar.swift scripts/verification/compose-toolbar.swift -o "$probe_dir/probe"
"$probe_dir/probe"
