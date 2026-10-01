#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/emailx-recipient-interaction.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT
xcrun swiftc -parse-as-library MyEmail/Views/ComposeHeaderFields.swift scripts/verification/recipient-interaction.swift -o "$probe_dir/probe"
"$probe_dir/probe"
