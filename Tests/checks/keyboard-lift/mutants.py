"""Mutants of KeyboardLift.swift (iOSClient): each changes it in one place, compiles it with the check
(main.swift) and expects the check to fail. usage: mutants.py WORKTREE"""
import os, subprocess, sys, tempfile
WT = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
F = "iOSClient/KeyboardLift.swift"
MUTANTS = [
    ("no margin", "static let margin: CGFloat = 12", "static let margin: CGFloat = 0"),
    ("the tap's line 44 pt", "static let tapLine: CGFloat = 24", "static let tapLine: CGFloat = 44"),
    ("no top bound", "        if let caret {\n            if caret.minY - lift < topMargin { lift = caret.minY - topMargin }\n", "        if let caret {\n"),
    ("no bottom bound", "            if caret.maxY - lift > keyboardTop - margin { lift = caret.maxY + margin - keyboardTop }\n", ""),
    ("the caret's top against the keyboard", "lift = caret.maxY + margin - keyboardTop", "lift = caret.minY + margin - keyboardTop"),
    ("no upper clamp", "return min(max(lift, 0), most)", "return max(lift, 0)"),
    ("below zero", "return min(max(lift, 0), most)", "return min(lift, most)"),
    ("always from zero", "        var lift = current\n", "        var lift: CGFloat = 0\n"),
    ("no keyboard lifts as it was", "guard let keyboardTop, height > 0 else { return 0 }", "guard let keyboardTop = keyboardTop ?? Optional(0), height > 0 else { return 0 }"),
    ("the caret's y not offset", "y: video.minY + CGFloat(y) * video.height", "y: CGFloat(y) * video.height"),
    ("a floating keyboard counts", "frame.width >= screen.width - 1, frame.maxY", "frame.maxY"),
    ("an undocked keyboard counts", "frame.maxY >= screen.maxY - 1 else", "frame.maxY >= 0 else"),
    ("the keyboard's top not measured from the panel", "return frameTop - viewTop", "return frameTop"),
    ("a tap's line from its top", "CGRect(x: point.x, y: point.y - tapLine / 2", "CGRect(x: point.x, y: point.y"),
]
caught = 0
for name, old, new in MUTANTS:
    text = open(os.path.join(WT, F)).read()
    if text.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {text.count(old)} times)"); continue
    with tempfile.TemporaryDirectory() as t:
        src = os.path.join(t, "KeyboardLift.swift"); open(src, "w").write(text.replace(old, new, 1))
        exe = os.path.join(t, "check")
        c = subprocess.run(["swiftc", "-O", src, os.path.join(HERE, "main.swift"), "-o", exe], capture_output=True, text=True)
        if c.returncode != 0:
            print(f"{name}: did not compile\n{c.stderr[:400]}"); continue
        r = subprocess.run([exe], capture_output=True, text=True, timeout=300)
        failed = [l for l in r.stdout.splitlines() if l.startswith("FAIL")]
        if r.returncode != 0:
            caught += 1; print(f"{name}: caught ({failed[0][:100] if failed else f'exit status {r.returncode}'})")
        else:
            print(f"{name}: NOT CAUGHT")
print(f"mutants caught: {caught} of {len(MUTANTS)}")
sys.exit(0 if caught == len(MUTANTS) else 1)
