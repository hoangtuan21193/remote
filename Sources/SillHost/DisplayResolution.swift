import CoreGraphics
import Foundation

/// The Desktop's text size, the glue around DesktopScalePolicy: the Mac display's modes read and set
/// through Core Graphics (`DisplayModes`), and what the coordinator keeps between pipelines
/// (`DesktopScaler`): the devices' requests, the display's own mode while Sill has it in another,
/// and the note that puts it back after a crash.
///
/// A mode is set with `.forAppOnly`: the window server puts the display back by itself when this
/// process ends, however it ends. The host still puts it back itself, in every case the policy
/// names (`DesktopScalePolicy.target`) and at Quit or a signal (`restoreForExit`), so its log says
/// so; and keeps a note in its defaults while the display is in a mode it set, which the next launch
/// reads (`recoverAtLaunch`) in case the window server did not.
///
/// Only the Desktop's display (`WindowCatalog.display`, the one the Desktop pipeline captures), and
/// only between pipelines: StreamCoordinator's `select` calls `reconcile` after the old stream has
/// stopped and before the next is sized, so a running SCStream is never reconfigured.
///
/// Nothing here prints unless a device asked for the Desktop's text size (or an earlier run's note
/// is found): the CLI's stdout is otherwise unchanged.
enum DisplayModes {
    typealias Mode = DesktopScalePolicy.Mode

    /// `CGDisplayMode` as the policy reads it.
    static func describe(_ m: CGDisplayMode) -> Mode {
        Mode(id: m.ioDisplayModeID, width: m.width, height: m.height, pixelWidth: m.pixelWidth, pixelHeight: m.pixelHeight,
             refresh: m.refreshRate, usable: m.isUsableForDesktopGUI())
    }

    /// Every mode of `display`, the low-resolution twins of HiDPI modes included (the policy leaves
    /// them out for a HiDPI original), each with the `CGDisplayMode` that sets it.
    static func all(_ display: CGDirectDisplayID) -> [(mode: Mode, cg: CGDisplayMode)] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes as String: true] as CFDictionary
        guard let list = CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] else { return [] }
        return list.map { (describe($0), $0) }
    }

    /// The mode `display` is in now.
    static func current(_ display: CGDirectDisplayID) -> Mode? {
        CGDisplayCopyDisplayMode(display).map(describe)
    }

    /// Sets `mode` on `display` for this process's life. Nil when it took, else what went wrong.
    static func apply(_ mode: Mode, to display: CGDirectDisplayID) -> String? {
        guard let cg = all(display).first(where: { $0.mode == mode })?.cg else { return "the display no longer has that mode" }
        var config: CGDisplayConfigRef?
        let begun = CGBeginDisplayConfiguration(&config)
        guard begun == .success, let config else { return "CGBeginDisplayConfiguration: CGError \(begun.rawValue)" }
        let set = CGConfigureDisplayWithDisplayMode(config, display, cg, nil)
        guard set == .success else {
            CGCancelDisplayConfiguration(config)
            return "CGConfigureDisplayWithDisplayMode: CGError \(set.rawValue)"
        }
        let done = CGCompleteDisplayConfiguration(config, .forAppOnly)
        return done == .success ? nil : "CGCompleteDisplayConfiguration: CGError \(done.rawValue)"
    }
}

/// The coordinator's side (main actor): the devices' requests, and the display's own mode while Sill
/// has it in another. A real host changes the Desktop's display; a synthetic host changes nothing,
/// unless TEST ONLY `SILL_TEST_DESKTOP_MODES` gives it a stand-in display (below).
@MainActor
final class DesktopScaler {
    typealias Mode = DesktopScalePolicy.Mode

    /// TEST ONLY. `SILL_TEST_DESKTOP_MODES=1512x982*,1147x745,1352x878,1800x1169,2056x1329` on a test
    /// host (DoorPolicy.isTestHost: a synthetic host that is not Sill.app's own executable): a stand-in
    /// display with these modes (DesktopScalePolicy.testModes: `WxH[@S][*]`, S pixels per point,
    /// default 2, `*` the mode it is in, default the first). The host decides as a real one does and
    /// logs the mode it would set ("TEST: … not applied"), and its window list says `desktopScale` 1,
    /// so a device's text size control can be tried against a loopback host. The real display is
    /// never touched by a synthetic host, with or without it.
    private struct TestDisplay {
        var modes: [Mode]
        var current: Mode
    }

    private enum Backend {
        case real
        case test(TestDisplay)
    }

    /// Nil: nothing to change (a synthetic host without the stand-in), and `desktopScale` not advertised.
    private var backend: Backend?
    private var requests = DesktopScalePolicy.Requests<ObjectIdentifier>()
    /// While the display is in a mode Sill set: which display, its own mode, and the mode set.
    private var changed: (display: CGDirectDisplayID, original: Mode, applied: Mode)?
    /// What `start` prints about the TEST ONLY variable: only when it is set.
    let testHookLine: String?
    private var saidSynthetic = false

