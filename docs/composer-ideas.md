# Note composer: directions

Status: proposal, no code until the owner picks. Owner: "the draw-and-write thing needs a more interesting look."

## Today

`apps/ios/Nooki/UI/NoteComposer.swift`: a flat 280 pt square, a `Write | Draw` segmented control, a row of ink
circles with prices, a row of five paper dots, and a `Pin it · +5` button. With the keyboard up the paper
colours fall under it. The lock-screen canvas (`UI/Draw/LockCanvasView.swift`) is a second, unrelated UI.

## What every direction shares

- **One canvas, no tabs.** You type and draw on the same note. A pen toggle in the tool strip switches the
  finger between "keyboard focus" and "ink". Text stays live text (`NoteText`); drawing is a transparent layer
  over it, still encoded with `InkEncoder`. A note can hold both.
- **Sheet rules kept:** ✕ glass top leading, Send top trailing, via `BilletSheet`.
- **Keyboard-aware.** The paper is pinned to the top and shrinks with the keyboard (it never goes under it);
  the tool strip rides on the keyboard as an accessory bar, so paper, ink and pen are always reachable.
- **Locked inks stay in the Store rule**: tap a locked ink, the Store opens. Price only appears on the one you
  just tapped (a small coin tag that pops, then goes), not on every ink all the time.
- **Same pieces on the lock-screen canvas** (Draw from +): the paper, the pen cup and the pen sounds are
  shared views, so both feel like one family.
- Haptics and sound: a soft tick per pen pick, a scratch-on-paper haptic while drawing, a small whoosh on send.

## Direction A: Sticky pad (lightest)

A stack of sticky notes. The paper is a sticky with a gentle curl at the bottom corner, a grain and a soft
shadow. Swiping the stack sideways peels to the next colour (the five papers), so colour is a gesture, not a
row of dots. Inks are a single strip of round pens above the keyboard.

```
 ✕                       Send
 ┌──────────────────────┐
 │▒ buy milk ♥          │ ← live text, handwriting font
 │   ~~sketch~~         │ ← ink layer
 │                  ╱╲  │   curl
 └──────────────────╱──┘
   ‹ butter  blush  sage ›     swipe or tap = next sticky
 [✎ pen] ● ● ● ○🔒 ○🔒 [↶]    ← above keyboard
 ┌──── keyboard ────────┐
```

Send: the sticky is peeled off and slaps onto the room's desk.
Cost: smallest. About 1 PR, no new art except the texture and the curl shader. Least "wow".

## Direction B: Desk with a pencil case (recommended)

The sheet is a small desk top from above. Paper sits in the middle, Mochi's paw and tail peek in from the edge.
The pens live in a **pencil case** at the bottom: owned pens poke out of the open case in their colours, locked
ones are inside, shown as dim caps with a tiny coin tag; tapping a locked one opens the Store. The paper type
(sticky / letter / polaroid) is a small stack at the top left; tapping it cycles, long press opens the
colours.

```
 ✕         desk          Send
        🐾 (Mochi peeks, paws the paper when you pause)
   ┌───────────────────┐
   │  Dear you,        │   letter paper, lined, slight rotation
   │  ~ ~ ~            │
   └───────────────────┘
  [stack ▤]   [✎ pen | T text]
  ╭──── pencil case ─────╮
  │ ┃┃┃┃┃ ┃░ ┃░ ┃░      │  owned = out, locked = capped
  ╰──────────────────────╯
 ┌──── keyboard ────────┐
```

Mochi: after ~6 s idle she sits on the corner of the paper; if the user keeps waiting she curls up on it.
Typing makes her ears turn. Send folds the note into a paper plane that she bats out of the screen, with a
whoosh and a haptic. Stickers and stamps (owned from the Shop) sit in a drawer behind a `+` in the pen strip.

Cost: medium-large. Needs a Mochi pose or two (paw, sitting) from the pet package, the plane fold animation,
and the case view. Biggest fit with the app's character.

## Direction C: Polaroid and letter, no pet

Skip Mochi on the desk. The note is a paper you choose from three shapes: square sticky, lined letter,
polaroid (draw on the photo area, write in the caption). The ink picker is a **pen cup** (a mug seen from the
side with pens sticking up, owned ones tall, locked ones short with a coin tag). A handwriting-font option sits
in the tool strip. Delivery is the paper folding into a plane; no Mochi.

```
 ✕                       Send
   ┌───────────┐  ┌────────┐ ┌───────┐
   │ sticky    │  │ letter │ │┌─────┐│
   └───────────┘  │ ─────  │ ││draw ││
                  └────────┘ │└─────┘│ polaroid
                             │ cap.  │
                             └───────┘
        ╭ pen cup ╮   [Aa ▾ font]
```

Cost: medium. Safer on art (no new pet poses), less personality than B.

## Comparison

| | A Sticky pad | B Desk + pencil case | C Papers + pen cup |
| --- | --- | --- | --- |
| One canvas, no tabs | yes | yes | yes |
| Real-feeling paper | curl + grain | letter, sticky, polaroid | sticky, letter, polaroid |
| Pens | strip | pencil case | pen cup |
| Mochi | no | yes, plus send moment | no |
| Send moment | peel and slap | paper plane, Mochi bats it | paper plane |
| Effort | small | large | medium |

## Suggested order inside any choice

1. One canvas (text + ink layer), keyboard-aware layout, the pen toggle. Removes the segmented control.
2. Paper (grain, shadow, curl) and the paper choice.
3. Pens: strip, case or cup, with the Store rule.
4. Send moment, sound, haptics.
5. Shared pieces on the lock-screen canvas.
6. Stickers, stamps, handwriting font (later, they need Shop items).

## Open questions for the owner

- A, B or C? Or B without Mochi's idle behaviour first?
- Should one note carry both text and drawing (needs `NoteText` plus an ink layer on the wire), or must a
  note stay one or the other as today?
- Are stickers and stamps in this PR, or a follow-up?
