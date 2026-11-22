// Other couples apps, as their own App Store page (US) and site described them on `checked`. Only what those pages
// said is here: a feature missing from `has` means we didn't find it listed, not that the app lacks it.

export type Checked = { iso: string; label: string };

export const checked: Checked = { iso: "2026-11-09", label: "November 9, 2026" };

export type Capability =
  | "questions"
  | "games"
  | "widgets"
  | "drawing"
  | "pet"
  | "calendar"
  | "dates"
  | "lists"
  | "chat";

export const capabilities: { key: Capability; label: string }[] = [
  { key: "questions", label: "Daily questions" },
  { key: "games", label: "Games or quizzes" },
  { key: "widgets", label: "Widgets" },
  { key: "drawing", label: "Drawings to your partner" },
  { key: "pet", label: "Shared virtual pet" },
  { key: "calendar", label: "Calendar, countdown or days counter" },
  { key: "dates", label: "Date ideas" },
  { key: "lists", label: "Shared lists or wishlists" },
  { key: "chat", label: "Chat" },
];

export type App = {
  name: string;
  // Its own one-line positioning, paraphrased.
  what: string;
  price: string;
  android: boolean;
  rating: string;
  has: Capability[];
  sources: string[];
  // When this app's pages were read, if not on `checked`.
  checked?: Checked;
};

const november13: Checked = { iso: "2026-11-13", label: "November 13, 2026" };
export const november19: Checked = { iso: "2026-11-19", label: "November 19, 2026" };
export const november22: Checked = { iso: "2026-11-22", label: "November 22, 2026" };

export const ourio: App = {
  name: "Ourio",
  what: "A shared room and cat for two, with drawings on your partner's Lock Screen, games and a planner",
  price: "Free. No subscription, no in-app purchases",
  android: false,
  rating: "New, no ratings yet",
  has: ["questions", "games", "widgets", "drawing", "pet", "calendar", "dates", "lists"],
  sources: [],
};

