#!/bin/bash
# DesktopScalePolicy (Sources/SillHost/DesktopScalePolicy.swift) on its own: the Desktop's text size,
# which of the Mac display's own modes a device's scale picks, whose request the Desktop follows, when
# the display goes back to its own mode, the crash note's recovery and the TEST ONLY stand-in's format.
#   Tests/checks/desktop-scale/run.sh             compile and run the check
#   Tests/checks/desktop-scale/run.sh --mutants   one-line mutants of DesktopScalePolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O Sources/SillHost/DesktopScalePolicy.swift "$here/main.swift" -o "$out/check"
"$out/check"
