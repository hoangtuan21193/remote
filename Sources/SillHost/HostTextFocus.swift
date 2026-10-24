import ApplicationServices
import Foundation
import Network
import StreamProtocol

/// The Mac's text focus, the host's side (kind 33; docs/keyboard-auto-plan.md). The rules are
/// TextFocusPolicy's; this reads the focused element through Accessibility and keeps who subscribed.
///
/// - A device subscribes with any kind 33 (an empty one at connect, while its Open Keyboard
///   Automatically is on) and stops with `stop`; one line each. A device that leaves is forgotten
///   without a line.
/// - A subscriber's click (its left button's up, `clicked`) is answered to that device alone: the
///   focus is looked at `TextFocusPolicy.hostLooks` after it, and the first look that finds a text
///   field, or else the last, goes out with `tap`.
/// - While the focus is in a text field, every subscriber is told when the caret moves or the focus
///   leaves (`followInterval`; only what `worthSending` takes), without `tap`.
/// - Never the field's text: its role, whether its value can be set, its selection range and the
///   caret's bounds are all that is read.
/// - Electron apps (Slack, VS Code, Discord…) build their accessibility tree only when asked: the
///   frontmost app is asked once per launch of it (`AXManualAccessibility`, which other apps ignore).
///   Not `AXEnhancedUserInterface`, which breaks window animations (the plan's D3).
///
/// TEST ONLY, on a synthetic host: SILL_TEST_TEXT_FOCUS stands in for Accessibility, which such a host
/// never reads: `field` (a text field, its caret at 40 % across and half way down the frame), `none`,
/// or the path of a file holding one of them or `x,y,w,h` (a field with that caret, as fractions of the
/// frame), read at each look, so a test can move it while it runs.
///
/// Threading: main actor for the subscribers and the lines; Accessibility is read on a queue of its
/// own, with a short messaging timeout, so an app that hangs never holds up the main actor, where
/// devices' input is handled.
@MainActor
final class HostTextFocus {
    /// The window lists' `textFocus`.
    var advertised: Int? { TextFocusPolicy.generation }

    private let server: StreamServer
    /// The streamed source's rectangle in global points (the coordinator's `currentSourceRect`, set
    /// once it is made), nil while nothing streams.
    var sourceRect: () -> CGRect? = { nil }
    private let reader: Reader
    /// The test hooks' line for `start`, nil without them.
    let testHookLine: String?

    private var subscribers: [ObjectIdentifier: (connection: NWConnection, who: String)] = [:]
    private var order: [ObjectIdentifier] = []
    /// What each subscriber was last sent, for `worthSending`.
    private var lastSent: [ObjectIdentifier: TextFocus] = [:]
    /// The looks after a click, per connection: a new click replaces its device's.
    private var afterClick: [ObjectIdentifier: Task<Void, Never>] = [:]
    /// The follow while the focus is in a text field.
    private var follow: Task<Void, Never>?

    init(server: StreamServer, synthetic: Bool, environment env: [String: String] = ProcessInfo.processInfo.environment) {
        self.server = server
        switch (env["SILL_TEST_TEXT_FOCUS"], synthetic) {
        case (nil, _), ("", _):
            reader = Reader(test: synthetic ? .fixed(nil) : nil)
            testHookLine = nil
        case (let spec?, true):
            reader = Reader(test: Reader.Test(spec))
            testHookLine = "Test text focus: SILL_TEST_TEXT_FOCUS=\(spec) stands in for Accessibility."
        case (let spec?, false):
            reader = Reader(test: nil)
            testHookLine = "SILL_TEST_TEXT_FOCUS=\(spec) ignored: only a --synthetic host takes it."
        }
    }

    // MARK: A device's message

    /// A kind 33 from `connection`, named `who` for the lines.
    func received(_ payload: Data, from connection: NWConnection, who: String) {
        let id = ObjectIdentifier(connection)
        guard let message = Wire.decode(TextFocus.self, from: payload) else { return }
        if message.stop == true {
            guard let gone = subscribers.removeValue(forKey: id) else { return }
            forget(id)
            print("Text focus: \(gone.who) no longer opens its keyboard for text fields.")
            return
        }
        guard subscribers[id] == nil else { return }
        subscribers[id] = (connection, who)
        order.append(id)
        print("Text focus: \(who) opens its keyboard for text fields.")
    }

