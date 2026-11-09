import { Context, Layer, Schema } from "effect";
import { OnboardingStep, OnboardingStepId } from "@billet/contracts-domain/onboarding";
import { OnboardingResponse } from "@billet/contracts-http-api/onboarding";
import type { CheckedStep } from "./answer-check.ts";

/**
 * The onboarding questions as they ship, in the order of the design. "Together since" is not here: it is a date the app keeps on the phone. The app's
 * own steps that follow are in `nativeSteps`.
 *
 * Changing the wording is safe. Changing what an id means is not: add a new id instead, and bump
 * `version`. An option that goes away makes a queued answer to it a 400, which the app drops.
 * The admin panel will edit this later; until then it changes with a deploy, not an app release.
 */
export const seedCatalogue: OnboardingResponse = Schema.decodeUnknownSync(OnboardingResponse)({
  version: "2026-11-04",
  steps: [
    {
      _tag: "Single",
      id: "age",
      title: { en: "How old are you?", ru: "Сколько тебе лет?" },
      subtitle: {
        en: "Billet is for 13 and up. Only you see this.",
        ru: "Billet — для тех, кому 13 и больше. Это видишь только ты.",
      },
      skippable: true,
      // Buckets only: the server never learns a date of birth. The app stops on `age-under-13` and
      // never sends it.
      options: [
        { id: "age-under-13", label: { en: "Under 13", ru: "Меньше 13" } },
        { id: "age-13-17", label: { en: "13–17", ru: "13–17" } },
        { id: "age-18-24", label: { en: "18–24", ru: "18–24" } },
        { id: "age-25-34", label: { en: "25–34", ru: "25–34" } },
        { id: "age-35-44", label: { en: "35–44", ru: "35–44" } },
        { id: "age-45-plus", label: { en: "45+", ru: "45+" } },
      ],
    },
    {
      _tag: "Single",
      id: "pronouns",
      title: { en: "How should we talk about you?", ru: "Как о тебе говорить?" },
      subtitle: {
        en: "So I tell your person right.",
        ru: "Чтобы я правильно рассказывал о тебе твоему человеку.",
      },
      skippable: true,
      options: [
        { id: "she", label: { en: "She / her", ru: "Она" } },
        { id: "he", label: { en: "He / him", ru: "Он" } },
        { id: "they", label: { en: "They / them", ru: "Нейтрально" } },
      ],
    },
    {
      _tag: "Text",
      id: "name",
      title: { en: "What does your person call you?", ru: "Как тебя называет твой человек?" },
      subtitle: {
        en: "It goes on your notes and your side of the room.",
        ru: "Это будет на твоих записках и на твоей половине комнаты.",
      },
      skippable: true,
      placeholder: { en: "Your name", ru: "Имя" },
      maxLength: 20,
    },
    {
      _tag: "Multi",
      id: "goals",
      title: { en: "What do you want to do together?", ru: "Что вы хотите делать вместе?" },
      subtitle: { en: "Pick all that fit.", ru: "Выбери всё, что подходит." },
      skippable: true,
      options: [
        {
          id: "stay-close",
          label: { en: "Stay close at a distance", ru: "Быть рядом на расстоянии" },
        },
        { id: "raise-pet", label: { en: "Raise a pet together", ru: "Растить питомца вместе" } },
        { id: "widgets", label: { en: "Use widgets", ru: "Пользоваться виджетами" } },
        { id: "grow-closer", label: { en: "Grow closer", ru: "Стать ближе" } },
        { id: "draw-together", label: { en: "Draw together", ru: "Рисовать вместе" } },
        {
          id: "just-exploring",
          label: { en: "Just exploring", ru: "Просто смотрю" },
          exclusive: true,
        },
      ],
    },
  ],
});

const nativeStep = Schema.decodeUnknownSync(OnboardingStep);

/**
 * The steps the app draws itself after the served ones, in its order: the cat's coat, its name and
 * the invite. They are not in `GET /v1/onboarding`, but their answers are stored and counted the
 * same way. A skipped name means the default, Mochi; a skipped invite means "later".
 */
export const nativeSteps: ReadonlyArray<CheckedStep> = [
  {
    _tag: "OpenChoice",
    id: Schema.decodeSync(OnboardingStepId)("cat_coat"),
    title: { en: "Cat coat (in the app)", ru: "Окрас кота (в приложении)" },
    skippable: true,
  },
  nativeStep({
    _tag: "Text",
    id: "cat_name",
    title: { en: "Cat name (in the app)", ru: "Имя кота (в приложении)" },
    skippable: true,
    maxLength: 24,
  }),
  nativeStep({
    _tag: "Single",
    id: "invite_partner",
    title: { en: "Invite partner (in the app)", ru: "Приглашение (в приложении)" },
    skippable: true,
    options: [{ id: "sent", label: { en: "Sent", ru: "Отправлено" } }],
  }),
];

/**
 * The questions the server answers with today, and the app's own steps it takes answers to. Tests,
 * and later the admin panel, give others.
 */
export class OnboardingCatalogue extends Context.Service<
  OnboardingCatalogue,
  { readonly current: OnboardingResponse; readonly native: ReadonlyArray<CheckedStep> }
>()("@billet/backend-onboarding/OnboardingCatalogue") {
  static readonly with = (current: OnboardingResponse, native = nativeSteps) =>
    Layer.succeed(OnboardingCatalogue, OnboardingCatalogue.of({ current, native }));
  static readonly seed = OnboardingCatalogue.with(seedCatalogue);
}
