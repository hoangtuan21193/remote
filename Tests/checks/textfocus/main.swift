import Foundation

// The Mac's text focus (docs/keyboard-auto-plan.md), against Sources/StreamProtocol compiled into
// this binary:
//   swiftc -O Sources/StreamProtocol/*.swift Tests/checks/textfocus/main.swift -o check
// Kind 33 and TextFocus's JSON, the window list's `textFocus`, and TextFocusPolicy: the roles that
// take text, the host's looks, the caret's fractions, which report goes out, what a device does with
// one, and its subscription; then a model of a device's keyboard against a run of reports.
var failures = 0
var checks = 0
func check(_ ok: Bool, _ what: @autoclosure () -> String, line: Int = #line) {
    checks += 1
    if !ok { failures += 1; print("FAIL (line \(line)): \(what())") }
}
typealias P = TextFocusPolicy
let sorted = JSONEncoder(); sorted.outputFormatting = .sortedKeys
func json<T: Encodable>(_ x: T) -> String { String(decoding: try! sorted.encode(x), as: UTF8.self) }
func data(_ s: String) -> Data { Data(s.utf8) }

// MARK: - The kind and the window list

func header(_ kind: UInt8) -> StreamHeader? {
    StreamMessage.parseHeader(Data([kind]) + Data(count: 9) + Data([0, 0, 0, 2]))
}
check(StreamMessageKind.textFocus.rawValue == 33 && StreamMessageKind(rawValue: 33) == .textFocus, "kind 33 is the text focus")
check(header(33)?.kind == .textFocus && header(33)?.payloadLength == 2, "a kind 33 header parses")
check(StreamMessageKind(rawValue: 32) == .clipboard && StreamMessageKind(rawValue: 34) == nil, "32 is still the clipboard, 34 not this build's")
let message = StreamMessage(kind: .textFocus, timestamp: 1, isKeyframe: false, payload: P.subscription).serialized()
check(message.first == 33 && message.count == StreamMessage.headerLength + 2, "a subscription is a header and {}")

