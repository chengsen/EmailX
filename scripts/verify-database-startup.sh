#!/bin/zsh
set -euo pipefail
PROJECT_ROOT=${0:A:h:h}
DERIVED_DATA=${1:-$PROJECT_ROOT/build/DerivedData}
PRODUCTS="$DERIVED_DATA/Build/Products/Release"
GRDB_SQLITE="$DERIVED_DATA/SourcePackages/checkouts/GRDB.swift/Sources/GRDBSQLite"
if [[ ! -d "$GRDB_SQLITE" ]]; then GRDB_SQLITE="$PROJECT_ROOT/build/DerivedData/SourcePackages/checkouts/GRDB.swift/Sources/GRDBSQLite"; fi
OUTPUT="$PROJECT_ROOT/build/verification/database-startup"
mkdir -p "${OUTPUT:h}"
xcrun swiftc -O -parse-as-library -target arm64-apple-macos27.0.1 \
  -I "$PRODUCTS" -I "$GRDB_SQLITE" \
  "$PROJECT_ROOT/MyEmail/Services/DatabaseService.swift" \
  "$PROJECT_ROOT/MyEmail/Services/DatabaseService+Schema.swift" \
  "$PROJECT_ROOT/MyEmail/Services/LogService.swift" \
  "$PROJECT_ROOT/MyEmail/Models/PendingAction.swift" \
  "$PROJECT_ROOT/MyEmail/Models/Enums.swift" \
  "$PROJECT_ROOT/scripts/verification/database-startup.swift" \
  "$PRODUCTS/GRDB.o" -lsqlite3 -o "$OUTPUT"
"$OUTPUT"
