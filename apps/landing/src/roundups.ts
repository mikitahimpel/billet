import { november19, type Checked } from "./compare";

// Ranked lists of apps for one need, each a page at the site's root. Facts about the apps come from `apps` in
// compare.ts; only the verdict ("best for") is written here.

export type Roundup = {
  slug: string;
  title: string;
  description: string;
  // One sentence for llms.txt and the footer.
  summary: string;
  label: string;
  h1: string;
  lead: string;
  // How the list was made and who wrote it, said before the list.
  method: string;
  picks: { app: string; bestFor: string }[];
  questions: { question: string; answer: string }[];
  updated: Checked;
};

export const roundups: Roundup[] = [
  {
    slug: "best-couples-apps",
    title: "Best couples apps for iPhone in 2026: 13 picks by what they do",
    description:
      "The best couples apps for iPhone in 2026: Ourio, Paired, Between, Couple Joy, Evergreen, Candle, SumOne and more, with prices and what each is best for.",
    summary:
      "The best couples apps for iPhone in 2026, ranked by what each is best for, with prices.",
    label: "Best couples apps",
    h1: "The best couples apps for iPhone in 2026",
    lead: "There is no single best couples app: some are built for deep conversations, some for widgets, some for planning. Here are 13 apps for iPhone, each with what it's best for, its price and whether it runs on Android.",
    method:
      "We make Ourio, so it's first and you should read this as our view. Everything else comes from each app's US App Store page and website. The rest is ordered by what most couples look for first: daily questions and games, then a private space, then widgets, pets and planning.",
    picks: [
      {
        app: "Ourio",
        bestFor:
          "Couples who want a free app that's fun every day: a shared cat, drawings on each other's Lock Screens, games and a planner.",
      },
      {
        app: "Paired",
        bestFor: "Daily conversation prompts and guided journeys, if you'll pay for Premium.",
      },
      {
        app: "Between",
        bestFor: "A private chat for the two of you, with a shared calendar and memories.",
      },
      {
        app: "Couple Joy",
        bestFor: "Widgets with mood and the distance between you, plus daily questions.",
      },
      {
        app: "Evergreen",
        bestFor: "Working on your relationship with lessons from experts.",
      },
      {
        app: "Candle",
        bestFor: "One-minute daily rituals with a photo prompt and local date ideas.",
      },
      { app: "Agapé", bestFor: "One thoughtful written question a day." },
      {
        app: "SumOne",
        bestFor: "A daily question for the two of you and a pet you raise together.",
      },
      {
        app: "Widgetable",
        bestFor: "Shared widgets and pets with friends as well as a partner.",
      },
      { app: "Lovewick", bestFor: "A question game, date ideas and a relationship journal." },
      { app: "Cupla", bestFor: "Planning life together: a shared calendar, to-dos and key dates." },
      { app: "Flamme", bestFor: "Quizzes and an AI relationship coach." },
      {
        app: "Locket Widget",
        bestFor: "Live photos on the Home Screen, with a partner or friends.",
      },
    ],
    questions: [
      {
        question: "What is the best free couples app for iPhone?",
        answer:
          "Ourio is free for both partners with no subscription, no in-app purchases and no ads. Most other couples apps are free to download with a paid tier: Paired Premium from $39.99 a year, Candle Premium $39.99 to $49.99 a year.",
      },
      {
        question: "What is the best couples app for long distance?",
        answer:
          "One that gives you something to do between calls. Ourio puts your partner's drawings on your Lock Screen and has a shared cat, a daily game and a countdown to your next visit. Couple Joy shows the distance between you; Between is a private chat.",
      },
      {
        question: "Which couples apps work on iPhone and Android together?",
        answer:
          "Paired, Between, Couple Joy, Evergreen, Candle, Agapé, SumOne, Widgetable, Lovewick, Cupla, Flamme and Locket Widget run on both. Ourio is iPhone-only for now.",
      },
    ],
    updated: november19,
  },
  {
    slug: "virtual-pet-app-for-couples",
    title: "Virtual pet apps for couples: 5 shared pet apps compared",
    description:
      "Virtual pet apps for couples, compared: raise a pet together in Ourio, Widgetable, SumOne, Pengu or Pokipet. Prices, Android and what each pet does.",
    summary: "Five apps where two people raise one virtual pet, compared.",
    label: "Pet apps for couples",
    h1: "Virtual pet apps for couples",
    lead: "A shared virtual pet gives two people one small thing to look after together: when one of you feeds it, the other sees. These five apps let a couple raise a pet on two phones. They differ in what else they do and in what you pay for.",
    method:
      "We make Ourio, so it's first and you should read this as our view. The other apps' facts come from their US App Store pages and websites.",
    picks: [
      {
        app: "Ourio",
        bestFor:
          "One cat, Mochi, in a cozy room you share, with nothing to buy. Lock Screen drawings, games and a planner come with it.",
      },
      {
        app: "Widgetable",
        bestFor: "Pets that live in your Home Screen widgets, with friends or a partner.",
      },
      {
        app: "SumOne",
        bestFor: "A pet you raise together next to a daily question for the two of you.",
      },
      {
        app: "Pengu",
        bestFor: "An AI pet that learns from your conversations, with a partner or a friend.",
      },
      { app: "Pokipet", bestFor: "A cat or dog raised by a group, with match puzzles and chat." },
    ],
    questions: [
      {
        question: "What is the best virtual pet app for couples?",
        answer:
          "For a pet made for exactly two people with nothing to buy, Ourio. For a pet in widgets with friends too, Widgetable. For a pet next to a daily question, SumOne. For an AI pet that talks, Pengu.",
      },
      {
        question: "Is there a free shared pet app for couples?",
        answer:
          "Yes. In Ourio the cat, her food, treats and the room's furniture are free; you buy them with coins you earn by doing things together. The other apps sell passes, subscriptions, coins or food.",
      },
      {
        question: "What happens to the pet if we forget it?",
        answer:
          "It depends on the app. In Ourio the cat never gets sick, runs away or dies; her needs go down slowly and nothing is lost if you miss a day.",
      },
    ],
    updated: november19,
  },
  {
    slug: "best-couple-widget-apps",
    title: "Best couple widget apps for iPhone: 7 compared",
    description:
      "The best couple widget apps for iPhone: Ourio, Locket Widget, Widgetable, Couple Joy, noteit, Flamme and SumOne. Drawings, photos, mood, countdowns.",
    summary: "Seven apps that put your partner on your Home Screen or Lock Screen, compared.",
    label: "Couple widget apps",
    h1: "The best couple widget apps for iPhone",
    lead: "A couple widget puts your partner on your Home Screen or Lock Screen: their photo, a note, a drawing, their mood or the days to your next date. These seven apps do it in different ways, and some are made for friends as much as couples.",
    method:
      "We make Ourio, so it's first and you should read this as our view. The other apps' facts come from their US App Store pages and websites.",
    picks: [
      {
        app: "Ourio",
        bestFor:
          "Drawings and notes on your partner's Lock Screen, plus widgets for your shared cat, mood, days together and countdowns. Free.",
      },
      {
        app: "Locket Widget",
        bestFor: "Live photos from a partner or friends on the Home Screen.",
      },
      { app: "noteit", bestFor: "Quick notes, pics and drawings to a partner's Home Screen." },
      {
        app: "Widgetable",
        bestFor: "Many widget styles and pets, shared with friends or a partner.",
      },
      { app: "Couple Joy", bestFor: "Mood and the distance between you on a widget." },
      { app: "Flamme", bestFor: "Countdowns and milestone widgets with quizzes." },
      { app: "SumOne", bestFor: "Widgets next to a daily question and a pet you raise together." },
    ],
    questions: [
      {
        question: "What is the best widget app for couples?",
        answer:
          "For drawings and notes on the Lock Screen plus a shared pet, Ourio. For photos, Locket Widget. For quick notes to the Home Screen, noteit. For many styles shared with friends too, Widgetable.",
      },
      {
        question: "Can my partner draw on my Lock Screen?",
        answer:
          "Yes, with Ourio: your partner draws on a canvas shaped like your Lock Screen, and the drawing appears in your Lock Screen widget. It's free.",
      },
      {
        question: "Is there a free couple widget app with no subscription?",
        answer:
          "Ourio's six widgets are free for both partners, with no subscription and no in-app purchases. The other apps on this list are free to download with a paid tier.",
      },
    ],
    updated: november19,
  },
];