let takes = WindowList(macName: "Mac mini", windows: [], active: .desktop, textFocus: P.generation)
check(json(takes).contains(#""textFocus":1"#), "a host that reports says textFocus 1: \(json(takes))")
check(Wire.decode(WindowList.self, from: Wire.encode(takes))?.textFocus == 1, "textFocus round-trips")
check(!json(WindowList(macName: "M", windows: [], active: .none)).contains("textFocus"), "a host without it leaves the key out")
check(Wire.decode(WindowList.self, from: data(#"{"macName":"M","windows":[],"active":{"none":{}},"clipboard":1}"#))?.textFocus == nil,
      "an older host's list decodes, textFocus nil")
check(P.generation == 1, "generation 1")

// MARK: - TextFocus's JSON

check(json(TextFocus()) == "{}" && String(decoding: P.subscription, as: UTF8.self) == "{}", "the subscription is {}")
check(String(decoding: P.stopping, as: UTF8.self) == #"{"stop":true}"#, "stopping is {\"stop\":true}")
let report = TextFocus(editable: true, caret: TextFocusRect(x: 0.5, y: 0.25, w: 0, h: 0.0625), tap: true)
check(json(report) == #"{"caret":{"h":0.0625,"w":0,"x":0.5,"y":0.25},"editable":true,"tap":true}"#, "a report's keys: \(json(report))")
check(Wire.decode(TextFocus.self, from: Wire.encode(report)) == report, "a report round-trips")
check(Wire.decode(TextFocus.self, from: data(#"{"editable":false,"later":[1]}"#)) == TextFocus(editable: false), "unknown keys skipped")
check(Wire.decode(TextFocus.self, from: data(#"{"editable":"yes"}"#)) == nil, "a wrong type does not decode")

// MARK: - The host: roles

for role in ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"] {
    check(P.isEditable(role: role, valueSettable: false, hasSelectedTextRange: false), "\(role) takes text")
}
for role in ["AXButton", "AXGroup", "AXWebArea", "AXStaticText", "AXWindow", "AXScrollArea"] {
    check(!P.isEditable(role: role, valueSettable: false, hasSelectedTextRange: true), "\(role) without a settable value takes none")
    check(!P.isEditable(role: role, valueSettable: true, hasSelectedTextRange: false), "\(role) without a selection range takes none")
}
check(P.isEditable(role: "AXGroup", valueSettable: true, hasSelectedTextRange: true), "a contenteditable (settable, with a range) takes text")
check(!P.isEditable(role: nil, valueSettable: false, hasSelectedTextRange: false), "no element takes none")

// MARK: - The host: looks, the caret, what goes out

check(P.hostLooks == [0.15, 0.45], "two looks after a click: \(P.hostLooks)")
check(P.followInterval == 0.25 && P.caretSlack == 0.002, "the follow: 4 a second, 0.2 % of the frame")
check(P.normalized(x: 150, y: 300, w: 2, h: 20, sourceX: 100, sourceY: 200, sourceW: 1000, sourceH: 500)
      == TextFocusRect(x: 0.05, y: 0.2, w: 0.002, h: 0.04), "a caret inside the source")
check(P.normalized(x: 50, y: 300, w: 60, h: 20, sourceX: 100, sourceY: 200, sourceW: 1000, sourceH: 500)?.x == -0.05,
      "a field that starts left of the source but reaches into it is kept, unclamped")
check(P.normalized(x: 1101, y: 300, w: 2, h: 20, sourceX: 100, sourceY: 200, sourceW: 1000, sourceH: 500) == nil, "right of the source: none")
check(P.normalized(x: 150, y: 100, w: 2, h: 20, sourceX: 100, sourceY: 200, sourceW: 1000, sourceH: 500) == nil, "above the source: none")
check(P.normalized(x: 150, y: 701, w: 2, h: 20, sourceX: 100, sourceY: 200, sourceW: 1000, sourceH: 500) == nil, "below the source: none")
check(P.normalized(x: 150, y: 300, w: 2, h: 0, sourceX: 100, sourceY: 200, sourceW: 1000, sourceH: 500) == nil, "an empty caret: none")
check(P.normalized(x: 150, y: 300, w: 2, h: 20, sourceX: 100, sourceY: 200, sourceW: 0, sourceH: 500) == nil, "no source: none")
check(P.normalized(x: 150, y: 690, w: 2, h: 20, sourceX: 100, sourceY: 200, sourceW: 1000, sourceH: 500) != nil, "a caret across the bottom edge is kept")

let caret = TextFocusRect(x: 0.5, y: 0.5, w: 0, h: 0.04)
let a = TextFocus(editable: true, caret: caret, tap: true)
check(P.worthSending(a, after: nil), "the first report goes")
check(!P.worthSending(TextFocus(editable: true, caret: caret, tap: false), after: a), "the same again does not (tap aside)")
check(P.worthSending(TextFocus(editable: false, caret: caret), after: a), "a change of editable goes, the caret where it was")
check(P.worthSending(TextFocus(editable: true), after: a), "the caret going goes")
check(P.worthSending(a, after: TextFocus(editable: true)), "the caret coming goes")
check(!P.worthSending(TextFocus(editable: true, caret: TextFocusRect(x: 0.5015, y: 0.5, w: 0, h: 0.04)), after: a), "a move within the slack does not")
check(P.worthSending(TextFocus(editable: true, caret: TextFocusRect(x: 0.503, y: 0.5, w: 0, h: 0.04)), after: a), "a move across goes")
check(P.worthSending(TextFocus(editable: true, caret: TextFocusRect(x: 0.5, y: 0.53, w: 0, h: 0.04)), after: a), "a new line goes")
check(P.worthSending(TextFocus(editable: true, caret: TextFocusRect(x: 0.5, y: 0.5, w: 0, h: 0.05)), after: a), "a taller caret (its bottom) goes")
check(!P.worthSending(TextFocus(editable: false), after: TextFocus()), "nil editable is false")

// MARK: - The device

typealias K = TextFocusPolicy.Keyboard
let field = TextFocus(editable: true, tap: true)
let elsewhere = TextFocus(editable: false, tap: true)
check(P.answer(field, keyboard: .down, switchOn: true, sinceTap: 0.3) == .open, "a tap in a field opens the keyboard")
check(P.answer(field, keyboard: .byButton, switchOn: true, sinceTap: 0.3) == .keep, "the button's keyboard stays as it is")
check(P.answer(field, keyboard: .byFocus, switchOn: true, sinceTap: 0.3) == .keep, "already up: kept")
check(P.answer(field, keyboard: .hardware, switchOn: true, sinceTap: 0.3) == .keep, "a hardware keyboard's hold is left alone")
check(P.answer(elsewhere, keyboard: .byFocus, switchOn: true, sinceTap: 0.3) == .close, "a tap elsewhere closes the keyboard a field opened")
check(P.answer(elsewhere, keyboard: .byButton, switchOn: true, sinceTap: 0.3) == .keep, "but never the button's")
check(P.answer(elsewhere, keyboard: .hardware, switchOn: true, sinceTap: 0.3) == .keep, "nor a hardware keyboard's")
check(P.answer(elsewhere, keyboard: .down, switchOn: true, sinceTap: 0.3) == .keep, "nothing up: kept")
check(P.answer(TextFocus(tap: true), keyboard: .byFocus, switchOn: true, sinceTap: 0.3) == .close, "no editable at all reads as no field")
check(P.answer(TextFocus(editable: true, tap: false), keyboard: .down, switchOn: true, sinceTap: 0.3) == .keep, "a focus the Mac moved by itself opens nothing")
check(P.answer(TextFocus(editable: false), keyboard: .byFocus, switchOn: true, sinceTap: 0.3) == .keep, "nor closes")
check(P.answer(field, keyboard: .down, switchOn: false, sinceTap: 0.3) == .keep, "the switch off: nothing")
check(P.answer(elsewhere, keyboard: .byFocus, switchOn: false, sinceTap: 0.3) == .keep, "the switch off: nothing closes either")
check(P.answer(field, keyboard: .down, switchOn: true, sinceTap: nil) == .keep, "no click from this device: nothing")
check(P.answer(field, keyboard: .down, switchOn: true, sinceTap: 1.5) == .open, "a click 1.5 s ago still counts")
check(P.answer(field, keyboard: .down, switchOn: true, sinceTap: 1.51) == .keep, "an older one does not")
check(P.answer(field, keyboard: .down, switchOn: true, sinceTap: -0.1) == .keep, "a click from the future does not")

check(P.deviceSubscription(hostTextFocus: 1, switchOn: true, subscribed: false) == (.subscribe, true), "subscribes")
check(P.deviceSubscription(hostTextFocus: 1, switchOn: true, subscribed: true) == (.none, true), "once")
check(P.deviceSubscription(hostTextFocus: 1, switchOn: false, subscribed: true) == (.stop, false), "the switch off: stop")
check(P.deviceSubscription(hostTextFocus: 1, switchOn: false, subscribed: false) == (.none, false), "off and not subscribed: nothing")
check(P.deviceSubscription(hostTextFocus: nil, switchOn: true, subscribed: false) == (.none, false), "an older Mac: nothing")
check(P.deviceSubscription(hostTextFocus: nil, switchOn: true, subscribed: true) == (.none, false), "a Mac that stopped saying it: no stop sent, forgotten")
check(P.deviceSubscription(hostTextFocus: 2, switchOn: true, subscribed: false) == (.subscribe, true), "a later generation still takes ours")

// A model: a device's keyboard through a random run of reports, clicks and button presses. The
// keyboard a report brought up is the only one a report takes down; the button's and a hardware
// keyboard's are never touched; nothing happens without a click of this device's in the window.
var rng = SystemRandomNumberGenerator()
for _ in 0..<2000 {
    var kb: K = [.down, .byButton, .hardware].randomElement(using: &rng)!
    let start = kb
    var lastTap: Double? = nil
    var now = 0.0
    for _ in 0..<30 {
        now += Double.random(in: 0...1, using: &rng)
        switch Int.random(in: 0..<3, using: &rng) {
        case 0: lastTap = now
        case 1:
            let r = TextFocus(editable: Bool.random(using: &rng), tap: Bool.random(using: &rng))
            let since = lastTap.map { now - $0 }
            let ans = P.answer(r, keyboard: kb, switchOn: true, sinceTap: since)
            if ans != .keep {
                check(r.tap == true && since.map { $0 <= P.tapWindow } == true, "model: acted only on a recent click of its own")
            }
            if ans == .close { check(kb == .byFocus, "model: closed only what a report opened") }
            if ans == .open { check(kb == .down, "model: opened only a keyboard that was down") }
            switch ans {
            case .open: kb = .byFocus
            case .close: kb = .down
            case .keep: break
            }
        default:
            if start != .hardware { kb = kb == .down ? .byButton : .down }   // the button
        }
        if start == .hardware { check(kb == .hardware, "model: a hardware keyboard's hold never changes") }
    }
}

print("\(checks) checks, \(failures) failed")
exit(failures == 0 ? 0 : 1)
