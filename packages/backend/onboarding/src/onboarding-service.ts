import { Clock, Context, Effect, Layer } from "effect";
import type { UserId } from "@billet/contracts-domain/ids";
import type {
  OnboardingResponse,
  SaveOnboardingAnswerRequest,
} from "@billet/contracts-http-api/onboarding";
import { answerProblem } from "./answer-check.ts";
import { OnboardingCatalogue } from "./catalogue.ts";
import { InvalidAnswer, type OnboardingUnavailable } from "./onboarding-error.ts";
import { OnboardingRepository } from "./onboarding-repository.ts";

export class OnboardingService extends Context.Service<
  OnboardingService,
  {
    readonly catalogue: OnboardingResponse;
    /**
     * A future `answeredAt` is taken as now, so a phone clock running ahead can't pin an answer.
     */
    readonly save: (
      userId: UserId,
      request: SaveOnboardingAnswerRequest,
    ) => Effect.Effect<void, InvalidAnswer | OnboardingUnavailable>;
  }
>()("@billet/backend-onboarding/OnboardingService") {
  static readonly layer: Layer.Layer<
    OnboardingService,
    never,
    OnboardingCatalogue | OnboardingRepository
  > = Layer.effect(
    OnboardingService,
    Effect.gen(function* () {
      const { current, native } = yield* OnboardingCatalogue;
      const steps = [...current.steps, ...native];
      const repository = yield* OnboardingRepository;

      const save = Effect.fn("OnboardingService.save")(function* (
        userId: UserId,
        request: SaveOnboardingAnswerRequest,
      ): Effect.fn.Return<void, InvalidAnswer | OnboardingUnavailable> {
        const step = steps.find((candidate) => candidate.id === request.stepId);
        if (step === undefined) return yield* new InvalidAnswer({ reason: "unknown-step" });
        const problem = answerProblem(step, request.answer);
        if (problem !== undefined) return yield* new InvalidAnswer({ reason: "answer-mismatch" });
        const now = yield* Clock.currentTimeMillis;
        yield* repository.save({
          userId,
          stepId: request.stepId,
          version: request.version,
          answer: request.answer,
          answeredAt: Math.min(request.answeredAt, now),
        });
      });

      return OnboardingService.of({ catalogue: current, save });
    }),
  );
}
