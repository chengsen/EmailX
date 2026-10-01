#!/bin/zsh
set -euo pipefail
PROJECT_ROOT=${0:A:h:h}
cd "$PROJECT_ROOT"
mkdir -p build/verification
python3 - <<'PY'
from pathlib import Path
sources=[Path('MyEmail/Services/SyncService+Connection.swift').read_text(),Path('MyEmail/Services/SyncService.swift').read_text()]
methods=[]
for name in ['updateReceivingActivity','startPeriodicSync','removeAccount']:
 s=next(s for s in sources if '    func '+name+'(' in s)
 start=s.index('    func '+name+'('); brace=s.index('{',start); depth=1; end=brace+1
 while depth:
  if s[end]=='{':depth+=1
  elif s[end]=='}':depth-=1
  end+=1
 methods.append(s[start:end])
p=Path('scripts/verification/background-scheduling.swift').read_text().replace('    // PRODUCTION_METHODS','\n'.join(methods))
Path('build/verification/background-scheduling.swift').write_text(p)
PY
xcrun swiftc -O -swift-version 6 -parse-as-library build/verification/background-scheduling.swift -o build/verification/background-scheduling
build/verification/background-scheduling
