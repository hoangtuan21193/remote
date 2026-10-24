#!/bin/bash
# The Mac's text focus (kind 33; docs/keyboard-auto-plan.md): Sources/StreamProtocol compiled as one
# module with the check. Kind 33 and TextFocus's JSON, the window list's `textFocus`, and
# TextFocusPolicy's rules for both ends: which Accessibility roles take text, when the host looks after
# a click, the caret as fractions of the streamed frame, which report is worth sending, what a device
# does with a report (open, close or keep its keyboard) and its subscription.
#   Tests/checks/textfocus/run.sh             compile and run the check
#   Tests/checks/textfocus/run.sh --mutants   one-line mutants of StreamProtocol; each must fail it
here="$(cd "$(dirname "$0")" && pwd)"
source "$here/../common.sh"
if [ "${1:-}" = "--mutants" ]; then run_mutants python3 "$here/mutants.py" "$root"; exit; fi
swiftc -O Sources/StreamProtocol/*.swift "$here/main.swift" -o "$out/check"
"$out/check"
