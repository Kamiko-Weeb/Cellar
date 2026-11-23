#!/bin/bash
# Runs the tests. The Command Line Tools keep Swift Testing's macro plugin in a folder
# SwiftPM doesn't search, so point the compiler at it.
set -euo pipefail
cd "$(dirname "$0")"
swift test -Xswiftc -plugin-path -Xswiftc /Library/Developer/CommandLineTools/usr/lib/swift/host/plugins/testing "$@"
