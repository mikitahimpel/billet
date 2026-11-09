// The FAQ page, the home page's questions, their FAQPage JSON-LD and llms.txt all read these, so they never disagree.
// Every answer is checked against the app: docs/privacy.md, docs/payments.md, docs/release-flags.md, apps/ios.
export type Question = {
  question: string;
  answer: string;
  topic: "Basics" | "Pairing" | "Features" | "Coins" | "Privacy";
  // Also asked on the home page.
  home?: boolean;
};

export const questions: Question[] = [
  {
    topic: "Basics",
    home: true,
    question: "What is Ourio?",
    answer:
      "Ourio is a free iPhone app for couples. You share one cozy room and a cat named Mochi. When you pet her, draw, leave a note or send a photo, it shows up on your partner's iPhone, often right on their Lock Screen through a widget.",
  },
  {
    topic: "Basics",
    home: true,
    question: "Is Ourio free?",
    answer:
      "Yes. Ourio is free to download and has no in-app purchases or subscription. Coins for furniture come from doing things together.",
  },
  {
    topic: "Basics",
    home: true,
    question: "What do we need to use it?",
    answer:
      "Two iPhones on iOS 18 or later, one for each of you. Ourio is iPhone-only for now: there is no Android or iPad version.",
  },
  {
    topic: "Basics",
    home: true,
    question: "Is it a chat app?",
    answer:
      "No. Ourio has no chat and no feed. You do small things for Mochi and for each other, and they arrive quietly.",
  },

  {
    topic: "Basics",
    question: "Which languages and countries is Ourio available in?",
    answer: "Ourio is in English and available on the US App Store.",
  },
  {
    topic: "Basics",
    question: "How is Ourio different from other couples apps?",
    answer:
      "Most couples apps are a private chat or a shared calendar. Ourio is built around a shared room and a cat you look after together, with the planner (lists, wishlists, calendar, date night) and games around her, and no chat at all.",
  },
  {
    topic: "Pairing",
    home: true,
    question: "How do we pair our phones?",
    answer:
      "One of you opens Ourio and gets a 10-character code. The other types it into Ourio on their phone within 24 hours, or scans it as a QR code. A room holds exactly two people.",
  },
  {
    topic: "Pairing",
    question: "Do we need to make an account?",
    answer:
      "No. Ourio creates an anonymous account with no email or password and keeps its key in your iCloud Keychain. You can link Sign in with Apple later to save your cat and notes.",
  },
  {
    topic: "Pairing",
    question: "What happens if we unpair?",
    answer:
      "The shared room, with its notes, photos, cat and activity, is deleted for both of you. Each of you keeps the inks and pieces you bought and half the coins. You can pair again with a new code.",
  },
  {
    topic: "Pairing",
    question: "I got a new iPhone. Will my room come back?",
    answer:
      "Yes, if your iCloud Keychain moved with you or you linked Sign in with Apple: open Ourio on the new phone and it finds your account.",
  },
  {
    topic: "Features",
    home: true,
    question: "Does it work for a long-distance relationship?",
    answer:
      "Yes. Everything one of you does reaches the other phone over the internet, wherever you both are, and a drawing appears on your partner's Lock Screen widget.",
  },
  {
    topic: "Features",
    home: true,
    question: "What happens if we miss a day?",
    answer:
      "Nothing bad. Mochi never gets sick or sad because you were away. If your love streak breaks, you can bring it back once a month.",
  },
  {
    topic: "Features",
    question: "Can I draw on my partner's Lock Screen?",
    answer:
      "Yes. Your drawing appears in Ourio's Drawing widget on their Lock Screen or Home Screen, with a notification. iOS doesn't let any app change the wallpaper itself, so they add the widget once.",
  },
  {
    topic: "Features",
    question: "What games can couples play in Ourio?",
    answer:
      "Who knows who, a daily round of five questions about one of you, and Draw & guess, where one draws a word and the other spells it from letter tiles. Both are free and turn-based.",
  },
  {
    topic: "Features",
    question: "Can we make shared lists and wishlists?",
    answer:
      "Yes. The Us tab has shared lists (To watch, Groceries, Places to go, Places to eat, To read, Bucket list and your own), wishlists with secret gifting, a shared calendar, countdowns and date night ideas you swipe together.",
  },
  {
    topic: "Features",
    question: "Does Ourio have widgets?",
    answer:
      "Yes, six: the room with Mochi, the cat with a smart block, a single block, an Us widget for the Lock Screen, your partner's latest note and their latest drawing. There are also Control Center buttons to pet your cat or write a note.",
  },
  {
    topic: "Coins",
    question: "How do we get coins?",
    answer:
      "By doing things together: caring for Mochi, notes, photos, ticking list items, date ideas you both love, rating dates, gifts from wishlists and the games. A new pair starts with 560 coins.",
  },
  {
    topic: "Coins",
    question: "Can we buy coins?",
    answer:
      "No. Ourio has no in-app purchases. Coins have no cash value and belong to the two of you.",
  },
  {
    topic: "Privacy",
    home: true,
    question: "What does Ourio know about us?",
    answer:
      "Your account is anonymous: Ourio never receives your name or email. It keeps the notes, drawings, photos and lists you share so they reach your partner, and only a one-way hash of your pairing code. No ads, no tracking, no AI training on your content.",
  },
  {
    topic: "Privacy",
    question: "How do I delete my account?",
    answer:
      "Settings › Delete account. Your account and what you sent are deleted from the server, your partner is unpaired and everything on the phone is erased. This can't be undone.",
  },
];

export const faq = questions.filter((item) => item.home);