    /// The device left: forgotten without a line.
    func clientLeft(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        guard subscribers.removeValue(forKey: id) != nil else { return }
        forget(id)
    }

    private func forget(_ id: ObjectIdentifier) {
        order.removeAll { $0 == id }
        lastSent[id] = nil
        afterClick.removeValue(forKey: id)?.cancel()
        if subscribers.isEmpty { follow?.cancel(); follow = nil }
    }

    // MARK: A click

    /// A device's input reached the Mac: its left button's up, from a subscriber, starts the looks
    /// after it.
    func input(_ event: InputEvent, from connection: NWConnection) {
        guard case .pointer(.leftUp, _, _) = event else { return }
        let id = ObjectIdentifier(connection)
        guard subscribers[id] != nil else { return }
        afterClick[id]?.cancel()
        afterClick[id] = Task { @MainActor [weak self] in
            var waited = 0.0
            for (index, at) in TextFocusPolicy.hostLooks.enumerated() {
                try? await Task.sleep(for: .seconds(at - waited))
                waited = at
                guard !Task.isCancelled, let self else { return }
                let found = await self.look()
                guard !Task.isCancelled, self.subscribers[id] != nil else { return }
                let last = index == TextFocusPolicy.hostLooks.count - 1
                guard found.editable == true || last else { continue }
                var report = found
                report.tap = true
                self.send(report, to: id)
                self.afterClick[id] = nil
                if found.editable == true { self.startFollowing() }
                return
            }
        }
    }

    // MARK: The follow

