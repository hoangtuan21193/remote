"""Each mutant changes DesktopScalePolicy.swift in one place and must fail the check (main.swift).
usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "desktop-scale")   # the mutants' sources and binaries
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "Sources/SillHost/DesktopScalePolicy.swift")
orig = open(SRC).read()
MUTANTS = {
    "M1 any shape within 5%": ("static let aspectTolerance = 0.01", "static let aspectTolerance = 0.05"),
    "M2 a HiDPI original drops to low resolution": ("if original.isHiDPI && !m.isHiDPI { continue }", ""),
    "M3 unusable modes too": ("for m in modes where m.usable && m.width > 0", "for m in modes where m.width > 0"),
    "M4 HiDPI-ness not preferred": ("if (a.isHiDPI == o.isHiDPI) != (b.isHiDPI == o.isHiDPI) { return a.isHiDPI == o.isHiDPI }\n", ""),
    "M5 the lowest rate, not the original's": ("let da = abs(a.refresh - o.refresh), db = abs(b.refresh - o.refresh)", "let da = a.refresh, db = b.refresh"),
    "M6 the farther rate": ("if abs(da - db) > refreshTolerance { return da < db }", "if abs(da - db) > refreshTolerance { return da > db }"),
    "M7 fewer pixels": ("return a.pixelWidth > b.pixelWidth", "return a.pixelWidth < b.pixelWidth"),
    "M8 the original not its size's candidate": ("        best[\"\\(original.width)x\\(original.height)\"] = original\n", ""),
    "M9 a band of 5% around 1": ("static let unchangedBand = 0.005", "static let unchangedBand = 0.05"),
    "M10 nearest in difference": ("let d = abs(log(textScale(of: m, original: original, panel: panel) / scale))",
                                  "let d = abs(textScale(of: m, original: original, panel: panel) - scale)"),
    "M11 ties to the smaller": ("(abs(d - distance) <= 1e-9 && m.width > chosen.width)", "(abs(d - distance) <= 1e-9 && m.width < chosen.width)"),
    "M12 fit by the larger side": ("min(Double(panel.width) / Double(width), Double(panel.height) / Double(height))",
                                   "max(Double(panel.width) / Double(width), Double(panel.height) / Double(height))"),
    "M13 text scale inverted": ("return fit(panel, width: mode.width, height: mode.height) / fit(panel, width: original.width, height: original.height)",
                                "return fit(panel, width: original.width, height: original.height) / fit(panel, width: mode.width, height: mode.height)"),
    "M14 no panel ignored": ("guard usable else { return Double(original.width) / Double(mode.width) }", ""),
    "M15 the Desktop not streaming ignored": ("guard desktopStreams, !stopping, let request", "guard !stopping, let request"),
    "M16 stopping ignored": ("guard desktopStreams, !stopping, let request", "guard desktopStreams, let request"),
    "M17 the first request followed": ("var current: Request? { order.last?.request }", "var current: Request? { order.first?.request }"),
    "M18 nil counts as desktop": ("if desktop == true { order.append", "if desktop != false { order.append"),
    "M19 a re-sent viewport kept twice": ("            order.removeAll { $0.device == device }\n            if desktop", "            if desktop"),
    "M20 a device leaving keeps its request": ("mutating func left(_ device: Device) { order.removeAll { $0.device == device } }", "mutating func left(_ device: Device) { }"),
    "M21 a change on the Mac undone": ("if let stored, let applied, applied == current { return stored }", "if let stored, applied != nil { return stored }"),
    "M22 recovery over a change on the Mac": ("guard current == applied, stored != current, modes.contains(stored)", "guard stored != current, modes.contains(stored)"),
    "M23 recovery to a mode not listed": ("guard current == applied, stored != current, modes.contains(stored)", "guard current == applied, stored != current"),
    "M24 test modes at 1x by default": ("let backing = parts.count == 2 ? Int(parts[1]) : 2", "let backing = parts.count == 2 ? Int(parts[1]) : 1"),
    "M25 test modes up to 4x": ("(1...3).contains(backing)", "(1...4).contains(backing)"),
    "M26 two stars taken": ("                guard current == nil else { return nil }\n", ""),
    "M27 rates apart taken as one": ("static let refreshTolerance = 0.5", "static let refreshTolerance = 30.0"),
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
