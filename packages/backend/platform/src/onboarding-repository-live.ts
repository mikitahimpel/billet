import { eq, sql } from "drizzle-orm";
import { Effect, Layer, Schema } from "effect";
import type { UserId } from "@billet/contracts-domain/ids";
import type { OnboardingAnswer } from "@billet/contracts-domain/onboarding";
import { OnboardingUnavailable } from "@billet/backend-onboarding/onboarding-error";
import {
  OnboardingRepository,
  StoredOnboardingAnswer,
} from "@billet/backend-onboarding/onboarding-repository";
import { spanMethods } from "@billet/backend-observability/span-methods";
import { type DirectoryDatabase, openDirectoryDatabase } from "./directory-database.ts";
import { onboardingAnswers } from "./directory-schema.ts";

/** A test fails if the table's columns differ. */
export const OnboardingAnswerRow = Schema.Struct({
  userId: Schema.String,
  stepId: Schema.String,
  version: Schema.String,
  kind: Schema.String,
  optionIds: Schema.NullOr(Schema.String),
  value: Schema.NullOr(Schema.Int),
  text: Schema.NullOr(Schema.String),
  answeredAt: Schema.Int,
});
export type OnboardingAnswerRow = typeof OnboardingAnswerRow.Type;

// A storage error can quote bound values, an answer's text among them, so nothing survives this.
const unavailable = (cause: unknown) =>
  new OnboardingUnavailable({ reason: "directory-unavailable", cause });

const guarded = <A, E>(effect: Effect.Effect<A, E>) => Effect.mapError(effect, unavailable);

/** Only the column for the answer's kind is set; the others are null. */
const columnsOf = (answer: OnboardingAnswer) => {
  switch (answer._tag) {
    case "Skipped":
      return { kind: answer._tag, optionIds: null, value: null, text: null };
    case "Single":
      return {
        kind: answer._tag,
        optionIds: JSON.stringify([answer.option]),
        value: null,
        text: null,
      };
    case "Multi":
      return {
        kind: answer._tag,
        optionIds: JSON.stringify(answer.options),
        value: null,
        text: null,
      };
    case "Range":
      return { kind: answer._tag, optionIds: null, value: answer.value, text: null };
    case "Text":
      return { kind: answer._tag, optionIds: null, value: null, text: answer.text };
  }
};

const answerOf = (row: OnboardingAnswerRow): unknown => {
  const picks = row.optionIds === null ? [] : (JSON.parse(row.optionIds) as ReadonlyArray<string>);
  switch (row.kind) {
    case "Single":
      return { _tag: "Single", option: picks[0] };
    case "Multi":
      return { _tag: "Multi", options: picks };
    case "Range":
      return { _tag: "Range", value: row.value };
    case "Text":
      return { _tag: "Text", text: row.text };
    default:
      return { _tag: row.kind };
  }
};

const decodeStored = Schema.decodeUnknownEffect(StoredOnboardingAnswer);

const makeOnboardingRepository = (db: DirectoryDatabase): OnboardingRepository["Service"] =>
  OnboardingRepository.of(
    spanMethods("OnboardingRepository", {
      save: (answer) => {
        const values = {
          userId: answer.userId,
          stepId: answer.stepId,
          version: answer.version,
          ...columnsOf(answer.answer),
          answeredAt: answer.answeredAt,
        };
        // One statement, so two saves at once can't both see no row; the later answer wins.
        return guarded(
          db
            .insert(onboardingAnswers)
            .values(values)
            .onConflictDoUpdate({
              target: [onboardingAnswers.userId, onboardingAnswers.stepId],
              set: values,
              setWhere: sql`excluded.answered_at >= ${onboardingAnswers.answeredAt}`,
            }),
        ).pipe(Effect.asVoid);
      },
      answersOf: (userId: UserId) =>
        guarded(
          db
            .select()
            .from(onboardingAnswers)
            .where(eq(onboardingAnswers.userId, userId))
            .pipe(
              Effect.flatMap((rows) =>
                Effect.forEach(rows, (row) =>
                  decodeStored({
                    userId: row.userId,
                    stepId: row.stepId,
                    version: row.version,
                    answer: answerOf(row),
                    answeredAt: row.answeredAt,
                  }),
                ),
              ),
            ),
        ),
    }),
  );

/** Build it once per request. */
export const OnboardingRepositoryLive = (binding: D1Database): Layer.Layer<OnboardingRepository> =>
  Layer.effect(
    OnboardingRepository,
    Effect.map(openDirectoryDatabase(binding), makeOnboardingRepository),
  );