    private func startFollowing() {
        guard follow == nil else { return }
        follow = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(TextFocusPolicy.followInterval))
                guard !Task.isCancelled, let self else { return }
                let found = await self.look()
                guard !Task.isCancelled else { return }
                for id in self.order where TextFocusPolicy.worthSending(found, after: self.lastSent[id]) {
                    self.send(found, to: id)
                }
                // Out of the field: the follow ends, until the next click finds one.
                if found.editable != true { self.follow = nil; return }
            }
        }
    }

    // MARK: Reading and sending

    /// The focus now, its caret as fractions of the streamed source; not editable while nothing streams.
    private func look() async -> TextFocus {
        guard let rect = sourceRect() else { return TextFocus(editable: false) }
        let read = await reader.read()
        guard read.editable else { return TextFocus(editable: false) }
        let caret = read.caret.flatMap {
            TextFocusPolicy.normalized(x: $0.minX, y: $0.minY, w: $0.width, h: $0.height,
                                       sourceX: rect.minX, sourceY: rect.minY, sourceW: rect.width, sourceH: rect.height)
        } ?? read.fraction
        return TextFocus(editable: true, caret: caret)
    }

    private func send(_ report: TextFocus, to id: ObjectIdentifier) {
        guard let connection = subscribers[id]?.connection else { return }
        lastSent[id] = report
        server.send(StreamMessage(kind: .textFocus, timestamp: Date().timeIntervalSince1970, isKeyframe: false,
                                  payload: Wire.encode(report)), to: connection)
        Stats.shared.bump("focus.sent")
    }

    /// Accessibility, read on `queue` alone, one read at a time.
    private final class Reader: @unchecked Sendable {
        /// A synthetic host's stand-in.
        enum Test {
            case fixed(TextFocusRect?)
            case none
            case file(String)

            init(_ spec: String) {
                if spec.hasPrefix("/") { self = .file(spec) } else { self = Self.parse(spec) }
            }

            static func parse(_ word: String) -> Test {
                switch word {
                case "field": return .fixed(TextFocusRect(x: 0.4, y: 0.5, w: 0.002, h: 0.04))
                case "none": return .none
                default:
                    let parts = word.split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
                    guard parts.count == 4 else { return .none }
                    return .fixed(TextFocusRect(x: parts[0], y: parts[1], w: parts[2], h: parts[3]))
                }
            }
        }

        struct Read {
            var editable = false
            /// The caret (or the field) in global points.
            var caret: CGRect?
            /// A test's caret, already as fractions of the frame.
            var fraction: TextFocusRect?
        }

        private let queue = DispatchQueue(label: "sill.textfocus", qos: .userInitiated)
        private let test: Test?
        /// The apps asked for their accessibility tree (`AXManualAccessibility`), by pid.
        private var asked: Set<pid_t> = []

        init(test: Test?) { self.test = test }

        func read() async -> Read {
            await withCheckedContinuation { done in
                queue.async { done.resume(returning: self.readNow()) }
            }
        }

        private func readNow() -> Read {
            if let test { return Self.read(test) }
            let system = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(system, 0.25)
            if let app: AXUIElement = Self.copy(system, kAXFocusedApplicationAttribute) {
                var pid: pid_t = 0
                if AXUIElementGetPid(app, &pid) == .success, !asked.contains(pid) {
                    asked.insert(pid)
                    AXUIElementSetMessagingTimeout(app, 0.25)
                    AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)
                }
            }
            guard let element: AXUIElement = Self.copy(system, kAXFocusedUIElementAttribute) else { return Read() }
            AXUIElementSetMessagingTimeout(element, 0.25)
            let role: String? = Self.copy(element, kAXRoleAttribute)
            var settable = DarwinBoolean(false)
            let canSet = AXUIElementIsAttributeSettable(element, kAXValueAttribute as CFString, &settable) == .success && settable.boolValue
            let range: AXValue? = Self.copy(element, kAXSelectedTextRangeAttribute)
            guard TextFocusPolicy.isEditable(role: role, valueSettable: canSet, hasSelectedTextRange: range != nil) else { return Read() }
            return Read(editable: true, caret: Self.caret(of: element, range: range) ?? Self.frame(of: element))
        }

        private static func read(_ test: Test) -> Read {
            switch test {
            case .fixed(let caret): return Read(editable: caret != nil, fraction: caret)
            case .none: return Read()
            case .file(let path):
                let word = (try? String(contentsOfFile: path, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "none"
                if case .file = Test(word) { return Read() }
                return read(Test(word))
            }
        }

        /// The caret's bounds: the selection's, or for an insertion point the bounds of a zero-length
        /// range at it, else of the character before it (some apps answer nothing for a zero length).
        private static func caret(of element: AXUIElement, range: AXValue?) -> CGRect? {
            guard let range else { return nil }
            var selected = CFRange()
            guard AXValueGetValue(range, .cfRange, &selected) else { return nil }
            var tries = [selected]
            if selected.length == 0, selected.location > 0 { tries.append(CFRange(location: selected.location - 1, length: 1)) }
            for var r in tries {
                guard let asked = AXValueCreate(.cfRange, &r) else { continue }
                var out: CFTypeRef?
                guard AXUIElementCopyParameterizedAttributeValue(element, kAXBoundsForRangeParameterizedAttribute as CFString,
                                                                 asked, &out) == .success,
                      let value = out, CFGetTypeID(value) == AXValueGetTypeID() else { continue }
                var rect = CGRect.zero
                guard AXValueGetValue(value as! AXValue, .cgRect, &rect), rect.height > 0 else { continue }
                // The character before the caret: the caret is at its right edge.
                if r.location != selected.location { rect = CGRect(x: rect.maxX, y: rect.minY, width: 0, height: rect.height) }
                return rect
            }
            return nil
        }

        /// The element's own frame, for an app that gives no caret.
        private static func frame(of element: AXUIElement) -> CGRect? {
            guard let position: AXValue = copy(element, kAXPositionAttribute),
                  let size: AXValue = copy(element, kAXSizeAttribute) else { return nil }
            var origin = CGPoint.zero, extent = CGSize.zero
            guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(size, .cgSize, &extent) else { return nil }
            return CGRect(origin: origin, size: extent)
        }

        private static func copy<T>(_ element: AXUIElement, _ attribute: String) -> T? {
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success, let value else { return nil }
            return value as? T
        }
    }
}
