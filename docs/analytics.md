# Product analytics

What the app reports about how it is used, and why. The list is closed: the app can send only the
names in `ClientEventName` (`packages/contracts/domain/src/metrics.ts`), each with at most a short
detail from a closed list or a catalogue id, and a price on a purchase. There is no free text, no
note content or drawing, no name, no device identifier beyond the session the request already
signs with, and no third-party SDK. Adding a name or a detail is a privacy decision: add it here,
to `clientEventRules`, and to `docs/privacy.md`.

## The events

The server stamps the time and adds the pair. The four events before this list, and the three the
server records itself, are in [experiments.md](experiments.md#metrics).

| Event | Detail | Value | The question it answers |
| --- | --- | --- | --- |
| `CatPetted` | none | | Do people touch the cat, and how often? |
| `CatFed` | `treat` (the day's shared treat) or `food` | | Is the daily treat a habit? Do people feed beyond it? |
| `CatPlayed` | the toy's id, when there is one | | Which games are played? |
| `CatCalled` | none | | Do people call the cat over? |
| `TrickDone` | the trick's id | | Do the learned tricks get used? |
| `CatChosen` | the cat's id from the picker | | Which cats do people choose? |
| `TemperamentShown` | the temperament's id | | Do people see their cat's temperament, and which ones come up? |
| `NoteOpened` | `widget` or `app` | | Are notes read from the widget or inside the app? (Drawing and sending a note are counted by the server as `NoteSent`.) |
| `DecoratingOpened` | none | | Do people decorate the room? |
| `RoomItemPlaced`, `RoomItemMoved`, `RoomItemPutAway` | the item's id | | Which pieces go into rooms, and which come back out? |
| `RoomCustomised` | what was changed, when that exists | | Do people change the room itself? |
| `ShopOpened` | none | | Is the shop found? |
| `ShopItemViewed` | the item's id | | Which items draw a look? |
| `ShopItemBought` | the item's id | price in stamps | What do people spend their stamps on? |
| `StreakOpened` | none | | Is the streak's flame looked at? |
| `StreakMilestoneSeen` | the milestone's id | | How far do streaks get? |
| `WidgetAdded` | the widget kind, when known | | Which widgets are added? Once per kind. |
| `WidgetButtonTapped` | `pet` or `treat` | | Are the widget's buttons used? |
| `ProfileOpened` | none | | Is the profile ("Us") visited? |
| `SignInPromptShown` | none | | How often is Sign in with Apple offered? |
| `SignInPromptAnswered` | `accepted` or `dismissed` | | And taken up? |
| `AccountDeleted` (server) | none | | How many leave? Written to Analytics Engine only: the account's own counts are deleted with it. |

The opening's cinematic is covered by `OpeningWatched` and `OpeningSkipped`.

An id is a name the app ships (letters, digits and hyphens, at most 40), never something a person
typed. The server refuses with 400 a detail on a name that takes none, a missing detail where one
is needed, a word outside a closed list, and a value anywhere but a price.

## Where it is kept

- **`pair_events`** (D1): per person, pair, name and UTC day, a count. The same table as before,
  so the funnel and the admin's per-pair views see the new names too.
- **`event_details`** (D1): per name, detail and UTC day, a count and the sum of the values. No
  person and no pair, so it can say which cats and items are chosen without saying by whom.
- **Analytics Engine** (`EVENTS`): one row per event, with the detail as `blob6` and the value as
  `double2`. See [experiments.md](experiments.md#analytics-engine).

The admin panel's "In the app" page (`GET /admin/api/app-events`) reads the two D1 tables. For
each event it shows the daily counts over the chosen range (7, 30 or 90 days), how many pairs did
it at least once in the last 7 days, and how many people did it. Under "Most chosen" it shows the
five most chosen things per name over the same range, with the stamps spent for purchases.

## On the phone

Events wait in a small file in the app group, at most 100: past that, the oldest are dropped, so a
phone that is offline for long loses its oldest events, never the app's speed. They are sent 20 to
a request when the app comes to the front and when it goes to the background. A request the server
refuses with 400 is dropped rather than retried; any other failure keeps the events for next time.
Sign-out forgets them.

Only the real client reports: `/v1/events` needs a session, so demo builds, which have no account,
send nothing.

## Switching it off

The service status (`GET /v1/status`, and in the flags answer) carries `analytics.enabled`. It is
on unless set to `false` in the admin panel's Maintenance section. Off:

- the app stops recording and drops what it was holding, within a minute (it re-reads the status
  on every foreground and every 60 s);
- the server answers `POST /v1/events` with 204 and drops the events unread, before it reads the
  session or the database, so older builds stop counting too.

Switching it on again starts counting from that moment; nothing from the off period is recovered.

## Rate limits

`POST /v1/events` keeps its limit of 60 requests a minute per caller (the `events` group in
`packages/backend/platform/src/rate-limit.ts`), and one request carries at most 20 events, so the
app's batching stays far below it.
