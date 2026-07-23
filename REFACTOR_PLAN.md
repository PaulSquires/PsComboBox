# CComboBox — design notes

Why this control is shaped the way it is. The usage documentation is in `README.md`; this file
records the decisions, so they are not re-litigated later from first principles.

Written from a pair of reference screenshots: a dark, borderless, rounded button reading
"Add to Existing Window" with a stacked up/down chevron at its right; clicking it turns the
caption and chevron blue and drops a bordered panel with two rows, the current one checkmarked.

Seeded from **CToggle** (the family's other focusable control) for the focus/tabstop machinery,
and from **CSelectBar** for the measure-the-text-to-size-the-cell layout pass.

---

## Decisions taken in the design interview

| Question | Decision | Why |
|---|---|---|
| How to build the dropdown | **Reuse `CPopupMenu` as-is**, vendored | It already solves the non-activating popup, hover-is-selection, keyboard nav, `Escape`, outside-click dismissal and checkmarks. Forking or patching it would have cost a second repo's worth of churn for a cosmetic gain. |
| What drives the autosized width | **The widest item** | The button must not change width when the selection changes — that reflows the surrounding layout and drags the dropdown anchor sideways. |
| Who applies the size | `GetIdealSize` always, plus an **opt-in** `SetAutoSize` | The family rule is that a control never sizes itself. The opt-in makes "autosize" real without making it a surprise. |
| Dropdown width / anchor | `max(button, widest item)`, left edges aligned, below | Never narrower than the thing it drops from. `CPopupMenu_ShowForRect(PM_ALIGN_BELOW)` already does the alignment, the `bottom-1` border merge, and the work-area clamp/flip. |
| Blue-while-open | An **OPEN** colour state, distinct from focus | The two are indistinguishable in the screenshot but drive different fields. Focus gets a painted ring instead. |
| Keyboard when closed | **Win32 combobox rules** | Up/Down/Home/End move the selection in place; Alt+Down / F4 / Space / Enter open. What a Windows user's fingers already expect. |
| No selection | **`-1` is legal**, with an optional placeholder | A picker that has not been answered yet is a real state. This is the deliberate departure from `CSelectBar`'s always-exactly-one contract. |
| Chevron | **Drawn geometrically** | No icon-font dependency, scales cleanly with DPI, identical on every machine. GDI+ antialiases the diagonals for free through `CBufferPaint`. |
| Text mode | **Three-state**, default `CBO_TEXT_ALWAYS` | `CBO_TEXT_WHENSELECTED` (collapse to arrows until answered) was added after the first build, on request. Made a third mode rather than the default so the placeholder feature decided in the interview keeps working; flipping the default is a one-word change. |
| Item set | **Dynamic** | A combobox is repopulated at runtime. This is the family's most repeated bug class, so the three fix-up sites are named in the code and asserted in the self-test. |
| Open on | **Mouse-DOWN**, and therefore **no capture** | Real combobox behaviour, and the family's capture test comes out negative. |

---

## Where this control departs from its siblings

Each of these is a deliberate reversal of a sibling's call, not drift.

**It is focusable.** Only `CToggle` is too; the other eleven are mouse-only. `WS_TABSTOP`, focus
tracking, a painted focus ring, and a per-message `WM_GETDLGCODE` that claims `DLGC_WANTALLKEYS`
only for the keys actually consumed. Claiming unconditionally swallows Tab and breaks the
navigation the tabstop opted into; claiming nothing lets `IsDialogMessage` route Enter to the
default button first.

**It takes no mouse capture.** `CListBox`, `CVScrollBar`, `CHScrollBar`, `CTabBar`, `CSplitter`,
`CIconPanel`, `CSelectBar` and `CToggle` all do, and all pay the full price. Here the family's
own test — "take capture only if something consumes the guaranteed down→up pairing" — comes out
negative, because the down opens the list and the popup owns the mouse from that instant. So
there is **no** `WM_CAPTURECHANGED` handler, **no** snapshot-before-release, **no**
`CancelPress`, and the message callback's result is **honoured** for `WM_LBUTTONUP`. A capture
note copied in from a sibling would be a lie.

**It has no `isPressed`.** Opening on mouse-down collapses "pressed" and "open" into one state.

**Its arrow keys clamp rather than wrap.** `CPopupMenu.NextSelectable` wraps, because menu
semantics want that. Here a wrapping `Down` at the last item would jump the user back to the
first with no list visible to explain it — so `CCOMBOBOX.NextSelectable` is a separate
implementation, and the difference is the point of it.

**`-1` is legal.** `CSelectBar` holds "exactly one panel is always current" with three rules and
`CIconPanel` treats selection as a set. Here the selection is a single optional value.

**`CS_DBLCLKS` is off**, reversing `CSelectBar`'s and `CSplitter`'s call and following
`CToggle`'s and `CIconPanel`'s: a rapid second click on this button is a legitimate
close-then-reopen, which `WM_LBUTTONDBLCLK` would swallow.

**It owns a second window.** No other control in the family creates a floating window of its
own. The dropdown is created lazily on first open and destroyed in `WM_DESTROY` — it is a
`WS_POPUP` owned by the host's top-level window, not a child of ours, so nothing else would
destroy it.

---

## What the CPopupMenu decision actually cost

Recorded plainly, because both consequences are visible to a user and neither is a bug to be
"fixed" later without reopening the decision:

1. **The checkmark sits in a 30px left gutter, with a dead 20px column reserved on the right.**
   `nCheckColWidth` and `nChevronColWidth` are fixed at `CPopupMenu`'s Create and have no
   setters. Rows therefore render as a Windows menu, not as the reference screenshot's
   right-aligned check. Reaching that look means patching CMenuBar and rippling it into tiko.

2. **No scrolling.** `CPopupMenu_Show` bottom-clamps to the work area; a list taller than the
   screen is clipped and its tail is unreachable. Good for a dozen items, not fifty.

What it bought, for comparison: the entire non-activating-popup problem — z-order, the
foreground watch, `MA_NOACTIVATE`, hover-is-selection, keyboard navigation, `Escape`,
outside-click dismissal, `CS_DROPSHADOW`, and per-row checkmarks — none of which had to be
written or debugged here.

---

## Three implementation details that were not obvious

**`SyncListWidth` is a converging measurement, not arithmetic.** `CPopupMenu_SetMinWidth` floors
the *content* width, but the window it reports adds padding and a border that `CPopupMenu`
exposes no getter for. The overhead cannot be subtracted, but it can be *measured*: floor at the
button width, measure, and the overshoot is exactly the overhead — so floor at
`buttonW - overshoot` and measure again. If the lower floor stops binding and the result comes
back narrower than the button, revert to pass 1 and be a few pixels wide rather than narrow.
At most three measures, deterministic, and asserted in both directions.

**The row id is `index + 1`, and the item's own `id` never enters the command stream.** `id 0`
is `CPopupMenu`'s separator, so a zero-based index cannot be used directly. More importantly,
routing host ids through a command channel is the exact trap recorded in `Learnings.md` under
*"Replacing TrackPopupMenu with CPopupMenu"*, where tiko's menu ids that had only ever been
`TPM_RETURNCMD` return values started re-triggering the command that opened the menu. Keeping
the id space private to the control makes that impossible by construction.

**The measuring pass runs before the zero-client bail.** `CToggle_GetIdealSize` computes from
scalars and so is trivially valid before the control is sized; this control has to *measure*
text, which needs a DC. `LayoutCombo` therefore measures and computes `nIdealW`/`nIdealH`
**first**, and only then bails if there is no client area to place rects in — the same ordering
trick `CSelectBar` uses for `nTotalWidth`. Without it, `GetIdealSize` would return 0 until the
host had already sized the control, which is a chicken-and-egg trap since sizing it is what the
host called `GetIdealSize` to do.

---

## The width rule, and its one exception

`textW` is the WIDEST item, never the selected one, so the button cannot resize as the user
picks between items. `CBO_TEXT_WHENSELECTED` is the single exception and only at the
`-1` ↔ selected boundary — a one-time unanswered-to-answered transition, which is the mode's
entire purpose.

Two implementation notes on that exception:

**The dirty-marking is driven off the resolver, not off a `-1` test.** `IsTextVisible()` is
sampled before the selection changes and compared after; `CComboBox_AfterSelectionChange` acts
only when the two differ. That keeps an ordinary pick free of any re-measure (the optimisation
`ApplyUserSel` depends on), and it stays correct for any future mode without anyone having to
remember that function exists. Three call sites cross the boundary: `SetCurSel`, the
user-selection path, and `SetItemEnabled` disabling the current item.

**`AfterSelectionChange` runs BEFORE the `SelChange` callback.** A host that re-places the
control from its handler — which is what this mode asks of a host that has not turned on
auto-size — must find `GetIdealSize` already reporting the new width.

## The one trap this design carries

`CPopupMenu_FilterMessage` dismisses the chain on an outside click and then returns **`FALSE` on
purpose**, so the click still reaches its target — tiko's behaviour, where clicking a toolbar
button while a menu is open both closes the menu and presses the button.

For a click on the combobox's **own button** that is exactly wrong: the list closes in the
filter, and the `WM_LBUTTONDOWN` that follows reopens it. The button becomes impossible to close
by clicking.

`CComboBox_FilterMessage` arms a one-shot `bSuppressNextOpen` when the click is ours and the
list is open; `WM_LBUTTONDOWN` clears it unconditionally and honours it. No timer, no
close-time heuristic, and it cannot get stuck — the first down-click that sees it clears it
whatever else happens.

It only works if the filter is in the host's pump. A host that skips the pump contract still
gets a working open/close toggle (the `WM_LBUTTONDOWN` handler falls back to closing an open
list directly) but loses keyboard navigation and outside-click dismissal.

---

## A residual, stated rather than hidden

Only one `CPopupMenu` chain may be open at a time — `gPM_OpenRoot` is module-shared — and
`PM_ShowCore` closes any other chain with `bNotify = FALSE`. So opening combobox B while
combobox A's list is up closes A's list **silently**: no `CPM_NOTIFY_CLOSED` ever reaches A.

`CComboBox_SyncOpenState` re-syncs the flag on every repaint, mouse move, focus change, hover
poll and query, so A never *stays* painted open. But the repaint path deliberately passes
`bNotify = FALSE` — running host callbacks from inside `WM_PAINT` is a rule this family does not
break — so A's `DropDown(false)` callback can be deferred to A's next non-paint touch rather
than firing at the instant B opened.

Closing that gap properly means a notification hook in `CPopupMenu` for foreign-chain closure,
i.e. patching CMenuBar. Not worth it for this.

---

## Status

- Builds clean, zero warnings.
- `CCOMBOBOX_SELFTEST=1` → **43/43 assertions passing**.
- **The interactive pass has been run and passed** (2026-07-23, by the author), including
  `CBO_TEXT_WHENSELECTED` growing from a bare chevron to the full captioned button on the
  first pick. That is what closes the control out: the assertions prove the geometry, and only
  a human can say the result reads as a combobox.
- **No host uses this control.** tiko adoption is a separate task, and until one exists the
  control has never run inside a real message pump other than the demo's.
