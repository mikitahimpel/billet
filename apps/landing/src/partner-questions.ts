import catalog from "@billet/backend-guess/question-catalog.json" with { type: "json" };

// The questions of Who knows who, the daily quiz in the app, grouped by their catalog tag. The page asks them
// in the "you" form, as one partner would ask the other.

type Tag = "quirks" | "food" | "music" | "dreams" | "past" | "habits" | "money" | "us";

export const updated = { iso: "2026-11-13", label: "November 13, 2026" };

export const topics: { tag: Tag; id: string; heading: string; intro: string }[] = [
  {
    tag: "quirks",
    id: "fun",
    heading: "Fun questions to ask your partner",
    intro: "Light ones for a car ride or a slow evening. Nobody has a wrong answer.",
  },
  {
    tag: "food",
    id: "food",
    heading: "Questions about food",
    intro: "Everyone has opinions about food, and they come out fast.",
  },
  {
    tag: "music",
    id: "music",
    heading: "Questions about music",
    intro: "Guilty pleasures, first concerts and what plays in the car.",
  },
  {
    tag: "dreams",
    id: "get-to-know",
    heading: "Questions to get to know your partner better",
    intro: "What they'd do with a free day, a free ticket or a different life.",
  },
  {
    tag: "past",
    id: "past",
    heading: "Questions about their childhood and past",
    intro: "Summers, first pets, school: the stories you haven't heard yet.",
  },
  {
    tag: "habits",
    id: "habits",
    heading: "Questions about everyday habits",
    intro:
      "The small habits you'll live with: alarms, folding laundry, the state of an email inbox.",
  },
  {
    tag: "money",
    id: "before-marriage-money",
    heading: "Questions to ask before marriage: money",
    intro: "Worth asking before you share a lease or a bank account.",
  },
  {
    tag: "us",
    id: "relationship",
    heading: "Questions about your relationship",
    intro: "About the two of you: chores, favorite photos, how you'd sum it up.",
  },
];

const all = catalog.questions as { id: number; self: string; tag: string }[];

export const questionsByTopic = topics.map((topic) => ({
  ...topic,
  questions: all.filter((question) => question.tag === topic.tag).map((question) => question.self),
}));

export const questionCount = all.length;

export const faq: { question: string; answer: string }[] = [
  {
    question: "What are good questions to ask your partner?",
    answer:
      "Open, specific questions work best: what they would do with a free Saturday, their first concert, how they eat a pizza crust. Small questions get real answers more often than big ones.",
  },
  {
    question: "What questions should you ask before marriage?",
    answer:
      "Ask about money (budgets, debt, how you each spend), how you'll split chores, and what you each want from the next few years. The money and relationship lists above are a place to start.",
  },
  {
    question: "How many questions should you ask at once?",
    answer:
      "A few at a time. Five questions a day keeps it a game, not an interview; that's the size of a daily round in Ourio's Who knows who.",
  },
  {
    question: "Is there an app with questions for couples?",
    answer:
      "Yes. Ourio, a free iPhone app for couples, asks five of these questions a day in Who knows who: one of you answers, the other guesses, and the answers open together.",
  },
];
