# App size

What is in the Ourio bundle, what was removed without changing how anything looks, and a design for On-Demand
Resources (#739, #740) that is **not implemented**: it needs the owner's decision.

Measured on 2026-11-13 from `origin/main` (0035bd1e), Release, unsigned `iphoneos` build
(`xcodebuild -configuration Release -sdk iphoneos CODE_SIGNING_ALLOWED=NO`). An archive strips the binaries; the
estimates for that are marked. "IPA" is the `Payload/` zipped with `zip -r`, which is close to the App Store's
download size before App Thinning (the App Store thins nothing here: one device family, one slice).

## 1. Where the bytes are

| Category | Files | Bytes | In the IPA (zipped) | Note |
| --- | --- | --- | --- | --- |
| USDZ models | 84 | 67.5 MB | 37.0 MB | stored uncompressed inside the USDZ, so the IPA halves them |
| Coat colours `.fdc` | 20 | 31.8 MB | 25.1 MB | 5 coats x 4 poses, 3 floats per splat |
| Splat PLY | 4 | 29.7 MB | 26.8 MB | `Mochi`, `MochiStanding`, `MochiLoaf`, `MochiSleep` |
| JPEG | 10 (+ 2 in shells) | 9.3 MB | 9.3 MB | coat textures for the mesh cat |
| PNG | 7 in the app (+ 18 in extensions) | 5.4 MB | 5.4 MB | portraits, coat cards |
| WebP | 105 | 7.0 MB | 7.0 MB | hero frames, shop pictures, city layers |
| `.skin` | 4 | 4.2 MB | 0.6 MB | |
| `Assets.car` | 1 | 2.4 MB | | AppIcon is 1.1 MB of it |
| Fonts, JSON | | 0.7 MB | | |
| Main binary | 1 | 39.0 MB (about 15.3 MB stripped) | | symbols in this unarchived build |
| Three extension binaries | 3 | 12.2 to 14.3 MB each (about 5.6 to 6.4 MB stripped) | | |

Whole `.app` 242.6 MB; IPA 139.0 MB (with unstripped binaries). Largest files: `CatStanding.usdz` 11.0,
`Cat.usdz` 10.9, `MochiStanding.ply` 7.7, `Mochi.ply` 7.3, `MochiSleep.ply` 7.3, `MochiLoaf.ply` 7.3,
`Base_donutbed.usdz` 6.8, `City_shell.usdz` 4.8, `Item_yarn.usdz` 3.4, `Item_donutbed.usdz` 2.9, `Assets.car`
2.4, `Room_shell.usdz` 2.4, `Room_furniture.usdz` 2.3 MB, then the twenty `.fdc` at 1.57 to 1.66 MB each.

Splat and cat assets: the four PLY are the splat cat for a GPU that can draw splats; `Cat.usdz` and
`CatStanding.usdz` (each 6.8 MB of geometry plus 4 MB of textures) are the meshes for everything else (Simulator,
iOS below 27 or older GPUs; deployment target is 18), so neither side can go. A coat is the grey PLY plus an `.fdc`
laid over it on first use (`CatCoat.bundle`), written to Caches, so a coat costs the install `.fdc` plus the same
bytes again in Caches.

### Duplicates across the app and its extensions

- `MochiPortrait*.png`: 6 files, 1.6 MB, were copied into the app, the widgets **and** the notification and share
  extensions (4 copies, 6.4 MB). Only the widgets and the app read them.
- Byte-identical files elsewhere: `HeroEar1/2-black.webp` equal `-tuxedo` (60 KB, not removed: the bake writes both
  and the saving is under 0.05 %); the rest of the matches are empty `Contents.json`, entitlements and privacy
  manifests.
- `Base_*`, `Decor_*`, `Item_*` and `Room_*` USDZ are different models, not copies (hashes differ).

### Debug-only data in Release

Nothing found. Labs, the `-perf.script` hooks and `ScenePerf` are compiled out unless `BILLET_LABS` and
`BILLET_PERF_HOOKS` are set (`project.yml`), the test hosts are separate targets, `city_contact.*` and
`room_contact.*` are the shells' contact shadows (read by `DioramaScene`). A scan for resources whose name appears in
no source file finds only dynamically named files (shop colourways such as `Item_armchair-cocoa`, city layers);
none was removed.

## 2. What changed

| Change | Before | After | Looks the same because |
| --- | --- | --- | --- |
| Notification and share extensions drop `Shared/Resources` (`project.yml`) | 2 x 1.6 MB | 0 | Neither reads an image by name; the widgets still carry all six |
| Coat JPEGs rewritten with optimised progressive tables (`jpegtran -optimize -progressive -copy none`) | 9,336,085 B | 8,886,660 B (-449,425) | Lossless: every decoded pixel compared equal with Pillow; the files had no ICC or EXIF |
| Coat colours as half floats (`.fdc` to `.fdh`), a separate pull request | 31,847,160 B (IPA 25.1 MB) | 15,923,580 B (IPA 7.8 MB) | See below |

Half-float coats: each `f_dc` is rounded to a half float. The largest error is 0.0019 (colour = 0.5 + 0.282 x
`f_dc`, so 0.0005 of full scale). Against the old files, 113,472 of 7,961,790 colour channels (1.4 %) land one
8-bit level away and none two. A numpy render of the seated splat with `Tools/bake_hero.py`'s renderer, old colours
against new, at 540 x 720: maximum 8-bit difference 1 in every coat, on 2,848 to 4,177 of 388,800 pixels (about
1 %), mean absolute difference 0.002 to 0.003. `CatCoatTests` no longer compares with billet-gpu's byte-exact PLY
hashes (they cannot hold); it pins the rebuilt PLY, whose non-colour bytes are the original's.

Tried and not worth it: lossless re-encoding of the Hero patches (44 KB of 1.79 MB), PNG recompression of the cat
texture (`MochiFur.png` is already minimal, the rest save 1 to 3 %), re-writing `Base_donutbed.usdc` (same size; the
geometry is 6.8 MB of unindexed floats, a model change and not a repack).

## 3. Cold launch

`LaunchSignposts` already logs the intervals (`log stream --predicate 'subsystem == "com.ourio.app"'`). Five cold
Release launches on the iPhone 17 Simulator, with the Mac at a load average above 200 (other agents' builds), so the
absolute numbers are not usable and are not a baseline:

| Interval | Range over runs |
| --- | --- |
| `assemble` (session, stores, onboarding state) | 39 to 112 ms |
| `stores` inside it | 7 to 34 ms |
| process start to `home first frame` | 4.2 to 7.6 s (loaded Mac) |
| `home first frame` to `room ready` | 4.5 to 8.4 s (loaded Mac) |
| `phys_footprint` after 14 s | 186 to 232 MB, peak 258 to 289 MB |

What the main thread does before the first frame is `OurioApp.init` (`NavigationBarStyle.prepare`, a `URLCache`,
`assemble`), whose own cost is about 0.1 s; the rest is the system loading the 39 MB image and SwiftUI building
`HomeView`. The room (splat, shells, furniture) loads in tasks after the first frame, behind the splash. Nothing in
`init` is deferrable for more than a few milliseconds; the file counts that matter (`.ply`, `.usdz`) are read lazily
already. A trustworthy first-second profile needs a quiet Mac or a device (`xctrace record --template 'Time
Profiler'`); it is not claimed here.

## 4. On-Demand Resources: design (not built)

Why: 42 MB of coats (20 `.fdc` + 10 JPEGs + cards), 21.6 MB of shop USDZ (55 files; #740), 4.8 MB `City_shell`, are
needed by few people at first launch. Together about 60 MB of 139 MB IPA.

Tags, sized after the half-float change:

| Tag | Contents | Size | When |
| --- | --- | --- | --- |
| `coat-ginger`, `-cream`, `-tuxedo`, `-black`, `-calico` | `<pose>-<coat>.fdh` x4, `CatColor`, `CatStandingColor`, `Coat-<coat>.png`, `Hero*-<coat>.webp` | 5.1 to 6.7 MB each (8.3 to 9.9 MB with `.fdc`) | when the coat is picked (onboarding or Profile) |
| `city` | `City_shell.usdz`, `CityDiorama/*` | about 5.1 MB | first time the City room opens |
| `shop-<collection>` | `Shop/Item_*.usdz` by collection | 21.6 MB over the collections | item sheet or room placement of an item the pair owns |
| (install) | grey coat, Mochi PLY and skins, Room, `Decor_*`, `Base_*`, `Shop/*.webp` thumbnails, `MochiPortrait*` | the rest | with the app |

Not ODR: anything an extension reads (portraits, fonts, `date-catalog.json`), `Assets.car`, and everything the Home
room needs on a cold start with no network.

Offline behaviour, per tag:
- A coat is picked by the user, so the picker asks for the tag (`NSBundleResourceRequest.beginAccessingResources`),
  shows progress, and wears the old coat until the request succeeds. Once worn, the tag is also written as the
  dressed PLYs in Caches, which `CatCoat.bundle` already does, but Caches can be purged, so the worn coat's tag is
  also requested at every launch and the request kept for the process's life (`conditionallyBeginAccessingResources`
  first: no network when it is on the phone).
- `city` and shop items fall back to what already exists: the City button stays unpressable with a one-line "needs
  a connection" while the tag is absent; an owned item with no model shows its WebP thumbnail on the shelf and a
  plain placeholder in the Room until it arrives. The room never waits on a request.
- Server option for shop items (#740): `ShopCatalogRoutes` already serves art by hash with a one-year
  `max-age`; USDZ could go the same way, with the Caches file written once. That avoids ODR's tag and size limits
  and works in TestFlight and for the Simulator identically, but adds our own bandwidth and a download path to test.

Prefetch: after a pair is paired and on Wi-Fi, request the partner's worn coat and the pair's owned shop tags in the
background (`loadingPriority` low) once, in that order; `ON_DEMAND_RESOURCES_PREFETCH_ORDER` for the tags the first
launch needs (the worn coat) is not usable because the coat is chosen after install. The initial-install tag set
stays the grey coat.

TestFlight and App Store: ODR assets are hosted by Apple for both; a TestFlight build downloads them on demand
like the store, and the Simulator and Debug builds keep every tag in the bundle, so the offline fallback and the
progress UI cannot be tested there: they need a TestFlight build on a phone in aeroplane mode. App Review needs the
app to work when a tag fails, so the fallbacks above are part of the change, not polish. Tag, size and count limits
(per-tag and total) come from Apple's documentation and were not re-read for this note.
XcodeGen needs `resourceTags` on the resource sources and `ENABLE_ON_DEMAND_RESOURCES = YES`; neither was tried.
`check-archive.sh` should list the tags so a missing one fails the archive.

Alternative: Apple-Hosted Background Assets (asset packs) replace ODR in newer SDKs but need iOS 26; the deployment
target is 18, so ODR or our own server stay the options for now. Not checked against current documentation.

Decision needed from the owner: ODR (about 60 MB off the IPA, 5 to 9 MB per coat picked) versus our own server
for the shop models, and whether a first-time coat choice during onboarding may wait for a download.