export const apps: App[] = [
  {
    name: "Paired",
    what: "Daily questions, quizzes and guided journeys for couples, about five minutes a day",
    price: "Free; Paired Premium from $39.99 a year or $14.99 a month",
    android: true,
    rating: "4.7 (210k ratings)",
    has: ["questions", "games", "calendar"],
    sources: [
      "https://apps.apple.com/us/app/paired-couples-relationship/id1469609343",
      "https://www.paired.com",
    ],
  },
  {
    name: "Between",
    what: "A private messenger for couples with a shared calendar and memories",
    price: "Free with ads; Between Plus from $13.99 a year",
    android: true,
    rating: "4.8 (21k ratings)",
    has: ["calendar", "chat"],
    sources: [
      "https://apps.apple.com/us/app/between-couples-love-tracker/id458035189",
      "https://between.us",
    ],
  },
  {
    name: "Couple Joy",
    what: "Couple widgets, mood, a distance tracker, games and daily questions",
    price:
      "Free; Couple Joy Premium $12.99 to $39.99 (the store page doesn't say per what period), streak repairs from $0.99",
    android: true,
    rating: "4.9 (40k ratings)",
    has: ["questions", "games", "widgets", "calendar", "chat"],
    sources: [
      "https://apps.apple.com/us/app/couple-joy-relationship-app/id1624758651",
      "https://couplejoyapp.com",
    ],
    checked: november13,
  },
  {
    name: "Candle",
    what: "One-minute daily rituals: questions, photo prompts, games and local date ideas",
    price:
      "Free; Premium $4.99 a week, $12.99 a month or $39.99 to $49.99 a year, plus Sparks and streak reignites",
    android: true,
    rating: "4.8 (12k ratings)",
    has: ["questions", "games", "dates"],
    sources: [
      "https://apps.apple.com/us/app/candle-couples-relationship/id6743355635",
      "https://www.trycandle.app",
    ],
    checked: november13,
  },
  {
    name: "Locket Widget",
    what: "Live photos from your best friends on your Home Screen",
    price: "Free; Locket Gold from $1.99",
    android: true,
    rating: "4.8 (590k ratings)",
    has: ["widgets"],
    sources: ["https://apps.apple.com/us/app/locket-widget/id1600525061", "https://locket.camera"],
  },
  {
    name: "Widgetable",
    what: "Shared widgets for friends and couples, with doodles and pets you raise together",
    price:
      "Free; Widgetable Premium $19.99 a year or $4.99 a month, plus pets and food sold separately",
    android: true,
    rating: "4.9 (388k ratings)",
    has: ["widgets", "drawing", "pet"],
    sources: [
      "https://apps.apple.com/us/app/widgetable-besties-couples/id1641107226",
      "https://widgetable.net",
    ],
  },
  {
    name: "Agapé",
    what: "One personalized question a day for partners, friends and family",
    price: "Free; Premium from $19.99 a year",
    android: true,
    rating: "4.8 (26k ratings)",
    has: ["questions"],
    sources: [
      "https://apps.apple.com/us/app/agap%C3%A9-feel-close-when-apart/id1507907556",
      "https://www.getdailyagape.com",
    ],
  },
  {
    name: "Lovewick",
    what: "A relationship tracker with a question game, date ideas and a journal",
    price: "Free with a daily question limit; Lovewick Plus $29.99 a year or $9.99 a month",
    android: true,
    rating: "4.8 (1.9k ratings)",
    has: ["questions", "games", "calendar", "dates", "lists"],
    sources: [
      "https://apps.apple.com/us/app/lovewick-relationship-tracker/id1516199115",
      "https://www.lovewick.com",
    ],
  },
  {
    name: "Cupla",
    what: "A shared calendar and planner for couples",
    price: "Free; paid plans from $34.99 a year or $4.99 a month",
    android: true,
    rating: "4.7 (2.3k ratings)",
    has: ["widgets", "calendar", "dates", "lists"],
    sources: [
      "https://apps.apple.com/us/app/cupla-couples-shared-calendar/id1557764033",
      "https://www.cupla.app",
    ],
  },
  {
    name: "SumOne",
    what: "A daily question for partners and a pet you raise together",
    price: "Free; subscription $29.99 a year or $5.99 a month, plus gems",
    android: true,
    rating: "4.9 (18k ratings)",
    has: ["questions", "widgets", "pet", "calendar"],
    sources: [
      "https://apps.apple.com/us/app/sumone-for-relationships/id1469506430",
      "https://play.google.com/store/apps/details?id=com.sumone",
    ],
  },
  {
    name: "Pengu",
    what: "A shared AI pet you raise with a partner or a close friend, inside the Friends app",
    price:
      "Free; Pengu Pass $4.99, $9.99 a month for one or $69.99 a year for partners, plus offers",
    android: false,
    rating: "4.8 (238k ratings)",
    has: ["pet"],
    sources: ["https://apps.apple.com/us/app/id6462927800", "https://penguapp.co"],
    checked: november19,
  },
  {
    name: "Evergreen",
    what: "Daily questions, quizzes and expert lessons to grow your relationship",
    price: "Free; Unlimited access $9.99 to $69.99 (the store page doesn't say per what period)",
    android: true,
    rating: "4.8 (55k ratings)",
    has: ["questions", "games"],
    sources: ["https://apps.apple.com/us/app/id1573360122", "https://evergreenapp.co"],
    checked: november19,
  },
  {
    name: "Flamme",
    what: "Daily questions, quizzes, widgets and an AI relationship coach for couples",
    price: "Free; Premium $6.99 a week, $12.99 a month or $44.49 to $44.99 a year",
    android: true,
    rating: "4.7 (418 ratings)",
    has: ["questions", "games", "widgets", "calendar", "lists"],
    sources: ["https://apps.apple.com/us/app/id1583601044", "https://flamme.app"],
    checked: november19,
  },
  {
    name: "Pokipet",
    what: "A virtual cat or dog you raise in a group with friends, family or a partner",
    price: "Free; Pet pass $9.99, coins and packs from $0.99",
    android: true,
    rating: "4.6 (13k ratings)",
    has: ["games", "pet", "chat"],
    sources: [
      "https://apps.apple.com/us/app/id6443760470",
      "https://play.google.com/store/apps/details?id=com.Moonbear.Pokipet",
    ],
    checked: november19,
  },
  {
    name: "noteit",
    what: "Live notes, pics and drawings from your partner or best friend on your Home Screen",
    price: "Free; Diamond subscription $1.99 to $7.99, streak repairs $2.99 to $6.99",
    android: false,
    rating: "4.8 (99k ratings)",
    has: ["widgets", "drawing"],
    sources: ["https://apps.apple.com/us/app/id1570369625"],
    checked: november19,
  },
  {
    name: "Cozy Couples",
    what: "Mood sharing, love notes, daily questions, games and a virtual cat or dog in a home you decorate",
    price: "Free; Cozy Couples Plus $4.99 to $39.99, stars and streak repairs from $1.99",
    android: true,
    rating: "4.8 (47k ratings)",
    has: ["questions", "games", "pet", "calendar"],
    sources: ["https://apps.apple.com/us/app/id6463766369", "https://www.cozycouples.co"],
    checked: november22,
  },
];

