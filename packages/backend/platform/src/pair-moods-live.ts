import { Effect, Layer } from "effect";
import { MoodService } from "@billet/backend-notes/mood-service";
import { PairMoods } from "@billet/backend-pairing/pair-moods";

/** A room it cannot reach reads as no check-ins. */
export const PairMoodsLive: Layer.Layer<PairMoods, never, MoodService> = Layer.effect(
  PairMoods,
  Effect.gen(function* () {
    const moods = yield* MoodService;
    return PairMoods.of({
      latest: (pairId) =>
        moods
          .latest(pairId)
          .pipe(
            Effect.catchTag("NotesUnavailable", (error) =>
              Effect.logWarning("pair moods unavailable", error).pipe(Effect.as([])),
            ),
          ),
    });
  }),
);
