#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# Command Line Tools 6.4 sometimes omits the Swift Testing macro plugin when it
# recompiles the test module. Pointing the compiler at the plugin directory is
# enough and avoids a clean rebuild on every run.
SWIFT_BIN="$(xcrun --find swift 2>/dev/null || true)"
if [ -n "$SWIFT_BIN" ]; then
    PLUGIN_DIR="$(dirname "$(dirname "$SWIFT_BIN")")/lib/swift/host/plugins/testing"
    if [ -d "$PLUGIN_DIR" ]; then
        exec swift test -Xswiftc -plugin-path -Xswiftc "$PLUGIN_DIR" "$@"
    fi
fi

exec swift test "$@"
