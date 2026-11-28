import { november19, november28, type Capability, type Checked } from "./compare";

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
  // Feature rows of the table, all by default.
  rows?: Capability[];
  // The Ourio feature page the list is about.
  feature?: { slug: string; label: string };
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
  {
    slug: "draw-on-each-others-lock-screen",
    title: "Apps to draw on each other's Lock Screen (friends and couples)",
    description:
      "8 apps to draw on each other's Lock Screen or Home Screen, for couples and groups of friends: Ourio, Widgetable, UsTwo, Drawing Together, Lovly, noteit and more.",
    summary:
      "Eight apps that put your drawing on a partner's or a friend's Lock Screen, and which ones work for a group.",
    label: "Draw on each other's Lock Screen",
    h1: "Apps to draw on each other's Lock Screen, for friends and couples",
    lead: "We compared 8 iPhone apps that let you draw something that shows up on another person's Lock Screen or Home Screen: three are made for a couple and five work with friends. Ourio, which we make, pairs with exactly one partner, so for a group of friends Widgetable or Drawing Together on Lockscreen fit better. No app can change someone's wallpaper, so every one of them delivers the drawing through a widget.",
    method:
      "We make Ourio, so it's first and you should read this as our view. The other apps' facts come from their US App Store pages, websites and Google Play. The rest is ordered by how directly each puts a drawing on the other person's Lock Screen, then by App Store ratings. We left out Locket Widget (photos, no drawing), Artmate (drawing lessons inside the app, nothing on the other phone), and LoveBliss and DuoArt (ratings under 3 and no update in over a year).",
    picks: [
      {
        app: "Ourio",
        bestFor:
          "A couple: drawings and notes on your partner's Lock Screen, live drawing together and a shared cat, free. It pairs with one person only, so it isn't for a group.",
      },
      {
        app: "Widgetable",
        bestFor:
          "A group of friends: shared Home Screen and Lock Screen widgets with doodles and pets, on iPhone and Android.",
      },
      {
        app: "UsTwo",
        bestFor:
          "A couple on iPhone and Android: a shared live canvas on home and lock screen widgets, with questions, games and a pet.",
      },
      {
        app: "Drawing Together on Lockscreen",
        bestFor:
          "Friends or family drawing live on each other's lock screens. Its last update was in August 2024.",
      },
      {
        app: "Lovly",
        bestFor:
          "A couple who want one shared canvas on the Lock Screen and nothing else, with no ads or streaks.",
      },
      {
        app: "noteit",
        bestFor:
          "Quick notes, pics and drawings to a partner's or best friends' Home Screen, on iPhone and Android.",
      },
      {
        app: "Skizz",
        bestFor:
          "Friends or a couple sending drawings to a widget, and drawing over photos and videos.",
      },
      {
        app: "Getwid",
        bestFor: "Sending a free doodle, photo or countdown widget to a friend's Home Screen.",
      },
    ],
    questions: [
      {
        question: "Can friends draw on each other's Lock Screen?",
        answer:
          "Yes. Widgetable, Drawing Together on Lockscreen, noteit, Skizz and Getwid work with friends, not only a partner. Ourio, UsTwo and Lovly are made for a couple.",
      },
      {
        question: "Can I use Ourio with a group of friends?",
        answer:
          "No. Ourio pairs your iPhone with one partner's, and drawings only go to the person you paired with. For a group of friends, Widgetable or Drawing Together on Lockscreen fit better.",
      },
      {
        question: "Does the drawing change the other person's wallpaper?",
        answer:
          "No. iOS doesn't let an app change the wallpaper, so the drawing appears in the app's widget on the Lock Screen or Home Screen. The other person adds that widget once.",
      },
      {
        question: "Which of these apps is free with no subscription?",
        answer:
          "Ourio and Getwid list no subscription on the App Store. The others are free to download with a paid tier, for example Widgetable Premium at $4.99 a month or $19.99 a year and Drawing Together on Lockscreen at $3.99 a week or $14.99 a year.",
      },
      {
        question: "Which work on Android?",
        answer:
          "Widgetable, UsTwo and noteit are on Google Play as well as the App Store. We didn't find Ourio, Drawing Together on Lockscreen, Lovly, Skizz or Getwid on Google Play.",
      },
    ],
    updated: november28,
    rows: ["drawing", "widgets", "pet", "games"],
    feature: { slug: "lock-screen-drawings", label: "how Lock Screen drawings work" },
  },
  {
    slug: "movie-picker-app-for-couples",
    title: "Movie picker apps for couples: swipe and match a film to watch tonight",
    description:
      "5 movie picker apps for couples compared: Ourio's Pick tonight, Matched, ReelMatch, CineDuo and Movie Night. How the swipe and match works, prices and Android.",
    summary: "Five apps where two people swipe movies and match on one to watch tonight, compared.",
    label: "Movie picker apps for couples",
    h1: "Movie picker apps for couples: swipe and match a film to watch tonight",
    lead: "We compared 5 iPhone apps that let two people swipe through movies on their own phones and match on one they both want to watch: Ourio's Pick tonight, Matched, ReelMatch, CineDuo and Movie Night. Only Matched and ReelMatch are on Android too, and only Ourio has no paid tier.",
    method:
      "We make Ourio, so it's first and you should read this as our view. The other apps' facts come from their US App Store pages, websites and Google Play. The rest is ordered by App Store ratings. Newer apps that do the same swipe and match with one rating or none, MoviePicker, WatchPick, Shared Watchlist and What's NxtUp, are left out; CineDuo and Movie Night stay as the newest for couples and for groups. Swatched no longer shows on the US App Store.",
    picks: [
      {
        app: "Ourio",
        bestFor:
          "A movie picker free inside a couples app: you each swipe on your own iPhone, two Want to on one title within 24 hours is a match, and each title shows where it streams in the US.",
      },
      {
        app: "Matched",
        bestFor:
          "The most-rated movie picker for couples, on iPhone and Android, with matches filtered by mood or streaming service.",
      },
      {
        app: "ReelMatch",
        bestFor:
          "Deciding from trailers, then comparing Liked lists with friends or family, on iPhone and Android.",
      },
      {
        app: "CineDuo",
        bestFor:
          "A couples-only matcher with a joint watchlist and stats on where your tastes clash, with a one-time upgrade.",
      },
      {
        app: "Movie Night",
        bestFor:
          "A group: private rooms where friends or a partner swipe in real time until everyone matches.",
      },
    ],
    questions: [
      {
        question: "What is the best movie picker app for couples?",
        answer:
          "For a free one inside a couples app, Ourio's Pick tonight. For the most-rated standalone app, on Android too, Matched. For picking from trailers, ReelMatch. For more than two people, Movie Night.",
      },
      {
        question: "How do movie matching apps for couples work?",
        answer:
          "Each of you swipes through movies and shows on your own phone, and when you both say yes to the same title, the app calls it a match. In Ourio a match is two Want to swipes on one title within 24 hours, and your partner gets a notification naming it.",
      },
      {
        question: "Is there a free movie picker app for couples?",
        answer:
          "Ourio's Pick tonight is free, with no subscription and no in-app purchases. Matched, ReelMatch, CineDuo and Movie Night are free to download with a paid tier, for example Matched Premium at $2.99 a month or $19.99 a year and CineDuo Premium at $4.99 once.",
      },
      {
        question: "Can we pick a movie together when we're long distance?",
        answer:
          "Yes. In Ourio you swipe on your own phones, even hours apart, and the match lands when the second Want to does. Then start the film at the same time on a call.",
      },
      {
        question: "Which movie picker apps work on Android?",
        answer:
          "Matched and ReelMatch are on Google Play as well as the App Store. We didn't find Ourio, CineDuo or Movie Night on Google Play.",
      },
    ],
    updated: november28,
    rows: [],
    feature: { slug: "movie-night", label: "how Pick tonight works" },
  },
];
