# billet v1 (archived)

The first billet app, replaced by Nooki in `apps/ios` (#287). Nothing builds or tests it.

`packages/` holds the code only this app used, moved out of `packages/ios` and
`packages/pet-scenes`: its screens (`features-v1`: FeatureHome, FeatureSettings, FeatureInbox,
Labs, Surfaces, PetSceneCatalog) and its RealityKit scenes (`pet-scenes-reality`). The flat window
views Nooki still draws moved to `apps/ios/WindowViews/Views`, so `pet-scenes-reality` no longer
compiles on its own; check out a commit from before the move to build the app.
