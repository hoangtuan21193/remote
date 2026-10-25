# The keyboard at a text field, the picture above it, and the Mac keys bar

Fork change, 2026-10-25, branch `slim-claude-md`. Asked (in Vietnamese): the keyboard opens by itself
when a tap lands in a text field on the Mac; the picture slides up so the keyboard does not cover it;
over the keyboard, a bar of the keys iOS lacks (command, the arrows, shift, control…), after Jump
Desktop. The decisions were settled on a planboard (`.planboard/keyboard-auto/`, PLAN.md and
DECISIONS.md there), one round.

## Decisions

| | Question | Settled |
|---|---|---|
| D1 | When does the keyboard open by itself? | Only right after this device's click lands in a text field. A focus the Mac moves by itself (⌘L, a new window) opens nothing. |
| D2 | Does a tap elsewhere close it? | Yes, when a text field opened it; one opened with the button closes only with the button. |
| D3 | Web and Electron apps? | Ask the frontmost app for its accessibility tree (`AXManualAccessibility`), which Electron apps (Slack, VS Code, Discord) honour; not `AXEnhancedUserInterface`, which breaks window animations. Chrome's web pages: untested. |
| D4 | What does the picture do? | Slides up just enough to keep the caret 12 pt above the bar, keeping its size; it does not move when the caret is clear. |
| D5 | Follow the caret while typing? | Yes: one step when a new line goes under the keyboard; back down when the keyboard goes. |
| D6 | Which keys on the bar? | One row that scrolls sideways (the user's pick, as Jump Desktop): esc, tab, ctrl, opt, cmd, shift, ← ↑ ↓ →, F1–F12, home, end, pg up, pg dn, forward delete; the hide button fixed at the right edge. |
| D7 | How long does a modifier hold? | As iOS's shift: one tap for the next key, two taps (within 0.35 s) lock it until tapped again; the portrait key row the same. |
| D8 | An iPhone held upright, which has its own key row? | The bar as everywhere; the key row goes while the person's keyboard is up. |
| A1 | A switch | This device's Open Keyboard Automatically (This iPhone/iPad in Settings), on by default, shown while the Mac reports its focus. |
| A2 | An older Mac | No kind 33, no automatic keyboard and no caret; the picture still slides for the last tap; the button as before. Nothing shown. |
| A3–A4 | Permissions, passwords | Sill.app's Accessibility permission, already granted for input; never the field's text, only whether it takes text and where the caret is. |

## Wire (additive)

Kind 33 `textFocus`, both ways, JSON `TextFocus {editable, caret, tap, stop}` (TextFocus.swift), and
`WindowList.textFocus: Int?` (1). A device sends kind 33 only to a host that says 1 or more; any
kind 33 subscribes, `{"stop":true}` ends it. The host sends a report only to a subscriber: after its
click (`tap: true`, to it alone) and while the caret moves in a field (to every subscriber). `caret`
is a fraction of the streamed frame, as input positions are. Older peers skip the kind and the field.

## Host

`HostTextFocus` (main actor; Accessibility read on a queue of its own with a 0.25 s messaging
timeout): after a subscriber's left button comes up, it looks at the system-wide focused element at
0.15 s and 0.45 s (`TextFocusPolicy.hostLooks`); the first look that finds a text field, or else the
last, goes out. A text field is a role in `editableRoles` (AXTextField, AXTextArea, AXComboBox,
AXSearchField) or any element with a settable value and a selected text range. The caret is the
bounds of the selected range (for an insertion point, a zero-length range, else the character before
it), else the element's frame. While the focus is in a field, a look every 0.25 s sends what moved by
more than 0.2 % of the frame. One line per subscription and stop; nothing per report. TEST ONLY, a
synthetic host: `SILL_TEST_TEXT_FOCUS=field|none|x,y,w,h|/path` stands in for Accessibility.

## Device

- `StreamClient+TextFocus`: the subscription, the last report (`textFocusEvent`, `textCaret`), the
  last click's time.
- StreamScreen: on a report, `TextFocusPolicy.answer` (only a report that answers this device's click
  of at most 1.5 s ago, the switch on; nothing while the tour, the pairing overlay or Settings is
  open) opens the keyboard (`InputOverlayProxy.openForFocus`, a keyboard the proxy marks as the
  focus's) or closes one the focus opened.
- `KeyboardAccessoryBar`: the input view's `inputAccessoryView`, none for a hardware keyboard's hold.
  Arrows and forward delete repeat when held (0.4 s, then ten a second).
- `ModifierLatch` (KeyChords.swift): held and locked modifiers, shared by the key row and the bar.
- `KeyboardLift`: the lift from the caret (the Mac's, else the last tap as a 24 pt line), the docked
  keyboard's top measured against the panel's top in the window (not the input view's own place,
  which moves through a slide: the first try measured that and overshot to 370 pt), and the view's
  height. The landscape stream panel and the upright picture pane each apply it as an offset of the
  video and the input view together, inside their clip.

## Checks

`textfocus` (kind 33, the list's field, the roles, the looks, the caret's fractions, what goes out,
the device's answer and subscription, a model of 2,000 runs; 31 mutants), `keyboard-lift` (the lift,
its bounds, the docked keyboard, a model of 5,000; 14 mutants), `key-strokes` gains the latch (14
cases, 8 mutants), `compatibility`, `protocol`, `pointer-control` and `clipboard` know kind 33.

## Results

- Wire, with `Scripts/sillclient.py --textfocus` against a synthetic host: a tap outside a field gives
  `editable=0 tap=1` at 0.45 s; inside one, `editable=1 tap=1` at 0.15 s; a caret moving gives
  `tap=0` reports; leaving the field gives `editable=0`.
- iPhone 16 simulator (iOS 18.6), against the synthetic host: a tap on a field opens the keyboard
  with the bar, the upright key row goes; a tap elsewhere closes it; on its side the picture slides up
  196 pt for a caret at 85 % down and steps to 217 pt when it moves to 93 %; cmd lights for one key and
  esc spends it; the hide button closes the keyboard and the key row comes back; Settings shows the
  switch with its footnote.

## Untested

- A real Mac's Accessibility: TextEdit, Notes, Safari, Terminal, an Electron app, Chrome's pages; the
  caret's bounds in each; a password field.
- A real iPhone, iPad and the iPhone Duo; iPadOS's floating and split keyboards; a hardware keyboard
  attached while the bar shows; VoiceOver on the bar.
- Taps on the simulator while `-SillOrientation landscape` forces the scene sideways do not land
  (known); on its side the lift was driven by `-SillInputScript`, and the hide button there untried.