    /// The defaults key of the crash note (the host's own domain: Sill.app's bundle ID, the CLI's
    /// executable name): the display, its own mode and the mode set, while one is set.
    static let noteKey = "desktopScaleOriginalMode"

    init(synthetic: Bool, testHost: Bool, environment env: [String: String] = ProcessInfo.processInfo.environment) {
        let spec = env["SILL_TEST_DESKTOP_MODES"]
        switch (spec, synthetic) {
        case (nil, false):
            backend = .real; testHookLine = nil
        case (nil, true):
            backend = nil; testHookLine = nil
        case (let spec?, false):
            backend = .real
            testHookLine = "SILL_TEST_DESKTOP_MODES=\(spec) ignored: only a --synthetic test host takes it."
        case (let spec?, true):
            if !testHost {
                backend = nil
                testHookLine = "SILL_TEST_DESKTOP_MODES=\(spec) ignored: only a test host takes it (one that does not advertise and is not Sill.app itself)."
            } else if let parsed = DesktopScalePolicy.testModes(spec) {
                backend = .test(TestDisplay(modes: parsed.modes, current: parsed.current))
                testHookLine = "TEST: the Desktop's text size uses SILL_TEST_DESKTOP_MODES=\(spec) (in \(parsed.current)), and sets no real display."
            } else {
                backend = nil
                testHookLine = "SILL_TEST_DESKTOP_MODES=\(spec) ignored: comma-separated WxH, @S for pixels per point, * on the current mode."
            }
        }
    }

    /// The window list's `desktopScale`: 1 when this host can change the Desktop's display.
    var advertised: Int? { backend == nil ? nil : 1 }

    // MARK: Requests

    /// A device's viewport (kind 9): `desktop` true asks for `scale` on the Desktop; anything else
    /// takes that device's request back.
    func viewport(from id: ObjectIdentifier, desktop: Bool?, scale: Double?, panel: CGSize) {
        requests.viewport(from: id, desktop: desktop, scale: scale, panel: panel)
        if backend == nil, desktop == true, !saidSynthetic {
            saidSynthetic = true
            print("Desktop text size ignored: a synthetic host changes no display (TEST ONLY SILL_TEST_DESKTOP_MODES stands in for one).")
        }
    }

    func left(_ id: ObjectIdentifier) { requests.left(id) }

    // MARK: Deciding and applying

    /// The display the backend acts on: the Desktop's for a real host, the stand-in's (0) for a test host.
    private func displayID(_ desktop: CGDirectDisplayID?) -> CGDirectDisplayID? {
        switch backend {
        case .real: return desktop
        case .test: return 0
        case nil: return nil
        }
    }

    private func modes(_ display: CGDirectDisplayID) -> (modes: [Mode], current: Mode)? {
        switch backend {
        case .real:
            guard let current = DisplayModes.current(display) else { return nil }
            return (DisplayModes.all(display).map(\.mode), current)
        case .test(let t):
            return (t.modes, t.current)
        case nil:
            return nil
        }
    }

    private func set(_ mode: Mode, on display: CGDirectDisplayID) -> String? {
        switch backend {
        case .real:
            return DisplayModes.apply(mode, to: display)
        case .test(var t):
            guard t.modes.contains(mode) else { return "not one of SILL_TEST_DESKTOP_MODES" }
            t.current = mode
            backend = .test(t)
            return nil
        case nil:
            return "no display"
        }
    }

    private var isTest: Bool { if case .test = backend { return true } else { return false } }

    /// The mode the display should be in and the one it is in, for `desktop` (the Desktop's display):
    /// nil when there is nothing to decide (no display to change, or its mode unreadable).
    private func decide(desktop: CGDirectDisplayID?, desktopStreams: Bool, stopping: Bool)
        -> (display: CGDirectDisplayID, target: Mode, current: Mode, original: Mode)? {
        guard let display = displayID(desktop), let read = modes(display) else { return nil }
        let mine = changed.flatMap { $0.display == display ? $0 : nil }
        let original = DesktopScalePolicy.original(stored: mine?.original, applied: mine?.applied, current: read.current)
        let target = DesktopScalePolicy.target(desktopStreams: desktopStreams, stopping: stopping, request: requests.current,
                                               modes: read.modes, original: original)
        return (display, target, read.current, original)
    }

    /// Whether the next `reconcile` would change the display: the coordinator restarts the Desktop's
    /// pipeline only then.
    func wantsChange(desktop: CGDirectDisplayID?, desktopStreams: Bool) -> Bool {
        if let c = changed, c.display != displayID(desktop) { return true }
        guard let d = decide(desktop: desktop, desktopStreams: desktopStreams, stopping: false) else { return false }
        return d.target != d.current
    }