// Apps a compare page names beside its main rival that aren't couples apps, so the /compare/ table leaves them out.
export const nearby: App[] = [
  {
    name: "Getwid",
    what: "Design a widget, a photo, words, a doodle or a countdown, and send it to a friend's Home Screen",
    price: "Free; the store page lists no in-app purchases",
    android: false,
    rating: "5.0 (2 ratings)",
    has: ["widgets", "drawing", "calendar"],
    sources: ["https://apps.apple.com/us/app/id6761107656", "https://getwid.app"],
    checked: november22,
  },
  {
    name: "PebWorld",
    what: "A tiny companion for one person that grows its own memories and habits",
    price: "Free",
    android: false,
    rating: "4.8 (5 ratings)",
    has: ["pet"],
    sources: ["https://apps.apple.com/us/app/id6770403164"],
    checked: november22,
  },
  {
    name: "Gottman Card Decks",
    what: "Questions, statements and ideas from The Gottman Institute's couples workshop card decks",
    price: "Free",
    android: true,
    rating: "4.8 (1.7k ratings)",
    has: ["questions"],
    sources: ["https://apps.apple.com/us/app/id1292398843", "https://www.gottman.com"],
    checked: november22,
  },
];

export type Alternative = {
  slug: string;
  app: string;
  title: string;
  description: string;
  // One sentence for llms.txt and the footer.
  summary: string;
  h1: string;
  lead: string;
  // Where the other app is the better pick: said plainly, so the page is useful either way.
  theyFit: string[];
  oursFit: string[];
  questions: { question: string; answer: string }[];
  // More apps for the side-by-side table, by name from `apps` or `nearby`.
  others?: string[];
};

