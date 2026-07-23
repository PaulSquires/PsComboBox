# CComboBox

A reusable owner-drawn **dropdown selector** for FreeBASIC + Win32, in the AfxNova control
family: a button showing the current choice with a stacked up/down chevron on its right,
which drops a list of alternatives where exactly one — the current one — is checkmarked.

Single selection only. No text entry, no multi-select, no icons.

It is the thirteenth control in the family (`CListBox`, `CVScrollBar`, `CHScrollBar`,
`CStatusBar`, `CTabBar`, `CTextBox`, `CColumnHeader`, `CMenuBar`, `CPopupMenu`, `CSplitter`,
`CIconPanel`, `CSelectBar`, `CToggle`) and follows the same shape: one real `HWND`, all state
in a `TYPE` in the `CWindow` UserData area, host-supplied font and colours, host callbacks,
one `CBufferPaint` per `WM_PAINT`, lazy layout, no host globals.

---

## Files

| File | Role |
|---|---|
| `CComboBox.bi` | Types, colours, callbacks, the public API, the geometry contract |
| `CComboBox.inc` | Window class, layout, painter, WndProc, dropdown integration, self-test |
| `CBufferPaint.bi` / `.inc` | Vendored from [CBufferPaint](https://github.com/PaulSquires/CBufferPaint) — byte-identical |
| `CPopupMenu.bi` / `.inc` | Vendored from [CMenuBar](https://github.com/PaulSquires/CMenuBar) — byte-identical |
| `main.bas`, `frmMain.bi`, `frmMain.inc` | Demo harness |

`CComboBox.bi` includes **both** dependencies itself, so there is no include-order trap: two
`#include once` lines and the type name are the whole adoption cost. A host that already
vendors `CPopupMenu.bi` gets one copy — `#include once` dedupes by resolved path, which is how
tiko already shares a single copy between `CTextBox` and `CMenuBar`.

Build the demo:

```bash
fbc64.exe -i "C:\dev" main.bas
```

---

## Quick start

```basic
ghCombo = CComboBox_Create( hWndParent, IDC_MYCOMBO )
CComboBox_SetFont( ghCombo, ghFont(GUIFONT_10) )        ' borrowed; you keep ownership
CComboBox_SetSelChangeCallback( ghCombo, @MySelChange )

CComboBox_AddItem( ghCombo, "Add to Existing Window", 1 )
CComboBox_AddItem( ghCombo, "Open a New Window", 2 )
CComboBox_SetCurSel( ghCombo, 0 )                      ' SILENT -- fires no callback

dim as long iw, ih
CComboBox_GetIdealSize( ghCombo, iw, ih )              ' valid before it has ever been sized
SetWindowPos( ghCombo, 0, x, y, iw, ih, SWP_NOZORDER )
ShowWindow( ghCombo, SW_SHOW )
```

…and **the pump contract, which is not optional**:

```basic
do while GetMessage( @uMsg, null, 0, 0 )
    if CComboBox_FilterMessage( ghCombo, @uMsg ) then continue do
    if IsDialogMessage( hMain, @uMsg ) then continue do
    TranslateMessage @uMsg : DispatchMessage @uMsg
loop
```

Call it once per combobox, **before** `IsDialogMessage`. Each call returns immediately when
that control's list is closed, so a form with a dozen of them costs nothing.

Without it the list opens and paints but cannot be keyboard-driven, never dismisses on an
outside click, and clicking the button while it is open reopens it instead of closing it.

---

## The layout

```
ringPad  = nFocusGap + nFocusThick        reserved ALWAYS, focused or not
textW    = MAX over items of the measured caption width   (0 in arrow-only mode)
contentH = max( textH, nChevronHeight )

idealW   = 2*ringPad + nPadLeft + [textW + nTextGap] + nChevronWidth + nPadRight
idealH   = 2*ringPad + nPadTop  + contentH + nPadBottom

rcButton  = rcClient deflated by ringPad
rcChevron = right-aligned inside rcButton at nPadRight, v-centred
rcText    = rcButton.left+nPadLeft .. rcChevron.left-nTextGap, v-centred   (empty if arrow-only)
rcVisual  = rcButton inflated by ringPad   ( = rcClient when sized ideally )
```

**The width comes from the widest item, never the selected one.** A combobox that grew and
shrank as the user picked would reflow whatever surrounds it and drag its own dropdown anchor
sideways. The placeholder is deliberately not measured either, for the same reason — the button
is exactly as wide before the first pick as after it.

`GetIdealSize` is valid **before the control has ever been sized**, because the measuring pass
runs ahead of the zero-client bail. That matters: a host calls it to decide how big to make the
control in the first place.

All setters take **raw pixels** — the caller DPI-scales. Only the Create-time defaults are
scaled for you. `nBorderThick` and `nFocusThick` are not scaled anywhere: a hairline stays a
hairline. `nChevronThick` is the one exception, because `CBufferPaint.PaintLine` scales the pen
it is handed — deliberate, since a glyph's stroke should grow with the glyph.

`SetCornerCurvature` takes an ellipse **diameter**, not a radius: `CBufferPaint` keeps GDI's
vocabulary and halves it internally. 12 draws a 6px radius; 0 gives square corners.

### Text modes

`CComboBox_SetTextMode` picks one of three:

| Mode | Button shows | Width |
|---|---|---|
| `CBO_TEXT_ALWAYS` *(default)* | always the caption (or the placeholder, or nothing) | fixed, from the widest item |
| `CBO_TEXT_NEVER` | only the chevron, permanently | fixed, padding + chevron |
| `CBO_TEXT_WHENSELECTED` | only the chevron while nothing is selected; the caption once something is | **moves once**, on the `-1` ↔ selected boundary |

`CBO_TEXT_WHENSELECTED` is the "don't answer for me" shape: a combobox that starts as a bare
pair of arrows and becomes an ordinary captioned combobox the moment the user picks something.

**It is the only mode whose width moves, and that is not a contradiction of the widest-item
rule** — that rule exists so the button doesn't resize as the user picks *different* items, and
it still holds: every selected state has the same width. What changes is the one-time
transition from unanswered to answered, which is the point of the mode.

So in this mode, **either turn on `SetAutoSize(true)` or re-place the control from your
`SelChange` handler.** Left at a fixed size the control keeps its collapsed width and the
caption arrives ellipsized into a chevron-sized box — the self-test asserts exactly that,
because it's a real cost and not a bug. `SelChange` fires *after* the new ideal width is
computed, so a handler that calls `GetIdealSize` sees the new value.

A **placeholder can never appear** in this mode: the only state that would show one is the
collapsed, caption-less state. Setting both isn't an error, just inert.

`SetShowText(bool)` is the two-state convenience (`TRUE` → `ALWAYS`, `FALSE` → `NEVER`); it
cannot reach `WHENSELECTED`. `GetShowText` answers **"is a caption drawn right now"**, which
for `WHENSELECTED` depends on the selection — deliberately not an echo of the mode.

Paint callbacks get `isTextVisible` in `CCOMBOBOX_PAINTINFO` so they never have to re-derive
it; when it's false, `rcText` is empty.

### Auto-size

`CComboBox_SetAutoSize(true)` makes the control `SetWindowPos` **itself** (preserving its
top-left) whenever something that changes the ideal width changes — items, font, show-text,
padding, chevron size, focus ring. It is **off by default**, which is the strict family rule:
the host measures with `GetIdealSize` and sizes.

The control owns its size in that mode; the host still owns its position. A right-aligned
combobox therefore still needs a re-place after items change. The demo does exactly this and
prints as it goes.

---

## The dropdown is a CPopupMenu, used as-is

That buys the whole floating-window problem already solved: a `WS_POPUP` that never takes
activation, hover-is-selection, keyboard navigation, `Escape`, outside-click dismissal, and a
checkmark per row.

**Two consequences follow, and neither is a bug:**

1. **The checkmark sits in a left gutter.** `CPopupMenu`'s `nCheckColWidth` (30) and
   `nChevronColWidth` (20) are fixed at its Create with no setters, so rows render as a Windows
   menu — check on the left, and a reserved-but-unused column on the right. A right-aligned
   check would mean patching CMenuBar, which was ruled out.
2. **There is no scrolling.** `CPopupMenu` bottom-clamps to the work area; a list taller than
   the screen is **clipped and its tail is unreachable**. This control is built for about a
   dozen items, not fifty. A long list needs a different control.

Rows are **rebuilt from the model on every open**, so the two cannot drift. The row id is
`(model index + 1)` — not the item's own `id`, which stays a free-form host payload and never
enters the command stream. That is the id-collision trap recorded in `Learnings.md` under
*"Replacing TrackPopupMenu with CPopupMenu"*, avoided by construction.

The dropdown's appearance is reachable through `CComboBox_GetListHandle()`, so every
`CPopupMenu_Set*` appearance call is available. **That handle is for appearance only** —
adding, deleting or re-ordering rows through it desyncs them from the model and they vanish at
the next open.

Its colours are **derived from `CCOMBOBOX_COLORS`** automatically, so theming the button themes
the list. Calling `CComboBox_SetListColors` claims them permanently and the derivation stands
down — an explicit choice is never overwritten.

---

## Colours

Four moods: `idle`, `hot`, `open`, `disabled`, each with a back, fore, border and chevron
colour, plus `ForeColorPlaceholder` and `FocusRingColor`.

There is deliberately **no pressed state**: the list opens on mouse-*down*, so "pressed" and
"open" are the same instant. Precedence is `disabled > open > hot > idle` — **open beats hot**,
because while the list is up the cursor is normally over the *list*, and the button must stay
lit.

Out of the box the button reads **borderless** (every `BorderColorXxx` defaults equal to the
matching `BackColorXxx`) and the chevron **follows the caption** (every `ChevronColorXxx`
defaults equal to the matching `ForeColorXxx`) — which is what the reference design shows:
caption and chevron turn blue together while the list is open, and the fill does not change.
Set the fields to break either coupling.

Read-modify-write is `GetColors`, assign, `SetColors`.

---

## Focus and keyboard

`WS_TABSTOP`, real focus tracking, a painted focus ring. `CToggle`, `CNumericUpDown` and
`CButton` are the other focusable controls in the family. Tab *navigation* needs
`IsDialogMessage` in the host pump; mouse and — once the control has focus — keyboard both work
without it.

**Give one of your controls the focus at startup.** `IsDialogMessage` only acts when the focused
window is a *descendant* of the window you pass it, and when your form opens the focus is on the
form itself — so the **first Tab does nothing**, which reads exactly like broken tabstops. A real
dialog does this in `WM_INITDIALOG`; an ordinary `CWindow` host calls `SetFocus( hFirstControl )`
after `ShowWindow`.

> **Fixed 2026-07-23 — Tab navigation never actually reached a combobox before that.**
> `CWindow.Create` defaults its `dwExStyle` parameter to
> `WS_EX_CONTROLPARENT OR WS_EX_WINDOWEDGE`, and `CComboBox_Create` passed only `dwStyle` — so
> the control declared itself a *container*, the dialog manager descended into it looking for
> tabstops, found no children, and skipped it. **This repo's own demo hid it**: the demo also
> hosts three plain Win32 `BUTTON`s, so Tab moved between *those* and the interactive pass saw
> focus moving and concluded navigation worked. Now passed explicitly as `0`, asserted three ways
> in the self-test, and confirmed by an interactive pass that specifically watched Tab land on a
> combobox rather than merely move. Note this fix is **wrong** for
> `CListBox`/`CTextBox`/`CNumericUpDown`/`CScrollPanel`, which genuinely need the flag; see
> `C:\dev\Learnings.md`.

`WM_GETDLGCODE` claims `DLGC_WANTALLKEYS` **per-message and only for the keys the control
consumes**. Claiming unconditionally would swallow Tab and break the navigation the tabstop
opted into; claiming nothing would let `IsDialogMessage` route Enter to the dialog's default
button first.

With the list **closed** — Win32 combobox rules:

| Key | Effect |
|---|---|
| `Down` / `Up` | move the selection in place, **without** opening. Fires `SelChange`. |
| `Home` / `End` | first / last **enabled** item. Fires `SelChange`. |
| `Alt+Down`, `Alt+Up`, `F4`, `Space`, `Enter` | open the list |

Arrow movement **clamps, it does not wrap** — a wrapping `Down` at the last item would jump the
user back to the first with no list visible to explain it. Disabled items are skipped.

With the list **open** the keyboard belongs to `CPopupMenu`'s filter.

---

## Callbacks

| Callback | Fires when |
|---|---|
| `CBO_PaintCallbackSub` | draw the whole **button** instead of the built-in painter |
| `CBO_MessageCallbackFunc` | observe mouse / focus / key messages; `TRUE` suppresses default handling |
| `CBO_SelChangeCallbackSub` | the **user** changed the selection — programmatic `SetCurSel` is silent |
| `CBO_DropDownCallbackSub` | the list opened or closed |

**Programmatic setters are silent; only the user notifies.** `SetCurSel` fires nothing (Win32's
`CB_SETCURSEL` / `CBN_SELCHANGE` split), which is also what makes it safe to call from inside
your own handler.

`DropDownCallback` is the exception, and on purpose: it fires for programmatic opens too,
because it reports a *window-state transition* rather than a value change — and its opening
edge, which runs **before a single row is built**, is the just-in-time hook for rebuilding a
dynamic list with `Clear` + `AddItem`.

The message callback's result is **ignored for `WM_SETFOCUS` / `WM_KILLFOCUS`**: focus is a fact
the system reports, not an action to veto.

### One trap when writing a paint callback

Draw the focus ring with **`PaintRoundOutline`**, never `PaintBorderRect`. The latter goes
through `PaintRectFactory`, which **always fills the rect with `_backcolor`** before stroking
it — so used for a ring it floods `rcVisual` with whatever colour you last set and wipes the
chrome, the caption and the chevron you just drew, leaving a solid block. `PaintRoundOutline`
exists for exactly this case ("stroke over already-painted pixels without filling"); pass
curvature 0 for a square ring. The built-in painter uses it, and the demo's custom painter
carries a comment saying why.

The same shape bites anything drawn *over* existing pixels, not just the ring.

---

## Two things worth knowing

**1. The reopen trap, and how it is handled.** `CPopupMenu`'s filter dismisses on an outside
click and then returns `FALSE` *on purpose*, so the click still reaches its target. For a click
on the combobox's own button that is exactly wrong — the list would close and the following
`WM_LBUTTONDOWN` would immediately reopen it, making the button impossible to close by clicking.
`CComboBox_FilterMessage` notices that case and arms a one-shot flag the next down-click
consumes. Deterministic; no timer, no close-time heuristic. **This only works if the filter is
in your pump.**

**2. No mouse capture is taken, anywhere.** The family's test is "take capture only if something
consumes the guaranteed `WM_LBUTTONDOWN` → `WM_LBUTTONUP` pairing", and here it comes out
negative: the down opens the list, and from that instant the popup owns the interaction. So
there is no `WM_CAPTURECHANGED` handler, no snapshot-before-release dance, no `CancelPress`, and
**no "callback result ignored for `WM_LBUTTONUP`" caution** — a note about capture copied in
from a sibling would be a lie here.

`CS_DBLCLKS` is **off**, which is `CToggle`'s and `CIconPanel`'s call rather than
`CSelectBar`'s: a rapid second click on this button is a legitimate close-then-reopen, and
`WM_LBUTTONDBLCLK` would silently swallow it.

Only one popup chain may be open at a time (`CPopupMenu` shares it), and opening combobox B
closes combobox A's list **silently** — no notification reaches A. `CComboBox` re-syncs its own
flag whenever it is touched; the residual is that A's `DropDown(false)` callback may be deferred
to A's next repaint-plus-interaction rather than firing at the instant B opened.

---

## Verification

Build clean, zero warnings. Then:

```bash
CCOMBOBOX_SELFTEST=1 main.exe
```

43 geometry assertions covering: the ideal size before the control is ever sized and the parts
it is built from; the width being independent of the selection and of the placeholder; the
widest-item re-measure across insert and delete; `nCurSel` fix-up at all three mutation sites
plus `Clear`; disabled-item refusal and arrow clamping; the rect partition and the reserved ring
band; arrow-only mode; all three text modes including `WHENSELECTED`'s collapse, its expansion,
its stability between selections, its collapse-on-disable, the caption having nowhere to go at
the old window size, and auto-size applying the boundary change itself; the popup id ↔ index
round trip and the single checkmark; `SyncListWidth` convergence in both directions; and the
reopen guard's one-shot contract.

**What the assertions cannot cover, and is left to the interactive pass:** pixel appearance of
the chrome and chevron, hover, the open/close click cycle (including clicking the button while
the list is up), Tab navigation, outside-click dismissal, and the dropdown's own rendering.

**That pass has been run and passed** (2026-07-23, by the author), including
`CBO_TEXT_WHENSELECTED` growing from a bare chevron to the full captioned button on the first
pick. It matters more here than the assertion count does: the geometry is provable, but whether
the thing *looks* like a combobox is not, and a human is the only check on it.

---

## Not implemented, deliberately

- **No tooltips.** No tooltip window is created and there is no `CBO_TooltipCallback` (by
  request). A host that wants a tip can add its own tool over the control's `HWND`.
- **No list scrolling** — see the CPopupMenu section.
- **No editable / text-entry mode.** This is a picker, not a `CBS_DROPDOWN`.
- **No multi-select**, no tri-state, no per-item icons or images.
- **No typeahead** while the list is closed.
- **No animation.**
- **No `CComboBox_HitTest`** — the whole client is the hit area, so it could only ever return
  what the caller already knows.

**No host uses this control yet.** tiko adoption is a separate task.
