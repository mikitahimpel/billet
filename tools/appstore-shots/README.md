# App Store screenshots

Turns raw Simulator screens of the current app into the framed App Store panels: a gradient background
(Dusk palette), a tag line, a headline with one handwritten accent word, an iPhone body and 1 to 3 caption
chips. Copy and chip positions live in `manifest/<locale>.json`.

```sh
tools/appstore-shots/capture.sh                 # Mac: build, boot a shut-down Simulator, 8 raw PNGs
pnpm appstore:shots                             # panels + contact sheet, en, both default sizes
pnpm appstore:shots --locale ru                 # ru manifest (a draft; the raw screens are English UI)
pnpm appstore:shots --sizes 6.9-1320x2868       # one size; --panel room to re-render one panel
pnpm appstore:shots --check                     # output sizes, no alpha, tokens vs Palette.swift
pnpm appstore:test                              # unit tests
```

Defaults: raw screens in `~/Developer/billet-shots/appstore/raw` (`--raw`), output in
`~/Developer/billet-shots/appstore/<locale>/<size>/NN-<panel>.png` plus `contact-sheet.png` (`--out`).
Nothing is written into the repository.

## Requirements

Node 24 (the scripts run as TypeScript, no install) and a Chrome or Chromium: found on the Mac, in
`/usr/bin`, or in Playwright's cache on the pc; set `CHROME` to override. There are no dependencies.
Output is deterministic for the same Chrome and fonts. Emoji glyphs follow the machine (see NOTICE.md).

## Sizes

From App Store Connect's screenshot specifications
(https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/): iPhone 6.9 inch
1320x2868, 1290x2796 (1260x2736 also accepted); 6.5 inch 1284x2778, 1242x2688; JPEG or PNG, no alpha. One of
6.9 or 6.5 inch is required, the other is scaled by Apple. The default writes 1320x2868 and 1284x2778; the
files are flattened to RGB. The layout is drawn at 1320 wide and scaled by width. iPad is off in the app, so
there is no iPad size.

## Manifest

`headline` marks the accent word with braces: `"Keep the {spark} going"`. A chip's `x` and `y` are the left
and top in percent of the panel, `rotate` is in degrees. `raw` is the file stem in the raw folder; `bg` is
`light` or `dark`. A new locale is a new file with the same panel ids; `--check` and every run validate it.

## Capture

`capture.sh` builds the Debug app, takes the build lock (`lockq-wait`), boots the Simulator named by
`SIM_NAME` (default `ui-fixes2-pm`, an iPhone 17 Pro Max; it must be shut down, never a booted or the golden
one), sets the status bar to 9:41, dark mode and the Dusk look, and launches the app with `-landingDemo YES`
(Alex and Sam, 64 coins) per panel: `-landingGo pet|groceries|list|places|us|shop`, `-shotMoments photos`.
It shuts the Simulator down and releases the lock when done. `SETTLE` (seconds, default 14) is the wait
before each screenshot; the room needs it. A new screen is a new `-landingGo` case in `HomeState` and demo
data in `apps/ios/Nooki/Demo/LandingDemo.swift`.

## Tokens

`src/tokens.ts` mirrors the Dusk and Classic colours the panels use. `check-tokens.ts` reads `Palette.swift`
and fails (in `--check`, before every render and in `pnpm appstore:test`) when a mirror drifts.
