import CoreGraphics
import Foundation

// The picture's lift over the software keyboard (docs/keyboard-auto-plan.md), against
// iOSClient/KeyboardLift.swift compiled into this binary:
//   swiftc -O iOSClient/KeyboardLift.swift Tests/checks/keyboard-lift/main.swift -o check
var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
typealias L = KeyboardLift
func line(_ y: CGFloat, _ h: CGFloat = 20) -> CGRect { CGRect(x: 100, y: y, width: 0, height: h) }

// An iPhone on its side: the stream panel 287 pt tall, the keyboard and its bar from 63 pt down.
check(L.margin == 12 && L.topMargin == 12 && L.tapLine == 24, "the margins: 12 pt, a tap's line 24 pt")
check(L.lift(caret: line(200), keyboardTop: 63, height: 287, current: 0) == 169, "a caret under the keyboard: up until 12 pt clear (220 + 12 − 63)")
check(L.lift(caret: line(20), keyboardTop: 63, height: 287, current: 0) == 0, "a caret clear of it: no lift")
check(L.lift(caret: line(30), keyboardTop: 63, height: 287, current: 0) == 0, "its bottom 13 pt clear: still none")
check(L.lift(caret: line(32), keyboardTop: 63, height: 287, current: 0) == 1, "1 pt short of clear: 1 pt")
check(L.lift(caret: line(200), keyboardTop: nil, height: 287, current: 169) == 0, "the keyboard gone: back down")
check(L.lift(caret: line(200), keyboardTop: 287, height: 287, current: 50) == 0, "a keyboard at the view's bottom covers none of it")
check(L.lift(caret: line(200), keyboardTop: 300, height: 287, current: 50) == 0, "one below it: none")
check(L.lift(caret: line(270), keyboardTop: 63, height: 287, current: 0) == 224, "a caret at the bottom: as far as the view's bottom meets the keyboard (287 − 63)")
check(L.lift(caret: line(400), keyboardTop: 63, height: 287, current: 0) == 224, "never past that")
check(L.lift(caret: nil, keyboardTop: 63, height: 287, current: 100) == 100, "no caret: as it is")
check(L.lift(caret: nil, keyboardTop: 63, height: 287, current: 400) == 224, "no caret: within the bounds")
check(L.lift(caret: nil, keyboardTop: 63, height: 287, current: -5) == 0, "never below zero")
check(L.lift(caret: line(200), keyboardTop: 63, height: 0, current: 0) == 0, "no view: none")

// Typing: the picture stays still along a line, steps once for a new line under the keyboard, and
// comes down for a caret pushed out of the top.
var lift = L.lift(caret: line(200), keyboardTop: 63, height: 287, current: 0)
check(L.lift(caret: CGRect(x: 180, y: 200, width: 0, height: 20), keyboardTop: 63, height: 287, current: lift) == lift, "typing along the line: still")
check(L.lift(caret: line(190), keyboardTop: 63, height: 287, current: lift) == lift, "a line up, still clear: still")
lift = L.lift(caret: line(220), keyboardTop: 63, height: 287, current: lift)
check(lift == 189, "a new line under it: one step (\(lift))")
check(L.lift(caret: line(150), keyboardTop: 63, height: 287, current: 189) == 138, "a caret above the top: down until it shows 12 pt in (150 − 12)")
check(L.lift(caret: line(5), keyboardTop: 63, height: 287, current: 189) == 0, "back at the field's top: none")
check(L.lift(caret: CGRect(x: 0, y: 100, width: 0, height: 80), keyboardTop: 63, height: 287, current: 0) == 129,
      "a caret taller than the room: its bottom wins (180 + 12 − 63)")

// A tap's line, the Mac's caret in the view, the keyboard's top.
check(L.caret(forTap: CGPoint(x: 50, y: 100)) == CGRect(x: 50, y: 88, width: 0, height: 24), "a tap: a 24 pt line centred on it")
check(L.caret(x: 0.5, y: 0.25, w: 0, h: 0.1, in: CGRect(x: 10, y: 20, width: 200, height: 100)) == CGRect(x: 110, y: 45, width: 0, height: 10),
      "the Mac's caret, in the letterboxed video's rect")
check(L.caret(x: 0.5, y: 0.5, w: 0, h: 0.1, in: .zero) == nil, "no video: no caret")
let screen = CGRect(x: 0, y: 0, width: 874, height: 402)
let docked = CGRect(x: 0, y: 149, width: 874, height: 253)
check(L.keyboardTop(frame: docked, screen: screen, frameTop: 149, viewTop: 86) == 63, "docked: its top under the panel's (149 − 86)")
check(L.keyboardTop(frame: CGRect(x: 300, y: 152, width: 320, height: 250), screen: screen, frameTop: 152, viewTop: 86) == nil,
      "iPadOS's floating keyboard: none")
check(L.keyboardTop(frame: CGRect(x: 0, y: 100, width: 874, height: 250), screen: screen, frameTop: 100, viewTop: 86) == nil,
      "a keyboard short of the bottom (undocked): none")
check(L.keyboardTop(frame: CGRect(x: 0, y: 402, width: 874, height: 0), screen: screen, frameTop: 402, viewTop: 86) == nil,
      "an empty input view (a hardware keyboard's hold): none")

// A model: random carets and keyboards; the caret, once lifted, always clears the keyboard by the
// margin unless the view's bottom already meets it; the lift stays within its bounds; and a caret that
// was clear never moves the picture.
var rng = SystemRandomNumberGenerator()
for _ in 0..<5000 {
    let height = CGFloat.random(in: 100...900, using: &rng)
    let top = CGFloat.random(in: 0...height, using: &rng)
    let current = CGFloat.random(in: 0...(height - top), using: &rng)
    let caret = line(CGFloat.random(in: 0...height, using: &rng), CGFloat.random(in: 1...40, using: &rng))
    let next = L.lift(caret: caret, keyboardTop: top, height: height, current: current)
    check(next >= 0 && next <= height - top + 0.001, "model: within bounds")
    if next < height - top - 0.001 { check(caret.maxY - next <= top - L.margin + 0.001, "model: the caret clears the keyboard") }
    let clear = caret.maxY - current <= top - L.margin && caret.minY - current >= L.topMargin
    if clear { check(next == current, "model: a clear caret moves nothing") }
}

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
