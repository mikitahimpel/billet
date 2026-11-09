import type { ImageMetadata } from "astro";
import mochi from "./assets/mochi-portrait.webp";
import datePlans from "./assets/art/datescene-plans.webp";
import drawGuessCard from "./assets/art/drawguess-card.webp";
import drawGuessDraw from "./assets/art/drawguess-draw.webp";
import drawGuessHint from "./assets/art/drawguess-hint.webp";
import drawGuessSolved from "./assets/art/drawguess-solved.webp";
import room from "./assets/art/shared-room.webp";
import shotGroceries from "./assets/art/shot-groceries-list-top.webp";
import shotPartnerWishes from "./assets/art/shot-after-partner.webp";
import shotShare from "./assets/art/shot-share-extension-result.webp";
import shotUsCards from "./assets/art/shot-us-cards-full-top.webp";
import shotUsTop from "./assets/art/shot-us-now-top.webp";
import streakDay from "./assets/art/streak-day-lit.webp";
import streakTiers from "./assets/art/streak-flames-tiers.webp";
import streakTasks from "./assets/art/streak-task-icons.webp";
import streakBack from "./assets/art/streak-won-back.webp";
import whoKnowsCard from "./assets/art/whoknows-card.webp";
import whoKnowsHit from "./assets/art/whoknows-hit.webp";
import whoKnowsHost from "./assets/art/whoknows-host.webp";
import whoKnowsTrophy from "./assets/art/whoknows-trophy.webp";
import whoKnowsWaiting from "./assets/art/whoknows-waiting.webp";

// Every claim here is checked against the app (apps/ios, packages/ios/features, docs/). Things behind a release flag
// or not built (coin packs, a subscription, the drawing Live Activity, a streak freeze, the City room) stay out.

// "scene": a full picture in a frame; "cutout": Mochi on a transparent ground; "shot": an app screenshot in a phone.
export type Picture = { src: ImageMetadata; alt: string; kind: "scene" | "cutout" | "shot" };

export type FeatureSection = {
  id: string;
  heading: string;
  body: string[];
  bullets?: string[];
  table?: { head: string[]; rows: string[][]; caption: string };
  picture?: Picture;
};

export type Feature = {
  slug: string;
  // <title>: the words people type into search and into ChatGPT.
  title: string;
  description: string;
  eyebrow: string;
  h1: string;
  // The first paragraph answers "what is it" in under 50 words, so an answer engine can quote it whole.
  lead: string;
  hero: Picture;
  sections: FeatureSection[];
  questions: { question: string; answer: string }[];
};

