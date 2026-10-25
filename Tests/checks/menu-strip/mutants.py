"""Each mutant changes MenuStripLayout.swift in one place and must fail the check (main.swift).
usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "menu-strip")   # the mutants' sources and binaries
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/MenuStripLayout.swift")
orig = open(SRC).read()
MUTANTS = {
    "M1 the strip 28 pt": ("static let height: CGFloat = 32", "static let height: CGFloat = 28"),
    "M2 the titles from the edge": ("static let side: CGFloat = 8", "static let side: CGFloat = 0"),
    "M3 the titles' padding 8": ("static let titlePad: CGFloat = 10", "static let titlePad: CGFloat = 8"),
    "M4 the » 44 wide": ("static let moreWidth: CGFloat = 40", "static let moreWidth: CGFloat = 44"),
    "M5 the tab's room ignored": ("let end = width - Self.side - max(0, trailingRoom)", "let end = width - Self.side"),
    "M6 across the fold": ("if let fold, x < fold.upperBound, x + width > fold.lowerBound { x = fold.upperBound }", ""),
    "M7 one padding a title": ("let width = max(0, w) + 2 * titlePad", "let width = max(0, w) + titlePad"),
    "M8 the » without room for itself": ("let moreX = end - Self.moreWidth", "let moreX = end"),
    "M9 a title past the end": ("guard x + width <= end else { break }", "guard x <= end else { break }"),
    "M10 a title skipped, not the rest": ("guard x + width <= end else { break }", "guard x + width <= end else { continue }"),
    "M11 titles overlapping": ("            x += width\n", "            x += width - 1\n"),
    "M12 the overflow from the second": ("overflow = Array(shown.count..<titleWidths.count)", "overflow = Array(min(shown.count + 1, titleWidths.count)..<titleWidths.count)"),
    "M13 the » always": ("            more = nil\n", "            more = CGRect(x: end - Self.moreWidth, y: 0, width: Self.moreWidth, height: Self.height)\n"),
    "M14 the fold's start taken as its end": ("{ x = fold.upperBound }", "{ x = fold.lowerBound }"),
}
caught = 0
for name, (old, new) in MUTANTS.items():
    if orig.count(old) != 1:
        print(f"{name}: NOT APPLIED (pattern found {orig.count(old)} times)"); continue
    path = os.path.join(OUT, "mutant.swift")
    open(path, "w").write(orig.replace(old, new))
    b = subprocess.run(["swiftc", "-O", path, os.path.join(SP, "main.swift"), "-o", os.path.join(OUT, "mutant")],
                       capture_output=True, text=True)
    if b.returncode != 0:
        print(f"{name}: DOES NOT COMPILE\n{b.stderr[:600]}"); continue
    r = subprocess.run([os.path.join(OUT, "mutant")], capture_output=True, text=True, timeout=300)
    failed = [l[5:] for l in r.stdout.splitlines() if l.startswith("FAIL")]
    ok = r.returncode != 0
    caught += ok
    print(f"{'caught' if ok else 'MISSED'} {name}: {len(failed)} failing, e.g. {[f[:100] for f in failed[:2]]}")
print(f"{caught} of {len(MUTANTS)} mutants caught")
sys.exit(0 if caught == len(MUTANTS) else 1)
