# Mischief: hide and seek with the toy mouse

The first slice of concept A in the gameplay vision (`docs/gameplay-vision.md`, PR #1010): one
partner hides the toy mouse at a spot in the room, the other hunts for it, and the cat gives the
place away a little more with every look. Behind the `mischief` flag, off by default.

## What a pair sees

- **Where it lives.** One pill, "Hide & seek", in the care sheet (tap Mochi's portrait on Home),
  shown only when the flag is `on` and the pair is paired. Home gains no control.
- **Hiding.** The sheet opens on the spots of the living room: the bed, the cat tree, the
  windowsill, the ball, the basket, the bowl, and one for each sofa, window seat, scratching post,
  cat bed and crate the pair has stood in the room. Pick one, tuck in up to 40 characters if you
  like ("you looked under the rug first, didn't you"), tap "Hide it". Hiding again replaces the
  mouse; the old one is forgotten.
- **Hunting.** When the partner has hidden one, the same sheet offers "Go look", and Home shows a
  strip over the room with one chip for each spot. A look at a spot is a try. The cat knows where
  the mouse is and answers each look with her body ([Hints](#the-cats-hints)); the strip repeats
  her answer in a line for anyone who cannot see it. "Not now" leaves the hunt; the mouse waits.
- **Found.** Looking at the right spot ends the hunt: the cat goes to it and pounces, the strip
  shows the place, the time, the tries and the line the hider tucked in. The finder earns 2 coins
  and the hider gets an Inbox row ("Mia found the mouse by the bed in 1 min 12 s").
- **Lately.** The sheet lists the last three finished hides, both ways.

## The kind rules

Nothing expires, nags or counts against anyone, and nothing here has a streak, a score to beat,
a ranking or a price.

- **A mouse waits.** There is no timer on a hunt. After three days without a find the cat "finds"
  it herself and leaves it by the door: both phones work this out from the hide's time, no event
  is sent, no coin is paid, and the hider may hide again. Nobody is named as late.
- **No push, no badge, no reminder.** The partner learns of a hide from the Inbox row and from the
  sheet. Nothing is scheduled.
- **Every hunt is winnable in a minute.** After three misses the cat stops being coy and walks to
  the mouse and sits by it.
- **13 to 17.** The only text a person writes is the 40-character line, between the two paired
  people, covered by report and block as notes are. It is trimmed and stripped of control
  characters on the phone and refused on the server. No timers, no loss copy, no ranking.
- **Where it lives in the app.** The room is never a store; the pill is in the care sheet and
  Home draws no price.

## Wire

No new server store. A hide and a find are two new journal events of the cat's journal
(`CatEvent`, [cat-state.md](cat-state.md)), so they travel, sync and reconnect like every other
entry, and the activity Inbox shows them ([activity.md](activity.md)).

```ts
CatEvent =
  | ... // Fed, Petted, Played, Watered, NoteShared, GamePlayed, Slept, Shooed
  | MouseHidden { spot: MouseSpotId, line?: MouseLine }
  | MouseFound  { hidden: IdempotencyKey, spot: MouseSpotId, tries: 1..99, seconds: 0..86400 }
```

- `MouseSpotId` is `^[a-z][A-Za-z0-9]{0,23}$`: the app's cat spot names (`home`, `tree`, `sill`,
  `ball`, `basket`, `bowl`, `sofa`, `windowSeat`, `post`, `catBed`, `crate`). The server only
  keeps the id; the phone owns the names and the places.
- `MouseLine` is trimmed, without control characters, 1 to 40 Unicode scalars.
- `hidden` is the id of the `MouseHidden` entry that was found.
- A client may send both. The room trusts them as it trusts a client's `GamePlayed`; the games
  cap is what bounds a client that sends many.
- The activity items are `MouseHidden { spot }` and `MouseFound { spot, tries, seconds }`; the
  line stays out of the Inbox. Both open the cat.
- The journal's folds (the cat's needs, her temper) read a find as play and a hide as nothing.
  The Swift mapping is `CatLife.kind(of:)`; both are pinned by the shared golden files.
- Two events for counting (`MouseHidden`, `MouseFound`, no detail), listed in
  [analytics.md](analytics.md) and [privacy.md](privacy.md): counts only, never a spot or a line.

## The economy

A find pays **2 coins** from the existing `games` source, inside its 4-a-day cap
([economy.md](economy.md)); hiding pays nothing. The cap is what the pacing test measures, so the
test passes unchanged and the budget does not move: Mischief takes a share of the same 4 coins a
day as the four games and Draw & guess. Nothing else is paid, sold or priced.

## The cat's hints

The brain and the room keep their own rules; Mischief only borrows moves they already have
(`CatDirector.mischief`). Warmth is the distance on the floor between the spot looked at and the
spot of the mouse, using the places the room reports (`RoomEvent.spotsKnown`):

| Look | Under 0.25 | 0.25 to 0.5 | 0.5 to 0.8 | 0.8 and over |
| --- | --- | --- | --- | --- |
| Warmth | hot | warm | cool | cold |
| She | walks over and sniffs | ears up, head turns toward it | an ear flicks | yawns and looks away |

After three misses every look is answered with her walking to the mouse and sitting by it. The
distances are in the room's metres (the floor is about one wide) and are a first guess to tune
on real play.

## Code

| Where | What |
| --- | --- |
| `packages/ios/features/Sources/MischiefInterface` | `MischiefSpot`, `Warmth`, `MischiefHint`, `MischiefSpotMap`, `MischiefLine`, `MischiefTime`: what the room, the Inbox and the feature share. |
| `packages/ios/features/Sources/FeatureMischief` | `MischiefLedger` (every hide and find, kept apart from the journal's three days), `MischiefHuntMachine`, `MischiefHideMachine`, `MischiefModel`. Foundation only, so it tests on the PC. |
| `apps/ios/Nooki/UI/Home/MischiefSheet.swift`, `HuntStrip.swift` | The sheet and the strip over the room. |
| `apps/ios/Nooki/Room/RoomController+Mischief.swift`, `Scene/CatDirector.swift` | The spots the room tells and the hints it plays. The room stays sealed: commands through `RoomControlling.mischief(_:)`, the spots out as `RoomEvent.spotsKnown`. |
| `apps/ios/Nooki/Model/CatLife.swift` | Hands every journal entry to the ledger (`onEntry`), returns the ids it sent under, and tells when the pair changes (`onReset`). |

State is two machines. `MischiefHuntMachine`: `idle`, `hunting(hide, looks)`, `found`; events
begin, look, leave, dismissed and hideEnded; its outputs are the cat's hint and the report for
the journal. `MischiefHideMachine`: `closed`, `choosing(spot, line)`; events opened, picked,
wrote, submitted, cancelled. Both transition tables are tested, rejected events included.

## The flag

`mischief` (kind `flag`, variants `off` and `on`, default `off`, status `draft`) in
`packages/backend/flags/src/experiments.ts` and `Experiments.mischief` in `RemoteFlags.swift`.
Nothing of it shows while it is `off`, but the app still records the partner's hides in its
ledger, so a pair that is switched on later finds what was hidden meanwhile. Start it on one pair
with an override, then by `pairedSince`. Older builds throw on a journal event they do not know:
set `minAppVersion` to the first build that has this before starting it for anyone
([experiments.md](experiments.md)).

How to judge it (from the vision's slice table): works if, in pairs that hid once, the median is
3 or more hides a week in weeks 2 to 4; kill if under 1 hide a week, or under half of the hidden
mice are found within three days.

## Not yet

- Spot what moved, and pranks (the vision's other two parts of concept A).
- A push for a hide. The vision leaves room for "your partner hid something"; the first slice
  sends none, so it cannot nag.
- The mouse itself is not drawn in the room; the find is the cat's pounce and the strip.
- The City (bedroom) has no spots: hide and seek is in the living room.
- No demo partner: the fake partner does not hide or hunt.
