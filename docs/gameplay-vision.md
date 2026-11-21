# Gameplay vision

Status: **working notes** (stage 1 of 5). The final proposal replaces these notes.

## Working notes

### Stage 1: audit (in progress)

Real usage numbers: **not read yet**. `scripts/admin-read.sh` fails before any request: Proton Pass
has no item `cloudflare-agents` in vault `Ourio` (`.env.pass.agents`). Reported to the manager.
Everything below is from the code and docs only.

**Loops found so far**

| Loop | Rhythm | Needs both? | Evidence |
| --- | --- | --- | --- |
| Care for the cat (pet, feed, water, laser, brush) | several times a day; needs fall with time constants of 6 h (full), 14 h (loved), 10 h (playful) | no | `LifeConfig.swift`, `MiniGame.swift` |
| Note, drawing, photo to the partner's widget | free | one sends, one receives | `docs/widgets.md`, `NoteSent` |
| Love streak | daily, lights when both acted | yes | `docs/love-streak.md` |
| Who knows who | daily, 5 questions, hidden until both answer | yes | `docs/who-knows-who.md`; deck is 150 questions = 30 days |
| Draw and guess | free, async, one open riddle each | yes | `docs/draw-guess.md` |
| Daily gift | daily, 1 or 2 coins | no | `docs/economy.md` |
| Shop: deals daily, featured set weekly (3 sets in turn) | daily and weekly | no | `shop.ts` `featuredSets` |
| Decorate the room | free | no | `RoomItem*` events |
| Pick tonight, wishlists, lists, calendar, places | occasional utility | some | `FeatureUs` |

**First observations**

- The earn side is capped at about 13 coins a day and the whole room catalogue is 12 pieces, 2 of
  them free (`shop.ts`): 2,175 coins for the other ten, 510 for the six paid inks, 375 for stamps
  and seals. About 3,060 coins, or roughly 8 months at the cap. So the long-term goal is a slow
  cosmetic checklist, and the economy doc says outright that "nothing is worth playing for the
  coins". Coins cannot carry retention, and are not meant to.
- The care level (`CatCare.fill`) is a bar in a per-phone wallet file: 3% per pet, no cap, nothing
  unlocks at any level. It is a number without a meaning.
- The four mini-games are solo and scored 0 to 100 with "no losing" (`GameResult`). To check:
  whether anything changes between the first play and the twentieth.
- The cat's inner life is rich (statechart brain, temperament, upbringing, memory of favourite
  spots, a diary of her day: `Pet/Brain`) but most of it is invisible to the pair. To check: what
  ships outside Labs.
- Not measurable today: a mini-game by id and score from the client beyond `CatPlayed`, Who knows
  who and draw-guess rounds (no client events; the room has them), moments, moods, reactions,
  session length, both partners present at once.
