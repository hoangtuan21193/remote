import Foundation

/// Kind 33, both ways: the Mac's text focus, so a device brings its keyboard up when a tap lands in a
/// text field and keeps the caret above it (docs/keyboard-auto-plan.md). The rules are
/// TextFocusPolicy's.
///
/// - Device → host, only to a host whose window list says `textFocus` 1 or more: any kind 33
///   subscribes the connection (an empty one, `{}`, at connect while the device's Open Keyboard
///   Automatically is on); `stop: true` ends the subscription and wins over anything else in it.
/// - Host → device, only to a connection that subscribed: whether the focused element of the
///   streamed Mac is a text field (`editable`), where its caret is in the streamed frame (`caret`),
///   and whether the report answers that device's own click (`tap`). Never the field's text.
///
/// HostSettings.swift's rules apply: JSON; every field optional and left out when nil, so `{}` is a
/// subscription; fields added later are optional.
public struct TextFocus: Codable, Hashable, Sendable {
    /// Host → device: the Mac's focused element takes text (TextFocusPolicy.isEditable).
    public var editable: Bool?
    /// Host → device: the caret, or the field when the app gives no caret, as fractions of the
    /// streamed frame; nil when it is outside the frame or unknown.
    public var caret: TextFocusRect?
    /// Host → device: true when this report is the look after this connection's click
    /// (TextFocusPolicy.hostLooks); false or nil for a change the Mac made by itself.
    public var tap: Bool?
    /// Device → host: true, this device's switch went off; the host sends it nothing more until its
    /// next kind 33. Never from a host.
    public var stop: Bool?

    public init(editable: Bool? = nil, caret: TextFocusRect? = nil, tap: Bool? = nil, stop: Bool? = nil) {
        self.editable = editable; self.caret = caret; self.tap = tap; self.stop = stop
    }
}

/// A rectangle as fractions of the streamed frame, top-left origin, as `InputEvent` positions are.
public struct TextFocusRect: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x; self.y = y; self.w = w; self.h = h
    }
}

/// The rules of kind 33 for both sides. Pure: Foundation only, checked in Tests/checks/textfocus.
public enum TextFocusPolicy {
    /// `WindowList.textFocus` from a host that sends kind 33.
    public static let generation = 1

    /// What a device sends to subscribe, and to stop.
    public static var subscription: Data { Wire.encode(TextFocus()) }
    public static var stopping: Data { Wire.encode(TextFocus(stop: true)) }

    // MARK: The host

    /// The Accessibility roles that take typed text: fields, text views (Terminal's, a web page's
    /// textarea), combo boxes and search fields. Any other element whose value can be set and that
    /// has a selected text range takes text too (a web page's contenteditable).
    public static let editableRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    public static func isEditable(role: String?, valueSettable: Bool, hasSelectedTextRange: Bool) -> Bool {
        if let role, editableRoles.contains(role) { return true }
        return valueSettable && hasSelectedTextRange
    }

    /// When the host looks at the focus after a subscriber's click (its left button's up), in seconds:
    /// soon, and once more for an app that moves its focus a moment late. The first look that finds a
    /// text field reports it; otherwise the last look reports what it found.
    public static let hostLooks: [Double] = [0.15, 0.45]

    /// While the focus is in a text field, how often the host looks again for the caret moving
    /// (typing, an arrow, a click inside the field), and the change in either edge, as a fraction of
    /// the frame, that is worth a report.
    public static let followInterval = 0.25
    public static let caretSlack = 0.002

    /// The caret (or the field), in the same global points as the streamed source's rectangle, as
    /// fractions of that rectangle; nil when it is empty or lies wholly outside it.
    public static func normalized(x: Double, y: Double, w: Double, h: Double,
                                  sourceX: Double, sourceY: Double, sourceW: Double, sourceH: Double) -> TextFocusRect? {
        guard sourceW > 0, sourceH > 0, w >= 0, h > 0 else { return nil }
        let r = TextFocusRect(x: (x - sourceX) / sourceW, y: (y - sourceY) / sourceH, w: w / sourceW, h: h / sourceH)
        guard r.x + r.w >= 0, r.x <= 1, r.y + r.h >= 0, r.y <= 1 else { return nil }
        return r
    }

    /// A report is worth sending: the first, a change of `editable`, or the caret moved by more than
    /// `caretSlack` (or came or went).
    public static func worthSending(_ now: TextFocus, after last: TextFocus?) -> Bool {
        guard let last else { return true }
        if (now.editable ?? false) != (last.editable ?? false) { return true }
        switch (now.caret, last.caret) {
        case (nil, nil): return false
        case let (a?, b?):
            return abs(a.x - b.x) > caretSlack || abs(a.y - b.y) > caretSlack
                || abs(a.y + a.h - b.y - b.h) > caretSlack
        default: return true
        }
    }

    // MARK: The device

    /// What holds the device's keyboard when a report comes.
    public enum Keyboard: Equatable, Sendable {
        /// Nothing: the software keyboard is down.
        case down
        /// The person's, from the Keyboard button.
        case byButton
        /// The person's, brought up by a report (`open` below).
        case byFocus
        /// A hardware keyboard's hold: typing already reaches the Mac, nothing is drawn.
        case hardware
    }

    public enum Answer: Equatable, Sendable {
        case open, close, keep
    }

    /// How long after this device's last click a report still answers it, in seconds: the host's
    /// last look and a slow link's way back.
    public static let tapWindow = 1.5

    /// What the device does with a report. Only a report that answers this device's own click acts
    /// (a focus the Mac moved by itself never brings the keyboard up or takes it down), only while the
    /// switch is on, and only for a click of at most `tapWindow` ago. A text field brings the keyboard
    /// up when nothing holds it; anything else takes down only a keyboard a report brought up. The
    /// Keyboard button's stays until the button, and a hardware keyboard's hold is left alone.
    public static func answer(_ report: TextFocus, keyboard: Keyboard, switchOn: Bool, sinceTap: Double?) -> Answer {
        guard switchOn, report.tap == true, let sinceTap, sinceTap >= 0, sinceTap <= tapWindow else { return .keep }
        if report.editable == true { return keyboard == .down ? .open : .keep }
        return keyboard == .byFocus ? .close : .keep
    }

    /// The device's subscription: what to send for the Mac's word (`WindowList.textFocus`), the
    /// switch and whether this connection has subscribed, and whether it is subscribed after.
    public enum Send: Equatable, Sendable { case subscribe, stop, none }

    public static func deviceSubscription(hostTextFocus: Int?, switchOn: Bool, subscribed: Bool) -> (send: Send, subscribed: Bool) {
        let takes = (hostTextFocus ?? 0) >= generation
        switch (takes && switchOn, subscribed) {
        case (true, false): return (.subscribe, true)
        case (false, true): return (takes ? .stop : .none, false)
        default: return (.none, subscribed)
        }
    }
}
