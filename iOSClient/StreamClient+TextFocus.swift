import Foundation
import StreamProtocol

/// One report from the Mac (kind 33), numbered so two of the same in a row are two events.
struct TextFocusEvent: Equatable {
    let report: TextFocus
    let number: Int
}

// The Mac's text focus, this device's side (kind 33; docs/keyboard-auto-plan.md). TextFocusPolicy has
// the rules; this keeps the subscription and the last report, and when this device last clicked.
//
// - The subscription: an empty kind 33 once the Mac's list says `textFocus` and the switch is on, again
//   on a move's new connection; `stop` when the switch goes off.
// - A report: published (`textFocusEvent`) for the stream screen, which opens or closes the keyboard
//   by TextFocusPolicy.answer, and its caret (`textCaret`) for the input view, which keeps it above the
//   keyboard (KeyboardLift).
//
// Everything here is main thread.
extension StreamClient {
    /// This device's switch, Open Keyboard Automatically (the Settings panel's This iPad group): on
    /// unless turned off. The device's own preference; read at each decision.
    static let openKeyboardKey = "Sill.openKeyboardAutomatically"
    static var openKeyboardOn: Bool {
        // `bool(forKey:)`, not `as? Bool`: a launch argument's "0" is a string, which it reads as
        // @AppStorage does, so the switch and the panel always agree.
        let defaults = UserDefaults.standard
        return defaults.object(forKey: openKeyboardKey) == nil || defaults.bool(forKey: openKeyboardKey)
    }

    /// Each window list's `textFocus`: the subscription follows it.
    func hostTextFocusChanged(_ value: Int?) {
        if hostTextFocus != value { hostTextFocus = value }
        updateTextFocusSubscription()
    }

    func updateTextFocusSubscription() {
        let step = TextFocusPolicy.deviceSubscription(hostTextFocus: hostTextFocus, switchOn: Self.openKeyboardOn,
                                                      subscribed: textFocusSubscribed)
        textFocusSubscribed = step.subscribed
        switch step.send {
        case .subscribe:
            send(.textFocus, payload: TextFocusPolicy.subscription)
            #if DEBUG
            print("text focus: subscribed")
            #endif
        case .stop:
            send(.textFocus, payload: TextFocusPolicy.stopping)
            textCaret = nil
            #if DEBUG
            print("text focus: stopped")
            #endif
        case .none:
            break
        }
    }

    /// The Settings group's switch moved.
    func textFocusSwitchChanged() { updateTextFocusSubscription() }

    /// A move handed the session to its new connection: the Mac keeps subscriptions per connection.
    func textFocusMoved() {
        textFocusSubscribed = false
        updateTextFocusSubscription()
    }

    /// The session ended.
    func resetTextFocus() {
        hostTextFocus = nil
        textFocusSubscribed = false
        textCaret = nil
        lastClickAt = nil
    }

    /// A kind 33 from the current connection.
    func receiveTextFocus(_ data: Data) {
        guard textFocusSubscribed, let report = Wire.decode(TextFocus.self, from: data) else { return }
        textCaret = report.editable == true ? report.caret : nil
        textFocusEvent = TextFocusEvent(report: report, number: (textFocusEvent?.number ?? 0) + 1)
        #if DEBUG
        let caret = report.caret.map { String(format: "%.3f,%.3f %.3f×%.3f", $0.x, $0.y, $0.w, $0.h) } ?? "none"
        print("text focus: editable=\(report.editable == true) tap=\(report.tap == true) caret=\(caret)")
        #endif
    }

    /// Seconds since this device's last click (its left button's up), nil before any.
    var sinceLastClick: Double? { lastClickAt.map { ProcessInfo.processInfo.systemUptime - $0 } }
}
