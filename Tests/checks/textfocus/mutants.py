"""Mutants of the text focus's wire and rules (docs/keyboard-auto-plan.md): each copies Sources/StreamProtocol,
changes TextFocus.swift, StreamMessage.swift or Switcher.swift in one place, compiles it with the check
(main.swift) and expects the check to fail. usage: mutants.py WORKTREE"""
import os, shutil, subprocess, sys, tempfile
WT = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
P = "TextFocus.swift"
MUTANTS = [
    # The wire.
    ("kind 33 as 34", "StreamMessage.swift", "case textFocus = 33", "case textFocus = 34"),
    ("the list's textFocus never stored", "Switcher.swift", "self.textFocus = textFocus", "self.textFocus = nil"),
    ("textFocus 1 by default", "Switcher.swift", "                textFocus: Int? = nil) {", "                textFocus: Int? = 1) {"),
    ("stop false by default (a subscription is no longer {})", P, "tap: Bool? = nil, stop: Bool? = nil) {", "tap: Bool? = nil, stop: Bool? = false) {"),
    ("generation 2", P, "public static let generation = 1", "public static let generation = 2"),
    ("the subscription says stop", P, "public static var subscription: Data { Wire.encode(TextFocus()) }", "public static var subscription: Data { Wire.encode(TextFocus(stop: true)) }"),
    ("stopping says nothing", P, "public static var stopping: Data { Wire.encode(TextFocus(stop: true)) }", "public static var stopping: Data { Wire.encode(TextFocus()) }"),
    # The host.
    ("a text area takes nothing", P, '["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]', '["AXTextField", "AXComboBox", "AXSearchField"]'),
    ("a search field takes nothing", P, '["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]', '["AXTextField", "AXTextArea", "AXComboBox"]'),
    ("any settable value takes text", P, "return valueSettable && hasSelectedTextRange", "return valueSettable"),
    ("any selection range takes text", P, "return valueSettable && hasSelectedTextRange", "return hasSelectedTextRange"),
    ("one look only", P, "public static let hostLooks: [Double] = [0.15, 0.45]", "public static let hostLooks: [Double] = [0.15]"),
    ("the caret not divided by the width", P, "w: w / sourceW, h: h / sourceH)", "w: w, h: h / sourceH)"),
    ("y against x", P, "y: (y - sourceY) / sourceH", "y: (y - sourceX) / sourceH"),
    ("an empty caret kept", P, "guard sourceW > 0, sourceH > 0, w >= 0, h > 0 else { return nil }", "guard sourceW > 0, sourceH > 0, w >= 0 else { return nil }"),
    ("right of the source kept", P, "guard r.x + r.w >= 0, r.x <= 1, r.y + r.h >= 0, r.y <= 1 else { return nil }", "guard r.x + r.w >= 0, r.y + r.h >= 0, r.y <= 1 else { return nil }"),
    ("below the source kept", P, "guard r.x + r.w >= 0, r.x <= 1, r.y + r.h >= 0, r.y <= 1 else { return nil }", "guard r.x + r.w >= 0, r.x <= 1, r.y + r.h >= 0 else { return nil }"),
    ("a change of editable not sent", P, "        if (now.editable ?? false) != (last.editable ?? false) { return true }\n", ""),
    ("the caret's height ignored", P, "\n                || abs(a.y + a.h - b.y - b.h) > caretSlack", ""),
    ("the caret coming or going not sent", P, "        default: return true\n        }\n    }\n\n    // MARK: The device", "        default: return false\n        }\n    }\n\n    // MARK: The device"),
    ("every caret move sent", P, "public static let caretSlack = 0.002", "public static let caretSlack = 0.0"),
    # The device.
    ("a focus the Mac moved opens", P, "guard switchOn, report.tap == true, let sinceTap,", "guard switchOn, let sinceTap,"),
    ("the switch ignored", P, "guard switchOn, report.tap == true, let sinceTap,", "guard report.tap == true, let sinceTap,"),
    ("any old click counts", P, "sinceTap >= 0, sinceTap <= tapWindow else", "sinceTap >= 0 else"),
    ("a 2 s window", P, "public static let tapWindow = 1.5", "public static let tapWindow = 2.0"),
    ("the button's keyboard taken over", P, "return keyboard == .down ? .open : .keep", "return keyboard == .hardware ? .keep : .open"),
    ("the button's keyboard closed", P, "return keyboard == .byFocus ? .close : .keep", "return keyboard == .down ? .keep : .close"),
    ("nothing ever closes", P, "return keyboard == .byFocus ? .close : .keep", "return .keep"),
    ("a stop to a Mac that no longer takes it", P, "case (false, true): return (takes ? .stop : .none, false)", "case (false, true): return (.stop, false)"),
    ("no stop when the switch goes off", P, "case (false, true): return (takes ? .stop : .none, false)", "case (false, true): return (.none, false)"),
    ("a later generation refused", P, "let takes = (hostTextFocus ?? 0) >= generation", "let takes = hostTextFocus == generation"),
]
caught = 0
for name, file, old, new in MUTANTS:
    with tempfile.TemporaryDirectory() as t:
        src = os.path.join(t, "StreamProtocol"); shutil.copytree(os.path.join(WT, "Sources/StreamProtocol"), src)
        path = os.path.join(src, file); text = open(path).read()
        if text.count(old) != 1:
            print(f"{name}: NOT APPLIED (pattern found {text.count(old)} times)"); continue
        open(path, "w").write(text.replace(old, new, 1))
        files = [os.path.join(src, f) for f in sorted(os.listdir(src)) if f.endswith(".swift")]
        exe = os.path.join(t, "check")
        c = subprocess.run(["swiftc", "-O", *files, os.path.join(HERE, "main.swift"), "-o", exe], capture_output=True, text=True)
        if c.returncode != 0:
            print(f"{name}: did not compile\n{c.stderr[:400]}"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1
            print(f"{name}: caught ({failed[0][:100] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
