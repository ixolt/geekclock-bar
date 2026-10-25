#!/usr/bin/env bash
# Runs the test suite. With Xcode, plain `swift test` works. The Command Line
# Tools' SwiftPM does not find the Swift Testing macro plugin on its own, so
# when they are the selected toolchain, load it explicitly.
set -euo pipefail
cd "$(dirname "$0")/.."
PLUGIN=/Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing/libTestingMacros.dylib
if [[ "$(xcode-select -p 2>/dev/null)" == /Library/Developer/CommandLineTools* && -f "$PLUGIN" ]]; then
    exec swift test -Xswiftc -load-plugin-library -Xswiftc "$PLUGIN" "$@"
fi
exec swift test "$@"
