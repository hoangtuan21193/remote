#!/bin/bash
# AppSwitcherPolicy (iOSClient/AppSwitcherPolicy.swift) on its own: the app switcher a three-finger
# swipe opens: its tiles and their order, the lit tile, the pause, taps, and what a choice streams.
#   Tests/checks/app-switcher/run.sh             compile and run the check
#   Tests/checks/app-switcher/run.sh --mutants   one-line mutants of AppSwitcherPolicy.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py"; exit; fi
swiftc -O iOSClient/AppSwitcherPolicy.swift "$here/main.swift" -o "$out/check"
"$out/check"
