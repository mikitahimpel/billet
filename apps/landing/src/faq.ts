// The page's FAQ section, its FAQPage JSON-LD and llms.txt all read these, so the three never disagree.
// Every answer is checked against the app: docs/privacy.md, docs/payments.md, apps/ios/project.yml.
export const faq = [
  {
    question: "What is Nooki?",
    answer:
      "Nooki is an iPhone app for couples. You share one cozy room and a cat named Mochi. When you pet her, feed her, draw or leave a note, it shows up on your partner's Lock Screen and home screen widget.",
  },
  {
    question: "Is Nooki free?",
    answer:
      "Yes. Nooki is free to download and has no in-app purchases at launch. Coins for furniture come from looking after Mochi together.",
  },
  {
    question: "What do we need to use it?",
    answer:
      "Two iPhones on iOS 18 or later, one for each of you. Nooki is iPhone-only for now: there is no Android or iPad version.",
  },
  {
    question: "How do we pair our phones?",
    answer:
      "One of you opens Nooki and gets a 10-character code. The other types it into Nooki on their phone within 24 hours. A room holds exactly two people.",
  },
  {
    question: "Does it work for a long-distance relationship?",
    answer:
      "Yes. Everything one of you does reaches the other phone over the internet, wherever you both are, and a drawing appears on your partner's Lock Screen stroke by stroke.",
  },
  {
    question: "What happens if we miss a day?",
    answer:
      "Nothing bad. Your shared flame rests as an ember instead of going out, and Mochi never gets sick or sad because you were away.",
  },
  {
    question: "Is it a chat app?",
    answer:
      "No. Nooki has no chat and no feed. You do small things for Mochi and for each other, and they arrive quietly.",
  },
  {
    question: "What does Nooki know about us?",
    answer:
      "You sign in with Apple, and Nooki never receives your name or email. It keeps the notes, drawings and photos you send each other so they reach your partner, and only a one-way hash of your pairing code.",
  },
];
