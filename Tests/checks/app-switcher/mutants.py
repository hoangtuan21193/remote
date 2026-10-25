"""Each mutant changes AppSwitcherPolicy.swift in one place and must fail the check (main.swift).
usage: mutants.py"""
import os, subprocess, sys
SP = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(SP, "..", "..", ".."))   # the repository
OUT = os.path.join(ROOT, ".build", "checks", "app-switcher")   # the mutants' sources and binaries
os.makedirs(OUT, exist_ok=True)
SRC = os.path.join(ROOT, "iOSClient/AppSwitcherPolicy.swift")
orig = open(SRC).read()
MUTANTS = {
    'M1 a pause of 0.4': ('static let pause: Double = 0.6', 'static let pause: Double = 0.4'),
    'M2 an app not moved first when used again': ('order.removeAll { $0 == bundleID }\n            order.insert(bundleID, at: 0)', 'if !order.contains(bundleID) { order.append(bundleID) }'),
    'M3 no Desktop tile': ('return [.desktop] + (used + rest).map { .app($0) }', 'return (used + rest).map { .app($0) }'),
    'M4 the Desktop tile last': ('return [.desktop] + (used + rest).map { .app($0) }', 'return (used + rest).map { .app($0) } + [.desktop]'),
    "M5 the window list's order, not the recent one": ('return [.desktop] + (used + rest).map { .app($0) }', 'return [.desktop] + apps.map { .app($0) }'),
    'M6 open on what streams, not one step from it': ('lit = Self.step(from, forward: forward, count: tiles.count)', 'lit = max(0, from)'),
    'M7 the pause not restarted by a step': ('        chooseAt = now + Self.pause\n    }', '        if chooseAt == nil { chooseAt = now + Self.pause }\n    }'),
    'M8 no wrap round the ends': ('return ((next % count) + count) % count', 'return min(max(next, 0), count - 1)'),
    'M9 left steps back': ('let next = index + (forward ? 1 : -1)', 'let next = index + (forward ? -1 : 1)'),
    'M10 chosen before the pause': ('guard let at = chooseAt, now >= at, let i = lit', 'guard let _ = chooseAt, let i = lit'),
    'M11 the row open after a choice': ('        let tile = tiles[i]\n        close()\n        return tile\n    }\n\n    /// A tap', '        let tile = tiles[i]\n        chooseAt = nil\n        return tile\n    }\n\n    /// A tap'),
    'M12 a tap with no row chooses': ('guard isOpen, tiles.indices.contains(index) else { return nil }', 'guard tiles.indices.contains(index) || !isOpen else { return nil }'),
    'M13 the Desktop chosen again while it streams': ('return showing == .desktop ? nil : .desktop', 'return .desktop'),
    "M14 an app's first window, never its last seen": ('if let last = recents.lastWindow[bundleID], mine.contains(where: { $0.id == last }) { return .window(last) }', ''),
    'M15 the streaming app chosen again': ('if case .window(let id) = showing, mine.contains(where: { $0.id == id }) { return nil }', ''),
    'M16 a gone last window still chosen': ('if let last = recents.lastWindow[bundleID], mine.contains(where: { $0.id == last }) { return .window(last) }', 'if let last = recents.lastWindow[bundleID] { return .window(last) }'),
    'M17 the tiles rebuilt on each swipe': ('if lit == nil {\n            tiles = Self.tiles', 'if true {\n            tiles = Self.tiles'),
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
