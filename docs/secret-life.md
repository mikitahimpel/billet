# The secret life of the cat

Small mysteries told over days in the room, where each partner finds a different half of every
clue. Concept B in [gameplay-vision.md](gameplay-vision.md) (PR #1010); this is its first slice:
one finished episode, "The fish plush is gone".

Behind the `story` experiment ([experiments.md](experiments.md)): variants `off` (default) and `on`,
in `draft`, so only a pair with an override sees it until the owner starts it.

## What a pair sees

- A case card on the corkboard (Moments > Board), one of its eight slots. It opens the case file, a
  `BilletSheet`.
- **An episode is five beats.** Each beat is a place in the room ("By the sofa", "At the window").
  A beat opens on the room day after the last one was *compared*, that is, found by both partners.
  Nothing is lost by waiting: a pair that looks once a week gets the same story more slowly, and
  nothing expires.
- **Each partner finds a different half.** Looking closer at an open beat shows this phone's half. The
  other half stays on the partner's phone until both have looked; then the beat shows both halves and
  what they make together. Which half a phone gets flips with the beat, so neither partner always
  holds the same kind of clue (`ClueSplit`).
- **Naming.** After the fifth beat each partner names one of three suspects. A choice stays hidden
  until the other is in (the room withholds it, as Who knows who does). Either answer is fine: the
  verdict line only says who got it.
- **The ending** plays as a short illustrated sheet once both names are in, and the pair keeps a
  souvenir card on the board (the shiny button). Opening the ending is recorded, which is what
  `CaseSolved` counts.
- Finished beats can be reread from the file at any time.

No coins are paid anywhere in it: the reward is the story and the souvenir (docs/economy.md has no
room for a daily coin). Nothing is sold, timed or nagged. The app sends no push for it; a partner's
progress shows when the app next reads the room (when it comes forward, and on every sync).

## Writing an episode

An episode is data: one JSON file in `packages/ios/features/Sources/StoryInterface/Resources/`, listed
in `EpisodeCatalog.files`. A test loads every listed file and `Episode.validate()` refuses a file that
would break the engine. The server knows no episode content, so a new episode needs no backend change.

| Field | Rule |
| --- | --- |
| `id`, beat ids, suspect ids, `souvenir.id` | kebab-case, at most 40 characters (the server's `StoryId`) |
| `beats` | exactly 5: `id`, `title`, `place`, two `halves` (`symbol` is an SF Symbol, `text`), `together` |
| `ask`, `suspects` | the question and exactly 3 suspects (`id`, `name`, `blurb`) |
| `culprit` | one of the suspect ids |
| `ending` | `title`, `lines`, and `verdicts` for `both`, `one` and `none` naming the culprit |
| `souvenir` | `id`, `name`, `note`, `symbol` |

Voice: short, warm, funny, English first. Write `{cat}` and `{partner}` for the names and never use a
pronoun for the cat (the pair chooses them; a test checks the shipped episode). Two halves of one beat
must each be a clue on its own and a different one. Nothing scary, nothing that blames a partner, and
nothing a 13-year-old should not read. The strings are not in a String Catalog because the app has none
yet; episodes localize when the rest of the app does, by one file per language.

## How it is built

| Piece | Where |
| --- | --- |
| Episode data, `ClueSplit`, `CaseProgress` (the fold of both partners' marks, with the pace) | `StoryInterface` (Foundation only) |
| `CaseMachine` (state enum, events, rejected events), `CaseStore`, `StoryClient` | `FeatureStory` (runs on the pc) |
| The sheet and the board cards | `apps/ios/Nooki/UI/Story` |
| The flag | `StoryVariant` in `WidgetBridge`, `Experiments.story` |

**The room is untouched.** The case is a card on the board through the existing `BoardPin` and
`RoomEvent.pinOpened`; no scene code, `RoomInput` or `RoomControlling` changed. What this slice leaves
out is the clues and the ending *in the living room* (a prop at a spot, the crow at the window as cat
steps): that is Room work, to be done with the owner of the Room files.

**Splitting the clues needs no server.** Both phones derive the same `Side` from the two account ids
(`Side(viewer:partner:)`), and a side plus the beat's index picks the half, so a half is never sent.
The server holds only each partner's *marks*: `found` (a beat id, or `ending`) and `named` (a suspect id),
with a time. The pace and the stage are folded from those on the phone.

**Server.** `GET /v1/story` and `POST /v1/story/marks` (HTTP only, no socket message or push). A mark
is idempotent per member, episode and ref; `named` is one per member and episode, first wins; the
partner's `named` marks are withheld until the caller has named. Marks hold ids and times, never text.

## Rules it keeps

Nothing expires, no nag, no guilt copy, no daily coins, no ranking between couples, nothing sold, no
text typed by the pair, so nothing to report or block. A partner who leaves keeps the story so far; a
second episode and the fallback to whole clues for a pair of one come with the next slice.

## Measuring

Events `ClueFound` (beat id) and `CaseSolved` (episode id), [analytics.md](analytics.md). From the
vision: the slice works if 60% of pairs that found beat one reach the ending; kill it if under 30% do,
or the median days per beat is over 4. The experiment's primary metric is both partners active on day
14.
