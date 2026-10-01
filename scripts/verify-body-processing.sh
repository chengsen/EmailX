#!/bin/sh
# Build first; this probe reuses that build's package modules and objects.
set -eu
project_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
derived_data=${1:-"$project_dir/build/DerivedData"}
products="$derived_data/Build/Products/Release"
package_sources=${2:-"$derived_data/SourcePackages"}
if [ ! -d "$package_sources/checkouts/GRDB.swift" ]; then
    package_sources="$project_dir/build/DerivedData/SourcePackages"
fi
if [ ! -f "$products/SwiftEmailParser.o" ] || [ ! -f "$products/GRDB.o" ]; then
    echo "Missing Release package objects in $products; build EmailX first." >&2
    exit 1
fi
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/emailx-body-probe.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT HUP INT TERM
xcrun swiftc -parse-as-library -swift-version 6 -default-isolation MainActor \
    -target "$(uname -m)-apple-macosx27.0.1" -module-name MyEmail -I "$products" \
    -I "$package_sources/checkouts/GRDB.swift/Sources/GRDBSQLite" \
    "$project_dir/MyEmail/Services/SyncService+BodyProcessing.swift" \
    "$project_dir/MyEmail/Models/Attachment.swift" \
    "$project_dir/scripts/verification/BodyProcessingProbe.swift" \
    "$products/SwiftEmailParser.o" "$products/GRDB.o" \
    -lsqlite3 -o "$probe_dir/probe"
"$probe_dir/probe"