    /// Brings the display to the mode the policy wants for what streams next (`desktopStreams`), and
    /// returns that mode when it changed it, so the caller can wait for ScreenCaptureKit to see the
    /// new size before it sizes the Desktop's pipeline. Between pipelines only.
    @discardableResult
    func reconcile(desktop: CGDirectDisplayID?, desktopStreams: Bool, stopping: Bool) -> Mode? {
        // The Desktop moved to another display (one unplugged, the arrangement changed): the one
        // Sill changed goes back first.
        if let c = changed, c.display != displayID(desktop) { restore(c) }
        guard let d = decide(desktop: desktop, desktopStreams: desktopStreams, stopping: stopping) else { return nil }
        if let c = changed, c.display == d.display, c.applied != d.current {
            // Someone chose another mode on the Mac: it is the display's own now, never undone.
            print("\(isTest ? "TEST: " : "")Desktop text size: the display was set to \(d.current) on the Mac, which is its own mode now.")
            forget()
        }
        guard d.target != d.current else {
            if d.target == d.original, changed != nil { forget() }
            return nil
        }
        if let problem = set(d.target, on: d.display) {
            print("\(isTest ? "TEST: " : "")Desktop text size: could not set \(d.target) (\(problem)).")
            return nil
        }
        if d.target == d.original {
            print(isTest ? "TEST: Desktop text size: the display would go back to its own \(d.original) (SILL_TEST_DESKTOP_MODES: not applied)."
                         : "Desktop text size: the display back to its own \(d.original).")
            forget()
        } else {
            let scale = requests.current?.scale.map { String(format: "%g", $0) } ?? "1"
            print(isTest ? "TEST: Desktop text size \(scale)×: the display would go to \(d.target) (its own \(d.original); SILL_TEST_DESKTOP_MODES: not applied)."
                         : "Desktop text size \(scale)×: the display goes to \(d.target) (its own \(d.original)).")
            changed = (d.display, d.original, d.target)
            saveNote()
        }
        return d.target
    }

    /// Puts `c`'s display back to its own mode, if it is still in the one Sill set.
    private func restore(_ c: (display: CGDirectDisplayID, original: Mode, applied: Mode)) {
        defer { forget() }
        guard let read = modes(c.display), read.current == c.applied else { return }
        if let problem = set(c.original, on: c.display) {
            print("\(isTest ? "TEST: " : "")Desktop text size: could not put the display back to \(c.original) (\(problem)).")
        } else {
            print(isTest ? "TEST: Desktop text size: the display would go back to its own \(c.original) (SILL_TEST_DESKTOP_MODES: not applied)."
                         : "Desktop text size: the display back to its own \(c.original).")
        }
    }

    /// Quit or a signal (HostShutdown, through the coordinator), on the main queue just before the
    /// process ends: the display goes back now rather than when the window server notices.
    func restoreForExit() {
        if let c = changed { restore(c) }
    }

    // MARK: The crash note

    private func forget() {
        changed = nil
        if case .real = backend { UserDefaults.standard.removeObject(forKey: Self.noteKey) }
    }

    private func saveNote() {
        guard case .real = backend, let c = changed else { return }
        UserDefaults.standard.set(["display": Int(c.display), "original": Self.plist(c.original), "applied": Self.plist(c.applied)],
                                  forKey: Self.noteKey)
    }

    /// At launch, before anything streams (a real host only): an earlier run's note means it ended
    /// while the display was in a mode it set. The display goes back to its own mode if it is still
    /// in that one (DesktopScalePolicy.recovery); the note goes either way. One line, only then.
    func recoverAtLaunch() {
        guard case .real = backend, let note = UserDefaults.standard.dictionary(forKey: Self.noteKey) else { return }
        UserDefaults.standard.removeObject(forKey: Self.noteKey)
        guard let raw = note["display"] as? Int, let original = Self.mode(note["original"]), let applied = Self.mode(note["applied"]) else {
            print("Desktop text size: an earlier run's note was unreadable; the display is left as it is.")
            return
        }
        let display = CGDirectDisplayID(truncatingIfNeeded: raw)
        guard let current = DisplayModes.current(display),
              let back = DesktopScalePolicy.recovery(stored: original, applied: applied, current: current,
                                                     modes: DisplayModes.all(display).map(\.mode)) else {
            print("Desktop text size: an earlier run had set \(applied); the display is no longer in it and is left as it is.")
            return
        }
        if let problem = DisplayModes.apply(back, to: display) {
            print("Desktop text size: could not put the display back to \(back) after an earlier run (\(problem)).")
        } else {
            print("Desktop text size: the display back to its own \(back), which an earlier run had changed.")
        }
    }

    private static func plist(_ m: Mode) -> [String: Any] {
        ["id": Int(m.id), "width": m.width, "height": m.height, "pixelWidth": m.pixelWidth, "pixelHeight": m.pixelHeight,
         "refresh": m.refresh, "usable": m.usable]
    }

    private static func mode(_ any: Any?) -> Mode? {
        guard let d = any as? [String: Any], let id = d["id"] as? Int, let w = d["width"] as? Int, let h = d["height"] as? Int,
              let pw = d["pixelWidth"] as? Int, let ph = d["pixelHeight"] as? Int, let r = d["refresh"] as? Double,
              let u = d["usable"] as? Bool else { return nil }
        return Mode(id: Int32(truncatingIfNeeded: id), width: w, height: h, pixelWidth: pw, pixelHeight: ph, refresh: r, usable: u)
    }
}
