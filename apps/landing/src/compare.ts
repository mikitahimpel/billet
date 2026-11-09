// Other couples apps, as their own App Store page (US) and site described them on `checked`. Only what those pages
// said is here: a feature missing from `has` means we didn't find it listed, not that the app lacks it.

export const checked = { iso: "2026-11-09", label: "November 9, 2026" };

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
};

export const ourio: App = {
  name: "Ourio",
  what: "A shared room and cat for two, with drawings on your partner's Lock Screen, games and a planner",
  price: "Free. No subscription, no in-app purchases",
  android: false,
  rating: "Not yet on the App Store",
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
};

export const alternatives: Alternative[] = [
  {
    slug: "paired-alternative",
    app: "Paired",
    title: "Paired alternative: a free couples app with no subscription · Ourio",
    description:
      "Looking for an app like Paired? Ourio is a free iPhone app for couples with daily questions, games, a shared cat and Lock Screen drawings, and no subscription. An honest comparison with Paired's features and prices.",
    summary: "Ourio vs Paired: daily questions and games without a subscription.",
    h1: "A Paired alternative that's free and playful.",
    lead: "Paired is a daily questions app with quizzes and guided journeys; Paired Premium costs from $39.99 a year. Ourio is a free alternative for iPhone with no subscription: five daily questions in Who knows who, Draw & guess, a shared cat, drawings on your partner's Lock Screen and a planner for two.",
    theyFit: [
      "You want relationship coaching: Paired has guided journeys and topics to work through.",
      "One of you uses Android. Paired runs on both; Ourio is iPhone-only for now.",
      "You want deep conversation prompts every day rather than a playful quiz.",
    ],
    oursFit: [
      "You don't want a subscription. Everything in Ourio is free for both of you.",
      "You want small things to do for each other: a doodle on their Lock Screen, a cat to look after, a streak to keep lit.",
      "You want planning too: date night ideas you swipe together, wishlists, shared lists and countdowns.",
    ],
    questions: [
      {
        question: "Is there a free app like Paired?",
        answer:
          "Yes. Ourio has daily questions (Who knows who, five a day) and games for couples, free with no subscription. It is lighter and more playful than Paired's coaching.",
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
    title: "Locket Widget alternative for couples: Lock Screen drawings · Ourio",
    description:
      "An alternative to Locket Widget made for couples: Ourio sends drawings and notes to your partner's Lock Screen and Home Screen widgets, with a shared cat, mood and days together. Free, no subscription.",
    summary: "Ourio vs Locket Widget: drawings and notes on your partner's Lock Screen, for two.",
    h1: "A Locket alternative made for two.",
    lead: "Locket Widget puts live photos from your best friends on your Home Screen. Ourio is a widget app made for couples: your partner's drawings and notes arrive on your Lock Screen, and widgets show your shared cat, their mood, days together and your next date. Free, with no subscription.",
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
    title: "Widgetable alternative for couples: a free shared pet and widgets · Ourio",
    description:
      "An alternative to Widgetable for couples: Ourio has a shared cat you raise together, Lock Screen drawings, mood and countdown widgets, with no subscription and no paid pets or food. Honest comparison.",
    summary: "Ourio vs Widgetable: a shared pet and widgets with nothing for sale.",
    h1: "A Widgetable alternative without the paywall.",
    lead: "Widgetable has shared widgets, doodles and pets for friends and couples; Widgetable Premium costs $19.99 a year, and pet eggs and food are sold too. Ourio is a free alternative for couples: one shared cat, Lock Screen drawings, mood, notes and countdown widgets, with no subscription and nothing for sale.",
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
];
