#!/bin/zsh
set -euo pipefail
PROJECT_ROOT=${0:A:h:h}
DERIVED_DATA=${1:-$PROJECT_ROOT/build/DerivedData}
BASELINE_REF=${2:-47def58}
PRODUCTS="$DERIVED_DATA/Build/Products/Release"
GRDB_SQLITE="$DERIVED_DATA/SourcePackages/checkouts/GRDB.swift/Sources/GRDBSQLite"
if [[ ! -d "$GRDB_SQLITE" ]]; then GRDB_SQLITE="$PROJECT_ROOT/build/DerivedData/SourcePackages/checkouts/GRDB.swift/Sources/GRDBSQLite"; fi
BENCHMARK_ROOT="$PROJECT_ROOT/build/verification/database-benchmark"
mkdir -p "$BENCHMARK_ROOT/baseline"
# Only visibility changes in the historical source, to invoke the same migration body.
git -C "$PROJECT_ROOT" show "$BASELINE_REF:MyEmail/Services/DatabaseService.swift" \
  | sed 's/private static func runMigrations/static func runMigrations/' \
  > "$BENCHMARK_ROOT/baseline/DatabaseService.swift"
git -C "$PROJECT_ROOT" show "$BASELINE_REF:MyEmail/Services/DatabaseService+Schema.swift" \
  > "$BENCHMARK_ROOT/baseline/DatabaseService+Schema.swift"
for variant in baseline optimized; do
  if [[ "$variant" == baseline ]]; then
    DATABASE_SOURCES="$BENCHMARK_ROOT/baseline"
  else
    DATABASE_SOURCES="$PROJECT_ROOT/MyEmail/Services"
  fi
  xcrun swiftc -O -parse-as-library -target arm64-apple-macos27.0.1 \
    -I "$PRODUCTS" -I "$GRDB_SQLITE" \
    "$DATABASE_SOURCES/DatabaseService.swift" \
    "$DATABASE_SOURCES/DatabaseService+Schema.swift" \
    "$PROJECT_ROOT/MyEmail/Services/LogService.swift" \
    "$PROJECT_ROOT/MyEmail/Models/PendingAction.swift" \
    "$PROJECT_ROOT/MyEmail/Models/Enums.swift" \
    "$PROJECT_ROOT/scripts/verification/database-benchmark.swift" \
    "$PRODUCTS/GRDB.o" -lsqlite3 -o "$BENCHMARK_ROOT/$variant-benchmark"
  "$BENCHMARK_ROOT/$variant-benchmark" > "$BENCHMARK_ROOT/$variant.json"
  cat "$BENCHMARK_ROOT/$variant.json"
done