export const alternatives: Alternative[] = [
  {
    slug: "paired-alternative",
    app: "Paired",
    others: ["Agapé", "Lovewick", "Flamme", "Gottman Card Decks"],
    title: "Paired alternatives: Ourio, Agapé, Lovewick, Flamme, Gottman",
    description:
      "Paired alternatives side by side: Ourio (free), Agapé, Lovewick, Flamme and Gottman Card Decks, with prices, features and ratings from the App Store.",
    summary: "Paired alternatives compared: Ourio, Agapé, Lovewick, Flamme and Gottman Card Decks.",
    h1: "Paired alternatives, free and paid, side by side.",
    lead: "The best Paired alternative depends on what you used Paired for. For one question a day, Agapé (Premium from $19.99 a year) or Lovewick (Plus $29.99 a year). For free research-based prompts, Gottman Card Decks. For quizzes with an AI coach, Flamme. For games, a shared cat and Lock Screen drawings with no subscription, Ourio.",
    theyFit: [
      "You want relationship coaching: Paired has guided journeys and topics to work through.",
      "One of you uses Android. Paired, Agapé, Lovewick, Flamme and Gottman Card Decks run on both; Ourio is iPhone-only for now.",
      "You want deep conversation prompts every day rather than a playful quiz.",
    ],
    oursFit: [
      "You don't want a subscription. Everything in Ourio is free for both of you.",
      "You want small things to do for each other: a doodle on their Lock Screen, a cat to look after, a streak to keep lit.",
      "You want planning too: date night ideas you swipe together, wishlists, shared lists and countdowns.",
    ],
    questions: [
      {
        question: "What are the best Paired alternatives?",
        answer:
          "Agapé and Lovewick for one question a day, Gottman Card Decks for free prompts from The Gottman Institute, Flamme for quizzes with an AI coach, and Ourio for free games, a shared cat and Lock Screen drawings.",
      },
      {
        question: "Is there a free app like Paired?",
        answer:
          "Yes. Gottman Card Decks is free, and Ourio has daily questions (Who knows who, five a day) and games for couples, free with no subscription. Agapé, Lovewick and Flamme are free to download with a paid tier.",
      },
      {
        question: "How much do Paired alternatives cost?",
        answer:
          "Paired Premium is from $39.99 a year. Agapé Premium is from $19.99 a year, Lovewick Plus $29.99 a year, Flamme Premium $44.49 to $44.99 a year. Gottman Card Decks and Ourio are free.",
      },
      {
        question: "Does Ourio have daily questions like Paired?",
        answer:
          "Yes, as a game: each day five multiple-choice questions about one of you, from 150; the other guesses, and the answers open together.",
      },
      {
        question: "Can I use Ourio and Paired together?",
        answer:
          "Yes. They don't overlap much: Paired for conversations, Ourio for the small daily things.",
      },
    ],
  },
  {
    slug: "locket-widget-alternative",
    app: "Locket Widget",
    others: ["Cozy Couples", "Widgetable", "Couple Joy"],
    title: "Locket Widget alternative for couples · Ourio",
    description:
      "A Locket Widget alternative for couples: Ourio sends drawings and notes to your partner's Lock Screen and Home Screen widgets. Free, no subscription.",
    summary: "Ourio vs Locket Widget: drawings and notes on your partner's Lock Screen, for two.",
    h1: "A Locket alternative made for two.",
    lead: "Locket Widget puts live photos from your best friends on your Home Screen. Ourio is a widget app made for couples: your partner's drawings and notes arrive on your Lock Screen, and widgets show your shared cat, their mood, days together and your next date. Free, with no subscription. Other couple widget apps: Couple Joy and Widgetable have widgets and daily questions; Cozy Couples has mood sharing, love notes and a virtual pet.",
    theyFit: [
      "You want to share photos with a group of close friends, not one partner.",
      "You want a quick camera-first app; Locket is built around snapping a photo.",
      "One of you uses Android.",
    ],
    oursFit: [
      "It's for the two of you: a pair is exactly two people, with nothing public.",
      "You'd rather draw or write than snap: drawings and notes land in Lock Screen widgets.",
      "You want more than photos: mood, a shared cat, countdowns, games and lists.",
    ],
    questions: [
      {
        question: "Is there a Locket-style widget app for couples?",
        answer:
          "Yes. Ourio's Drawing and Note widgets show your partner's latest drawing or note on your Lock Screen or Home Screen, and Moments keeps your photos as polaroids.",
      },
      {
        question: "What are the alternatives to Locket for couples?",
        answer:
          "Ourio for drawings and notes on your partner's Lock Screen and a shared cat, Couple Joy for widgets with mood and distance, Widgetable for widgets and pets with friends and a partner, and Cozy Couples for mood, love notes and a virtual pet. Prices are in the table above.",
      },
      {
        question: "Can I send photos to my partner's widget with Ourio?",
        answer:
          "Use a photo as the background of a Lock Screen drawing, or show one of your Moments in the Block widget on the Home Screen.",
      },
      {
        question: "Is Ourio free?",
        answer: "Yes. No subscription, no in-app purchases and no ads.",
      },
    ],
  },
  {
    slug: "widgetable-alternative",
    app: "Widgetable",
    others: ["Getwid", "PebWorld"],
    title: "Widgetable alternative for couples: shared pet · Ourio",
    description:
      "A Widgetable alternative for couples: raise one shared cat, send Lock Screen drawings, add mood and countdown widgets. No subscription, no paid pets or food.",
    summary: "Ourio vs Widgetable: a shared pet and widgets with nothing for sale.",
    h1: "A Widgetable alternative without the paywall.",
    lead: "Widgetable has shared widgets, doodles and pets for friends and couples; Widgetable Premium costs $19.99 a year, and pet eggs and food are sold too. Ourio is a free alternative for couples: one shared cat, Lock Screen drawings, mood, notes and countdown widgets, with no subscription and nothing for sale. Getwid sends a widget you design to a friend's Home Screen; PebWorld is a tiny companion for one person.",
    theyFit: [
      "You want widgets with friends as well as a partner.",
      "You want many widget styles and pets to collect.",
      "One of you uses Android.",
    ],
    oursFit: [
      "Nothing to buy: Mochi's food, treats and furniture come from coins you earn together.",
      "One cat and one cozy room you share, not a collection.",
      "Games, date night ideas, wishlists and a shared calendar in the same app.",
    ],
    questions: [
      {
        question: "Is there a free couples pet app like Widgetable?",
        answer:
          "Yes. In Ourio you raise one cat, Mochi, together on two iPhones, with no subscription and no paid food or pets.",
      },
      {
        question: "What are other apps like Widgetable?",
        answer:
          "Getwid lets you design a widget and send it to a friend's Home Screen, free. PebWorld is a pet that grows its own memories, for one person. Ourio is for two: one shared cat, Lock Screen drawings and countdowns, free.",
      },
      {
        question: "Does Ourio have a distance widget?",
        answer:
          "No. Ourio never uses your location. Its widgets show drawings, notes, mood, days together and countdowns.",
      },
      {
        question: "Does Ourio work with friends?",
        answer: "No. Ourio pairs exactly two people and is made for couples.",
      },
    ],
  },
  {
    slug: "couple-joy-alternative",
    app: "Couple Joy",
    title: "Couple Joy alternative: a free couples app, no premium · Ourio",
    description:
      "A free Couple Joy alternative: Ourio is an iPhone couples app with widgets, daily questions, games, a shared cat and Lock Screen drawings. No subscription.",
    summary:
      "Ourio vs Couple Joy: widgets, questions and games for two, free with no premium tier.",
    h1: "A Couple Joy alternative with nothing to unlock.",
    lead: "Couple Joy has couple widgets, mood, a distance tracker, daily questions and games, with Couple Joy Premium from $12.99 to $39.99 and paid streak repairs. Ourio is a free alternative for iPhone: widgets, five daily questions, two games, a love streak you can restore for free, a shared cat and drawings on your partner's Lock Screen, with no premium tier.",
    theyFit: [
      "You want to see how far apart you are: Couple Joy has a distance tracker. Ourio never uses your location.",
      "You want to chat about your answers inside the app; Ourio has no chat.",
      "One of you uses Android. Couple Joy runs on both; Ourio is iPhone-only for now.",
    ],
    oursFit: [
      "You don't want to pay to unlock anything: every Ourio feature is free for both of you.",
      "You'd rather draw than type: drawings and notes land on your partner's Lock Screen.",
      "You want a planner too: date night ideas you swipe together, wishlists, shared lists and countdowns.",
    ],
    questions: [
      {
        question: "Is there a free alternative to Couple Joy?",
        answer:
          "Yes. Ourio has couple widgets, daily questions, games, a love streak and countdowns, free for both partners with no subscription and no in-app purchases.",
      },
      {
        question: "Does Ourio have a streak like Couple Joy?",
        answer:
          "Yes. The love streak grows each day either of you does something together, and a broken streak of 3 days or more can be restored once every 30 days, at no cost.",
      },
      {
        question: "Does Ourio track the distance between us?",
        answer:
          "No. Ourio never asks for your location. For long distance it has drawings, notes, a shared cat and a countdown to your next visit.",
      },
    ],
  },
  {
    slug: "candle-alternative",
    app: "Candle",
    title: "Candle app alternative: a free couples app for iPhone · Ourio",
    description:
      "Looking for a free alternative to the Candle couples app? Ourio has daily questions, games, date ideas, a shared cat and Lock Screen drawings. No subscription.",
    summary: "Ourio vs Candle: daily questions, games and date ideas without a subscription.",
    h1: "A Candle alternative that stays free.",
    lead: "Candle is a couples app of one-minute daily rituals: questions, photo prompts, games and local date ideas. A year of Candle Premium costs $39.99 to $49.99. Ourio is a free alternative for iPhone: five daily questions in Who knows who, Draw & guess, 150 date ideas you swipe together, a shared cat and drawings on your partner's Lock Screen. The same year costs nothing.",
    theyFit: [
      "You want a daily photo prompt, BeReal-style, for the two of you.",
      "You want date ideas near you: Candle suggests local ones each week. Ourio's ideas don't use your location.",
      "One of you uses Android. Candle runs on both; Ourio is iPhone-only for now.",
    ],
    oursFit: [
      "You don't want a subscription. Everything in Ourio is free for both of you.",
      "You want something on your Lock Screen: your partner's drawings and notes, your shared cat, days together.",
      "You want to plan, not only talk: wishlists, shared lists, a shared calendar and countdowns.",
    ],
    questions: [
      {
        question: "Is there a free app like Candle?",
        answer:
          "Yes. Ourio has daily questions, couples games and date ideas, free with no subscription and no in-app purchases.",
      },
      {
        question: "Does Ourio have daily questions like Candle?",
        answer:
          "Yes, as a game: each day five multiple-choice questions about one of you, from 150; the other guesses, and the answers open together. All 150 are on our list of questions to ask your partner.",
      },
      {
        question: "Does Ourio have date ideas?",
        answer:
          "Yes. Date night has 150 ideas for home, going out, outdoors and long distance. You each swipe on your own phone, and when you both love one, it's a match.",
      },
    ],
  },
  {
    slug: "between-alternative",
    app: "Between",
    title: "Between app alternative: a free couples app for iPhone · Ourio",
    description:
      "A Between alternative for iPhone: Ourio has a shared calendar, countdowns, Lock Screen drawings, games and a shared cat. Free, no ads, no subscription.",
    summary:
      "Ourio vs Between: a shared calendar and countdowns plus games and a cat, with no ads.",
    h1: "A Between alternative that plays, not chats.",
    lead: "Between is a private messenger for couples with a shared calendar and memories; it is free with ads, and Between Plus costs from $13.99 a year. Ourio is a free alternative for iPhone without ads: a shared calendar, days together and countdowns, plus drawings on your partner's Lock Screen, daily games and a cat you raise together. It has no chat: you keep talking where you already do.",
    theyFit: [
      "You want a separate, private chat just for the two of you; Ourio has no chat.",
      "You want to keep years of photos and messages in one couples app.",
      "One of you uses Android. Between runs on both; Ourio is iPhone-only for now.",
    ],
    oursFit: [
      "You already text all day and want something to do together instead: games, a shared cat, date ideas.",
      "You don't want ads or a subscription. Everything in Ourio is free for both of you.",
      "You want your partner on your Lock Screen: their drawings, notes, mood and your days together.",
    ],
    questions: [
      {
        question: "Is there a free app like Between with no ads?",
        answer:
          "Yes. Ourio has a shared calendar, days together and countdowns, free for both partners with no ads, no subscription and no in-app purchases. It has no chat.",
      },
      {
        question: "Does Ourio have a shared calendar like Between?",
        answer:
          "Yes. Ourio's calendar holds both your plans, anniversaries and countdowns, and the Lock Screen widget shows days together or the days to your next date.",
      },
      {
        question: "Can I message my partner in Ourio?",
        answer:
          "Not as a chat. You can pin a note or a drawing to their Lock Screen, share your mood and send Moments, photos that arrive as polaroids.",
      },
    ],
  },
  {
    slug: "agape-alternative",
    app: "Agapé",
    title: "Agapé alternative: daily couples questions as a free game · Ourio",
    description:
      "An Agapé alternative: Ourio turns daily couples questions into a guessing game, with a shared cat and Lock Screen drawings. Free, no subscription.",
    summary: "Ourio vs Agapé: daily questions as a guessing game, free with no premium.",
    h1: "An Agapé alternative where questions are a game.",
    lead: "Agapé sends one personalized question a day to partners, friends and family; Premium costs from $19.99 a year. Ourio is a free alternative for couples on iPhone: each day one of you answers five questions about yourself, the other guesses, and the answers open together. Around it there is a shared cat, drawings on your partner's Lock Screen and a planner for two.",
    theyFit: [
      "You want open, written answers and longer reflections; Ourio's questions have four answers to pick from.",
      "You want daily questions with friends or family too; Ourio pairs exactly two people.",
      "One of you uses Android. Agapé runs on both; Ourio is iPhone-only for now.",
    ],
    oursFit: [
      "You'd like daily questions to feel like a game: guess, score, see who knows who.",
      "You don't want a subscription. Everything in Ourio is free for both of you.",
      "You want more than one question: a cat to look after, Draw & guess, date ideas and shared lists.",
    ],
    questions: [
      {
        question: "Is there a free app like Agapé?",
        answer:
          "Yes. Ourio's Who knows who asks five questions a day from 150 and is free with no subscription. All 150 are on our list of questions to ask your partner.",
      },
      {
        question: "How do Ourio's daily questions work?",
        answer:
          "Each day one of you answers five multiple-choice questions about yourself; the other guesses, and the answers open together once you have both played.",
      },
      {
        question: "Does Ourio work for long distance?",
        answer:
          "Yes. Everything works across two iPhones anywhere: the daily game, drawings on each other's Lock Screens, the shared cat and a countdown to your next visit.",
      },
    ],
  },
  {
    slug: "evergreen-alternative",
    app: "Evergreen",
    title: "Evergreen app alternative: a free, playful couples app · Ourio",
    description:
      "An Evergreen alternative: Ourio has daily questions, couples games, date ideas, a shared cat and Lock Screen drawings. Free, no subscription.",
    summary: "Ourio vs Evergreen: daily questions and games for fun, free with no subscription.",
    h1: "An Evergreen alternative that keeps it light.",
    lead: "Evergreen is a relationship growth app: daily questions, quizzes and lessons from relationship experts, with unlimited access sold from $9.99 to $69.99. Ourio is a free alternative for iPhone that is about fun more than growth: a daily guessing game, Draw & guess, 150 date ideas you swipe together, a shared cat and drawings on your partner's Lock Screen.",
    theyFit: [
      "You want to work on your relationship: lessons on communication, conflict, trust and money.",
      "You want to track your progress as a couple with check-ins.",
      "One of you uses Android. Evergreen runs on both; Ourio is iPhone-only for now.",
    ],
    oursFit: [
      "You want a few minutes of play a day rather than homework.",
      "You don't want a subscription. Everything in Ourio is free for both of you.",
      "You want to plan, too: date ideas, wishlists, shared lists, a calendar and countdowns.",
    ],
    questions: [
      {
        question: "Is there a free alternative to Evergreen?",
        answer:
          "Yes. Ourio has daily questions and couples games, free for both partners with no subscription. It has no expert lessons.",
      },
      {
        question: "Does Ourio have a streak?",
        answer:
          "Yes. The love streak grows each day either of you does something together, and a broken streak of 3 days or more can be restored once every 30 days, at no cost.",
      },
      {
        question: "Can we use Ourio and Evergreen together?",
        answer:
          "Yes. Evergreen for working on the relationship, Ourio for the small daily things: a doodle, the cat, tonight's date.",
      },
    ],
  },
  {
    slug: "pengu-alternative",
    app: "Pengu",
    title: "Pengu alternative: a shared pet app for couples, free · Ourio",
    description:
      "A Pengu alternative for couples: raise one shared cat on two iPhones, send Lock Screen drawings and play daily games. Free, no subscription, no Pengu Pass.",
    summary: "Ourio vs Pengu: a shared cat for two with nothing to buy.",
    h1: "A Pengu alternative with a cat you share.",
    lead: "Pengu, in the Friends app, is a shared AI pet you raise with a partner or a close friend; Pengu Pass costs from $4.99, or $69.99 a year for partners. Ourio is a free alternative made for couples: one cat, Mochi, that you both pet, feed and play with in a shared room, plus drawings on your partner's Lock Screen, games and a planner. Nothing is for sale.",
    theyFit: [
      "You want an AI pet that talks back and learns your routines.",
      "You want to raise a pet with a friend or sibling, not a partner.",
      "You want companions for focus and self-care too, as Friends has Bao and Mellow.",
    ],
    oursFit: [
      "It's made for couples: a pair is exactly two people.",
      "Nothing to buy: food, treats and furniture come from coins you earn together.",
      "The pet is one part: Lock Screen drawings, games, date ideas, wishlists and countdowns are in the same app.",
    ],
    questions: [
      {
        question: "Is there a free couples pet app like Pengu?",
        answer:
          "Yes. In Ourio you raise one cat, Mochi, together on two iPhones, with no subscription, no pass and no in-app purchases.",
      },
      {
        question: "Is Ourio's cat an AI?",
        answer:
          "No. Mochi doesn't chat. She lives in your shared room, reacts when either of you pets, feeds or plays with her, and shows up in your widgets.",
      },
      {
        question: "Does the cat die if we forget her?",
        answer:
          "No. Mochi never gets sick, runs away or dies. Her needs go down slowly, and nothing is lost if you miss a day.",
      },
    ],
  },
];
