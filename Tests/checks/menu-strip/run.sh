#!/bin/bash
# MenuStripLayout (iOSClient/MenuStripLayout.swift) on its own: where the Mac's menu titles go in the
# thin strip along the top of the stream (every title in order, none across the Duo's fold, none in
# the stashed bar's tab, the » button and its overflow).
#   Tests/checks/menu-strip/run.sh             compile and run the check
#   Tests/checks/menu-strip/run.sh --mutants   one-line mutants of MenuStripLayout.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/MenuStripLayout.swift "$here/main.swift" -o "$out/check"
"$out/check"
