# App Store screenshots

Portrait slides at 1290 × 2796 (accepted in App Store Connect's 6.9" slot), built in HTML so the
captions stay editable text and every slide shares one layout. The look follows Atoll's set
(`~/Documents/Code/iOS/DynamicIsland-app/Store/screenshots`): eyebrow, two-line headline with one
hand-written word, the phone running off the bottom, white chips on a fixed grid. The type is the
app's SF Pro Rounded and the colours are `Palette.swift`'s.

- `index.html`: every slide. Open it in Chrome to review them side by side; `index.html#2` shows slide 2
  alone at its export size.
- `render.sh [n…]`: writes `../01.png`… with headless Chrome and strips the alpha channel, which App Store
  Connect rejects. `overview.jpg` is all slides in one row, for review.
- `seed.py <udid>`: writes the couple (Lily and Max, 1,022 days), coins, a 47-day streak and the lists
  into a Simulator's app group. Terminate the app first.
- `assets/`: iPhone 17 Pro Simulator captures (1206 × 2622, status bar overridden to 9:41), launched with
  `-onboardingDone YES -uitestNoHints YES -AppleLocale en_US -AppleLanguages (en)`. `cat-card.png` and `us-card.png`
  are crops of `cat.png` and `us.png`. Re-capture these whenever the UI changes.

## The set

Ordered by what matters most to a couple deciding to install: the shared home, the daily streak, Moments,
then Mochi and the everyday tools. The first three are what App Store search results show.

| # | Sells | Headline | Screen |
| --- | --- | --- | --- |
| 1 | What it is | A cozy home for *us two* | Home: the room with Mochi |
| 2 | The daily habit | Keep the *spark* alive | Us: days together, love streak (card enlarged) |
| 3 | Sharing moments | Share your *little moments* | Moments: Mochi's wall and photos |
| 4 | The pet you share | Raise a kitty *together* | Mochi's sheet |
| 5 | Movie night | Pick a movie you *both* want | To watch posters with "both" badges |
| 6 | Trips | Dream up your *next trip* | Places to go: map, flags |
| 7 | Everyday use | One list, *both* phones | Groceries by aisle |
| 8 | Make it yours | Make the room *yours* | Shop: Today |

Shot 4 shows no real films: the To watch titles are made up, and their posters in `posters/` were made with
Codex CLI in the app's felt style (`WhoKnows-card.jpg` as the reference). The app draws gradient tiles for titles
without a TMDB poster (`assets/watch-base.png`); `compose-watch.py assets/watch-base.png assets/watch.png` lays the
posters over them and copies the app's "both" pills and avatars back on top. The Moments photos in `moments/` were
made with Codex CLI too. `lists.png` had another app's "◀ Mangaki" back-link in the status bar, painted over with
the background colour.