export const featureList: Feature[] = [
  {
    slug: "room-and-mochi",
    title: "A virtual pet for couples: share a cat named Mochi · Ourio",
    description:
      "Ourio gives two partners one cozy room and one cat. Feed, water, play with and brush Mochi on your iPhone, and your partner sees it on theirs.",
    eyebrow: "The Room and Mochi",
    h1: "A cat you raise together, in a room you share.",
    lead: "Ourio gives the two of you one cozy room and one cat, Mochi. Whatever one of you does for her, feeding, playing, brushing or a pet, shows up on the other's iPhone. She has four needs, six coats to choose from, and never gets sick if you're busy.",
    hero: {
      src: room,
      alt: "Mochi asleep on a donut bed in a warm, lamp-lit room with a round window",
      kind: "scene",
    },
    sections: [
      {
        id: "care",
        heading: "Six ways to look after her",
        body: [
          "Tap Mochi to open her card: a level, how many days she has been with you two, and four bars: Full, Rested, Playful and Loved. The wording stays gentle and nothing ever turns red.",
          "Each care action is a little hands-on moment that takes over the screen:",
        ],
        bullets: [
          "Feed: tip the bag, scoop, or shake your phone to weigh kibble into her bowl on a kitchen scale.",
          "Water: hold to pour from a jug up to the line, then wipe up any spill.",
          "Play: drag a laser dot and watch her chase and pounce.",
          "Brush: stroke her back from head to tail until the fur flies.",
          "Pet and treat: a quick pet, or a treat bought with coins.",
        ],
        picture: {
          src: mochi,
          alt: "Mochi, a grey tabby kitten with a red collar and a gold bell",
          kind: "cutout",
        },
      },
      {
        id: "coats",
        heading: "Choose her coat and her name",
        body: [
          "When you move in, you pick her coat from six: grey tabby, ginger, cream, tuxedo, black or calico. Then you name her. Mochi, Biscuit, Luna, Miso, Pumpkin and Tofu are suggested; skip it and she stays Mochi.",
        ],
      },
      {
        id: "mood",
        heading: "Say how you feel",
        body: [
          "“How are you?” lets each of you pick a mood (happy, sleepy, missing you or busy) and add a few words. Your partner sees it in the room and on their widget, without a conversation to keep up.",
        ],
      },
      {
        id: "furnish",
        heading: "Furnish the room together",
        body: [
          "Everything you buy in the shop, from a Cloud Armchair to a Donut Bed, can be placed in the room and appears on both phones. You can preview a piece in 3D first, and keep extras in your closet.",
        ],
      },
    ],
    questions: [
      {
        question: "Can Mochi get sick or run away?",
        answer:
          "No. Her needs go down slowly and the wording stays gentle. A busy week never hurts her.",
      },
      {
        question: "Does each of us get our own cat?",
        answer:
          "No. There is one cat and one room per couple, and both phones always show the same Mochi.",
      },
    ],
  },
  {
    slug: "lock-screen-drawings",
    title: "Draw on your partner's Lock Screen: drawings and notes for couples · Ourio",
    description:
      "Draw with a finger on a canvas that looks like your partner's Lock Screen. Ourio delivers it to their iPhone widget with a notification, and you can watch each other draw live.",
    eyebrow: "Drawings and notes",
    h1: "Draw on their Lock Screen.",
    lead: "In Ourio you draw on a canvas that looks like your partner's Lock Screen, with their clock and wallpaper. When you send it, they get a notification and the drawing appears in the Drawing widget on their Lock Screen or Home Screen. Seven ink colors, one free.",
    hero: {
      src: drawGuessDraw,
      alt: "Mochi holding a red crayon over a sheet of paper",
      kind: "cutout",
    },
    sections: [
      {
        id: "canvas",
        heading: "A canvas that is their Lock Screen",
        body: [
          "Tap + and choose Draw. The canvas shows your partner's wallpaper, big clock and date, so you see exactly where your doodle will sit. Undo, clear, erase, change the ink, or set the wallpaper to a paper color or a photo from your Moments.",
          "If you both have the canvas open, you see each other's strokes as they happen, with “is drawing…” at the top.",
        ],
      },
      {
        id: "delivery",
        heading: "How it reaches them",
        body: [
          "Your partner gets a notification, “A new drawing on your lock screen”, and the Drawing widget updates before the alert shows. Put the widget on the Lock Screen or the Home Screen, small to large, and the latest drawing is always there with “Tap to draw one back”.",
        ],
      },
      {
        id: "inks",
        heading: "Inks",
        body: ["Graphite is free. The other inks belong to the two of you once bought:"],
        table: {
          caption: "Ink colors and their price in coins",
          head: ["Ink", "Price"],
          rows: [
            ["Graphite", "Free"],
            ["Rose, Sea, Moss, Ember", "60 coins each"],
            ["Plum", "90 coins"],
            ["Gold", "120 coins"],
          ],
        },
      },
      {
        id: "notes",
        heading: "Notes on Mochi's board",
        body: [
          "For something to keep, write a note instead. Type, or turn the pen on and draw, pick a paper color and add a stamp and seal. The note goes up on Mochi's board in the room, your partner is notified, and the Note widget shows their latest one on your Lock Screen. Each note earns 5 coins.",
        ],
      },
    ],
    questions: [
      {
        question: "Does the drawing change my partner's wallpaper?",
        answer:
          "No. It appears in Ourio's Drawing widget, which your partner adds to their Lock Screen or Home Screen once. iOS doesn't let apps change the wallpaper itself.",
      },
      {
        question: "Can we draw at the same time?",
        answer: "Yes. When you both have the canvas open you see each other's strokes live.",
      },
    ],
  },
  {
    slug: "moments",
    title: "A shared photo wall for couples: Moments as polaroids · Ourio",
    description:
      "Send your partner a photo in Ourio and it lands on Mochi's wall as an instant-film polaroid with your caption. React, pin, and share it as a polaroid.",
    eyebrow: "Moments",
    h1: "Moments, on film.",
    lead: "Moments is Ourio's shared photo wall. Add a photo of the two of you with a short caption and it goes up on Mochi's wall as a little polaroid, on both phones. Each Moment earns 10 coins, and your partner can react to it with a heart.",
    hero: {
      src: drawGuessSolved,
      alt: "Mochi cheering with a little framed heart held over her head",
      kind: "cutout",
    },
    sections: [
      {
        id: "send",
        heading: "Send a photo, get a polaroid",
        body: [
          "Tap + and choose Moment. Pick a photo, write a little note if you like, and send. It arrives on your partner's phone with an instant-film look and your caption, and they get a notification.",
        ],
      },
      {
        id: "wall",
        heading: "Your wall and your board",
        body: [
          "The Moments tab switches between Photos and Board: your polaroids, and the notes and doodles you've pinned. Open a photo to react with a heart, pin it to the wall, edit the caption, share it as a polaroid or delete it.",
        ],
      },
      {
        id: "inbox",
        heading: "Everything, by day",
        body: [
          "The Inbox in the header keeps what you two did, grouped by Today and Yesterday: who sent a drawing, who reacted to a photo, how you each feel, your streak and the games you played.",
        ],
      },
    ],
    questions: [
      {
        question: "Who can see our Moments?",
        answer:
          "Only the two of you. Photos are kept in your pair's private storage, and Ourio never uses them for ads or to train AI.",
      },
    ],
  },
  {
    slug: "us",
    title:
      "Couples planner: countdown, date night ideas, wishlists, shared lists and calendar · Ourio",
    description:
      "The Us tab in Ourio holds your days together, countdowns, a love streak, date night ideas you swipe together, wishlists, a shared calendar, shared lists, To watch with Pick tonight and Places to go.",
    eyebrow: "The Us tab",
    h1: "Everything that's yours as a couple, in one tab.",
    lead: "Ourio's Us tab is a shared planner for two: a day counter and countdowns, a love streak, date night ideas you swipe together, wishlists with secret gifting, a shared calendar, and shared lists such as To watch, Groceries and Places to go. Both phones stay in sync.",
    hero: {
      src: shotUsTop,
      alt: "The Us tab: one month together, a love streak card, date night, wishlists and calendar",
      kind: "shot",
    },
    sections: [
      {
        id: "countdown",
        heading: "Days together and countdowns",
        body: [
          "Tell Ourio when your story started and the Us tab counts it: “Day 30 together”, with milestones like one month. Events in your calendar count down (“In 12 days”), and the Us Lock Screen widget can show either.",
        ],
      },
      {
        id: "calendar",
        heading: "Shared calendar",
        body: [
          "Birthdays, trips and concerts in one calendar you both see. Events can repeat every year and show up as countdowns.",
        ],
      },
      {
        id: "streak",
        heading: "Love streak",
        body: [
          "Your streak grows on every day either of you does something together: pet Mochi, send a note or a photo, swipe a date idea, share your mood. Missed a day? You can bring the flame back once a month.",
        ],
        picture: {
          src: streakDay,
          alt: "Mochi on a cushion beside a glowing flame",
          kind: "scene",
        },
      },
      {
        id: "date-night",
        heading: "Date night",
        body: [
          "Swipe through date ideas on your own phones. When you both love one, it lands in “You both loved these”. Filter the ideas, or tap Surprise us and let Mochi pick. Plan it for a day, even as a surprise with a hint, and get a reminder a day and an hour before. Rate it afterwards to mark it done.",
        ],
        picture: {
          src: datePlans,
          alt: "Mochi on a suitcase in front of a board of trip photos and a map",
          kind: "scene",
        },
      },
      {
        id: "wishlists",
        heading: "Wishlists with secret gifting",
        body: [
          "Each of you keeps a wishlist: paste a link or type a wish, mark what's most wanted, tie it to an occasion. A “What I love” card holds the things that are easy to forget: sizes, coffee order, flowers, sweets, allergies and “please don't”.",
          "On your partner's list, tap I'll get this. Your picks stay secret; they only see that someone is planning a surprise. “Got it ♥” closes the loop when the gift arrives.",
        ],
        picture: {
          src: shotPartnerWishes,
          alt: "A partner's wishlist with a most-wanted bracelet and a secret pick",
          kind: "shot",
        },
      },
      {
        id: "lists",
        heading: "Shared lists",
        body: [
          "Start a list together or use the ready ones: To watch, Groceries, Places to go, Places to eat, To read and a Bucket list. Tick items off as “Done together”. Groceries sorts by aisle and suggests what you often buy.",
        ],
        picture: { src: shotGroceries, alt: "A shared grocery list sorted by aisle", kind: "shot" },
      },
      {
        id: "pick-tonight",
        heading: "To watch and Pick tonight",
        body: [
          "Keep movies and shows you want to see together, with where to stream them. When you can't decide, open Pick tonight: you each swipe Not tonight, Seen it or Want to. When you both want the same title, it's a match and your partner gets a notification.",
        ],
      },
      {
        id: "places",
        heading: "Places to go",
        body: [
          "A world map of your travels: mark countries as Want to go or Been together, and watch the map fill in.",
        ],
      },
    ],
    questions: [
      {
        question: "Is Ourio a shared calendar and to-do app for couples?",
        answer:
          "Partly. The Us tab has a shared calendar, shared lists and wishlists that sync between your two iPhones, around the shared room and cat that make Ourio different.",
      },
      {
        question: "Can my partner see what I'm buying from their wishlist?",
        answer:
          "No. When you tap I'll get this, your partner only sees that someone is planning a surprise.",
      },
    ],
  },
  {
    slug: "love-streak",
    title: "Love streak for couples: a shared flame you keep lit · Ourio",
    description:
      "Ourio's love streak grows each day either partner does something together. Milestones at 3, 7, 14, 30, 50, 100, 200 and 365 days, and a missed day can be restored once a month.",
    eyebrow: "Love streak",
    h1: "A flame the two of you keep lit.",
    lead: "The love streak in Ourio counts the days in a row that either of you does something together: pet Mochi, send a note or a photo, swipe a date idea or share your mood. It has milestones at 3, 7, 14, 30, 50, 100, 200 and 365 days, and a broken streak can be restored once a month.",
    hero: {
      src: streakDay,
      alt: "Mochi on a knitted cushion next to a glowing coral flame",
      kind: "scene",
    },
    sections: [
      {
        id: "count",
        heading: "What counts",
        body: [
          "One of you is enough for the day: petting or caring for Mochi, a note, a Moment, a date night swipe or a mood. The card in the Us tab says “Do something together today to light the flame” until one of you does.",
        ],
        picture: {
          src: streakTasks,
          alt: "Four small icons: a paw, a speech bubble, a photo and a heart",
          kind: "scene",
        },
      },
      {
        id: "milestones",
        heading: "Milestones",
        body: [
          "Badges mark the streak at 3, 7, 14, 30, 50, 100, 200 and 365 days. Your best streak stays on the card.",
        ],
        picture: { src: streakTiers, alt: "A row of flames in six colors", kind: "scene" },
      },
      {
        id: "restore",
        heading: "Missed a day? Bring it back",
        body: [
          "If a streak of 3 days or more broke yesterday, the card offers “Restore N-day streak”. You can do it once every 30 days. Nothing else happens when you miss a day: Mochi doesn't suffer, and no one is told off.",
        ],
        picture: {
          src: streakBack,
          alt: "A hand relighting a flame while Mochi watches",
          kind: "scene",
        },
      },
    ],
    questions: [
      {
        question: "Do we both have to open the app every day?",
        answer: "No. One thing from either of you keeps the streak for both.",
      },
    ],
  },
  {
    slug: "games",
    title: "Couples games on iPhone: Who knows who and Draw & guess · Ourio",
    description:
      "Two free games for couples in Ourio: Who knows who, a daily five-question quiz about each other, and Draw & guess, where one draws a word and the other spells it from letter tiles.",
    eyebrow: "Games for two",
    h1: "Two small games, played across two phones.",
    lead: "Ourio has two free games for couples. Who knows who is a daily round of five questions about one of you; the other guesses, and the answers open together. Draw & guess has one of you draw a word and the other spell it from 12 letter tiles. Both earn coins.",
    hero: {
      src: whoKnowsCard,
      alt: "Mochi holding a question card next to a brass bell",
      kind: "scene",
    },
    sections: [
      {
        id: "who-knows-who",
        heading: "Who knows who",
        body: [
          "One round a day, five multiple-choice questions, all about one of you; the subject switches every day. The subject answers about themselves, the other guesses. Nobody sees anything until you have both finished, then the answers open one by one: Right! or Not quite.",
          "The weekly score resets on Monday. A right guess earns 2 coins and a finished round 10.",
        ],
        picture: {
          src: whoKnowsHost,
          alt: "Mochi holding a microphone like a quiz host",
          kind: "cutout",
        },
      },
      {
        id: "draw-and-guess",
        heading: "Draw & guess",
        body: [
          "One of you picks a word (up to 12 letters) and draws it. The other fills it in from 12 letter tiles, with as many tries as they like. Stuck? Mochi's hint first removes letters that aren't in the word, then reveals letters one at a time. Each hint costs 2 of the 10 coins a solve pays. Give up and the word is shown.",
          "Solve in a row to build a series; your best stays on the card. Words are in English.",
        ],
        picture: {
          src: drawGuessHint,
          alt: "Mochi pressing a letter tile with her paw",
          kind: "cutout",
        },
      },
    ],
    questions: [
      {
        question: "Do we need to play at the same time?",
        answer:
          "No. Both games are turn-based: each of you plays when you have a minute, and a notification tells the other it's their turn.",
      },
      {
        question: "Are the games free?",
        answer:
          "Yes. They're part of Ourio, with no purchase, and they earn coins for Mochi's room.",
      },
    ],
  },
  {
    slug: "shop-and-coins",
    title: "Coins and the shop: furnish your shared room · Ourio",
    description:
      "In Ourio every coin is earned by doing things together: caring for Mochi, notes, photos, lists, dates and games. Spend them on furniture, decor, inks and toys for the room you share.",
    eyebrow: "Shop and coins",
    h1: "Every coin is earned together.",
    lead: "Coins in Ourio belong to the couple, not to one of you, and they only come from what you do together: caring for Mochi, notes, photos, lists, dates and games. A new pair starts with 560 coins. Spend them in the shop on furniture, decor, inks and toys for your shared room.",
    hero: {
      src: whoKnowsTrophy,
      alt: "Mochi holding a golden trophy above her head",
      kind: "cutout",
    },
    sections: [
      {
        id: "earn",
        heading: "How you earn coins",
        body: [
          "Amounts can change as the app is tuned; daily caps keep it a cozy pace, not a grind.",
        ],
        picture: {
          src: whoKnowsHit,
          alt: "Mochi jumping for joy in a shower of gold confetti",
          kind: "cutout",
        },
        table: {
          caption: "Ways to earn coins in Ourio",
          head: ["What you do", "Coins"],
          rows: [
            ["A care action for Mochi", "1 (up to 10 a day)"],
            ["A note", "5"],
            ["A photo (Moment)", "10"],
            ["Tick off a list item", "5"],
            ["A date idea you both love", "10"],
            ["Rate a date you went on", "30"],
            ["Your partner gets something from your wishlist", "20"],
            ["Who knows who: a right guess / a round", "2 / 10"],
            ["Draw & guess: a solve", "4 to 10"],
          ],
        },
      },
      {
        id: "shop",
        heading: "What's in the shop",
        body: [
          "Furniture, decor and things for Mochi: the Cloud Armchair, Mushroom Lamp, Monstera, Little Bookcase, Woven Rug, Yarn Ball, Toy Mouse, Cat Tower, Sunset Print, Tea Table, Donut Bed and Paper Lantern. Today's tab has daily deals that change at midnight, a free gift once a day for both of you, bundles, inks, and collections that pay a bonus when you complete a set.",
          "One tap buys, with a few seconds to undo.",
        ],
      },
      {
        id: "money",
        heading: "Can you buy coins?",
        body: [
          "No. Ourio has no in-app purchases: nothing is for sale, and coins have no cash value.",
        ],
      },
    ],
    questions: [
      {
        question: "Are coins shared between partners?",
        answer:
          "Yes. Coins belong to the pair. If you unpair, each of you keeps the inks and pieces you bought and half of the coins.",
      },
    ],
  },
  {
    slug: "widgets-and-notifications",
    title: "Couples widget for iPhone: Lock Screen and Home Screen widgets · Ourio",
    description:
      "Ourio's iPhone widgets put your shared cat, your partner's latest drawing and note, days together and countdowns on your Home Screen and Lock Screen, plus Control Center buttons and a Safari share extension.",
    eyebrow: "Widgets and notifications",
    h1: "Your partner, on your Home Screen and Lock Screen.",
    lead: "Ourio has six widgets for iPhone: the room with Mochi, the cat with a smart block, a single block, an Us widget for the Lock Screen, your partner's latest note and their latest drawing. Some are interactive: set your mood or tick a list item without opening the app.",
    hero: {
      src: whoKnowsWaiting,
      alt: "Mochi sitting beside a phone propped on a gingham cushion",
      kind: "cutout",
    },
    sections: [
      {
        id: "widgets",
        heading: "The widgets",
        body: ["Add them from the Home Screen or Lock Screen like any iPhone widget."],
        table: {
          caption: "Ourio widgets, their sizes and what they show",
          head: ["Widget", "Sizes", "Shows"],
          rows: [
            ["Our Corner", "Large", "Mochi's room and two blocks you choose"],
            ["Ourio", "Medium", "Mochi and a smart block"],
            ["Block", "Small, medium", "Mood, a list, a date idea, a countdown or a photo"],
            [
              "Us",
              "Lock Screen: inline, circular, rectangular",
              "Days together, your next date, what your partner is up to",
            ],
            ["Note", "Lock Screen: rectangular, circular", "Your partner's latest note"],
            [
              "Drawing",
              "Small, medium, large, Lock Screen",
              "Their latest drawing, with “Tap to draw one back”",
            ],
          ],
        },
      },
      {
        id: "controls",
        heading: "Controls and widget buttons",
        body: [
          "Two Control Center and Lock Screen buttons: Pet Your Cat (she purrs, no need to open Ourio) and New Note. From widgets you can set your mood, tick a list item or ask Mochi to surprise you with a date idea.",
        ],
      },
      {
        id: "notifications",
        heading: "Notifications, only for your partner",
        body: [
          "Ourio notifies you when something comes from your partner, never to nag you back into the app:",
        ],
        bullets: [
          "a new drawing, photo or note;",
          "a heart on your photo;",
          "a Pick tonight match;",
          "your partner finished their part of Who knows who;",
          "a Draw & guess riddle, and when they solve it or give up;",
          "on your phone only: reminders a day and an hour before a planned date.",
        ],
      },
      {
        id: "share",
        heading: "Share to your wishlist from Safari",
        body: [
          "See something you'd love? Tap Share in Safari or another app and choose Ourio. “Add to my wishlist” opens with the link filled in; add a price, details or mark it most wanted.",
        ],
        picture: {
          src: shotShare,
          alt: "The Add to my wishlist sheet with AirPods filled in from a link",
          kind: "shot",
        },
      },
    ],
    questions: [
      {
        question: "Which iPhones do the widgets work on?",
        answer: "Any iPhone on iOS 18 or later.",
      },
    ],
  },
];

// Pictures the hub shows beside each feature; the feature pages use their own hero.
export const hubArt: Record<string, Picture> = {
  "room-and-mochi": { src: room, alt: "", kind: "scene" },
  "lock-screen-drawings": { src: drawGuessCard, alt: "", kind: "scene" },
  moments: { src: drawGuessSolved, alt: "", kind: "cutout" },
  us: { src: shotUsCards, alt: "", kind: "shot" },
  "love-streak": { src: streakDay, alt: "", kind: "scene" },
  games: { src: whoKnowsCard, alt: "", kind: "scene" },
  "shop-and-coins": { src: whoKnowsTrophy, alt: "", kind: "cutout" },
  "widgets-and-notifications": { src: whoKnowsWaiting, alt: "", kind: "cutout" },
};
