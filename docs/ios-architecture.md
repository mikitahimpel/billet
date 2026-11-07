# iOS architecture (draft, WIP)

Phase 1 notes; the full document follows. Nothing here is a rule yet.

## Findings so far

- `HomeState` (apps/ios/Nooki/Model/HomeState.swift) holds navigation (tab, room, sheets, deep links,
  shopFocus, openedShopItem, usRoute, composingNote, drawing, openedPin, momentsMode, game) and the
  13 stores of `HomeStores` (profile, wallet, us, partnerMoods, streak, moments, notes, rooms, care,
  shop, gifts, lists, journal) plus `moodSync`, `setMood`, `refresh`, `eraseAll`, `didEnterBackground`.
- 58 Swift files reference `HomeState`; every tab view takes the whole object.
- `HomeView` builds the rooms (`DioramaScene`, `CityRoomScene`, `BoardRoomScene`), reads
  `state.care.petPulse` into `DioramaView`, drives the room from 10 `onChange`s and owns the splash,
  snapshots, room switch, sync wiring (`followPair`), hints and perf hooks.
- `ShopModel` + `WalletStore` + `CatCare` + `CoinsAsk` + `Purchase` are the Coins and Shop slice;
  `ShopModel.earn` is called by `UsStore` and `Journal` through closures (already an interface).
- `BilletKit` already has `Machine` + `Store<M>` (pure transition, outputs run by the store).
  `FeaturePairing`, `FeatureCanvas`, `FeatureMoments` use it. The doc builds on it.
- packages/ios must stay engine-free (`check-imports.mjs`): the Room implementation stays in
  apps/ios; only its interface (`RoomInput`, `RoomEvent`, `RoomControlling`) is a package target.
- `GameSession` and the game stages touch `CatRoom` directly: they belong inside the Room module.
- `ScenePerf.Host.census` already emits `census scene=... k=v` lines that `report.py` turns into
  A/B metrics: a body counter can ride on it.
