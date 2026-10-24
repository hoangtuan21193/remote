#!/bin/bash
# The picture's lift over the software keyboard (KeyboardLift; docs/keyboard-auto-plan.md D4, D5):
# iOSClient/KeyboardLift.swift compiled with the check. How far the picture slides up for a caret
# under the keyboard, that it stays still while the caret is clear, that it never goes below zero or
# lifts the view's bottom above the keyboard, which keyboard counts as docked, and a model of typing.
#   Tests/checks/keyboard-lift/run.sh             compile and run the check
#   Tests/checks/keyboard-lift/run.sh --mutants   one-line mutants of KeyboardLift.swift; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
swiftc -O iOSClient/KeyboardLift.swift "$here/main.swift" -o "$out/check"
"$out/check"
