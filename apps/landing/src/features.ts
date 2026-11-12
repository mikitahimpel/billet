import type { ImageMetadata } from "astro";
import datePlans from "./assets/art/datescene-plans.webp";
import room from "./assets/art/shared-room.webp";
import shotLoves from "./assets/art/shot-after-loves.webp";
import shotMineAdded from "./assets/art/shot-after-mine-added.webp";
import shotPartnerWishes from "./assets/art/shot-after-partner.webp";
import shotGroceriesAdding from "./assets/art/shot-groceries-adding.webp";
import shotGroceries from "./assets/art/shot-groceries-list-top.webp";
import shotBucketList from "./assets/art/shot-list-item-icons.webp";
import shotOccasion from "./assets/art/shot-occasion.webp";
import shotShare from "./assets/art/shot-share-extension-result.webp";
import shotUsCards from "./assets/art/shot-us-cards-full-top.webp";
import shotUsLists from "./assets/art/shot-us-now-lists.webp";
import shotUsTop from "./assets/art/shot-us-now-top.webp";
import streakDay from "./assets/art/streak-day-lit.webp";
import streakTiers from "./assets/art/streak-flames-tiers.webp";
import streakTasks from "./assets/art/streak-task-icons.webp";
import type { CropName } from "./lib/crops";

// Every claim here is checked against the app (apps/ios, packages/ios/features, packages/backend, docs/). Things
// behind a release flag or not built (coin packs, a subscription, the drawing Live Activity, a streak freeze, the
// City room) stay out. Titles and H1s carry the words people search with.

// "scene": a full picture in a frame; "cutout": Mochi on a transparent ground; "shot": an app screenshot in a phone;
// "portrait": the small cutout of Mochi's head; "ui": a piece of the app's art, unframed.
// "crop": a close-up of the room render, never cropped; "slot": a phone whose screen waits for the app screenshot
// named `shot`, showing a close-up (or `src`) on the room's night meanwhile; "lock": their lock screen with one
// notification; "pair": your phone and their lock screen; "set": the shop window.
export type Picture =
  | { kind: "scene" | "cutout" | "shot" | "portrait" | "ui"; src: ImageMetadata; alt: string }
  | { kind: "crop"; crop: CropName; alt: string; fitHeight?: string; sizes?: string }
  | { kind: "slot"; shot: string; crop: CropName; alt: string }
  | { kind: "slot"; shot: string; src: ImageMetadata; alt: string }
  | { kind: "lock"; line: string }
  | { kind: "pair"; yours: "invite" | "room" }
  | { kind: "set" };

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
  // "How it works" in a few numbered steps, shown under the hero.
  steps?: { title: string; text: string }[];
  sections: FeatureSection[];
  // Extra block a page renders after its sections.
  gallery?: "dates";
  questions: { question: string; answer: string }[];
  // Feature slugs to suggest at the bottom; the rest of the list when absent.
  related?: string[];
};

export const featureList: Feature[] = [
  {
    slug: "room-and-mochi",
    title: "Virtual pet app for couples: raise a cat together · Ourio",
    description:
      "A couples app with a shared virtual pet: you and your partner raise one cat, Mochi, in one cozy room on two iPhones. Feed, play and pet her; the other sees it.",
    eyebrow: "Virtual pet for couples",
    h1: "A virtual pet you raise together, on two iPhones.",
    lead: "Ourio is a couples app with a shared pet: one cat, Mochi, in one cozy room that lives on both of your iPhones. Feed her, pour her water, play, brush or pet her, and your partner sees it. She has four needs, six coats and never gets sick when you're busy.",
    hero: {
      src: room,
      alt: "Mochi asleep on a donut bed in a warm, lamp-lit room with a round window",
      kind: "scene",
    },
    steps: [
      {
        title: "Choose her coat",
        text: "Grey tabby, ginger, cream, tuxedo, black or calico, and a name. Skip it and she stays Mochi.",
      },
      {
        title: "Pair your phones",
        text: "Your partner joins with your 10-character code. Now there's one cat, on two phones.",
      },
      {
        title: "Look after her together",
        text: "Whoever has a minute feeds, plays or pets her. The other sees it in the room and on their widget.",
      },
    ],
    sections: [
      {
        id: "care",
        heading: "Six ways to look after her",
        body: [
          "Tap Mochi to open her card: her level, how many days she has been with you two, and four bars, Full, Rested, Playful and Loved. Each care action is a small hands-on moment that takes over the screen:",
        ],
        bullets: [
          "Feed: tip the bag, scoop, or shake your phone to weigh kibble into her bowl on a kitchen scale.",
          "Water: hold to pour from a jug up to the line, then wipe up any spill.",
          "Play: drag a laser dot and watch her chase and pounce.",
          "Brush: stroke her back from head to tail until the fur flies.",
          "Pet: a quick stroke, also from a Control Center button without opening the app.",
          "Treat: a little extra, bought with coins.",
        ],
        picture: {
          kind: "crop",
          crop: "mochi",
          alt: "Mochi, a grey tabby kitten, in her donut bed",
          fitHeight: "8.75rem",
          sizes: "220px",
        },
      },
      {
        id: "gentle",
        heading: "A pet that never makes you feel guilty",
        body: [
          "Most virtual pets punish you for a busy week. Mochi doesn't. Her needs go down slowly, the wording stays kind and nothing ever turns red. She never gets sick, runs away or dies. Care is a way to say “I'm thinking of you”, not a chore list.",
        ],
      },
      {
        id: "mood",
        heading: "Say how you feel, without a conversation",
        body: [
          "“How are you?” lets each of you pick a mood (happy, sleepy, missing you or busy) and add a few words. Your partner sees it in the room and on their widget, with no thread to answer.",
        ],
      },
      {
        id: "furnish",
        heading: "Furnish the room together",
        body: [
          "Coins you earn together buy furniture, decor and toys: a Cloud Armchair, a Mushroom Lamp, a Donut Bed, a Cat Tower. Place a piece and it appears on both phones; preview it in 3D first, and keep extras in your closet.",
        ],
        picture: { kind: "set" },
      },
    ],
    questions: [
      {
        question: "Is there a couples app where you take care of a pet together?",
        answer:
          "Yes. In Ourio you and your partner share one cat, Mochi, on two iPhones. Either of you can feed, water, play with, brush or pet her, and the other sees it.",
      },
      {
        question: "Can Mochi get sick, run away or die?",
        answer:
          "No. Her needs go down slowly and the wording stays gentle. A busy week never hurts her.",
      },
      {
        question: "Does each of us get our own cat?",
        answer:
          "No. There is one cat and one room per couple, and both phones always show the same Mochi.",
      },
      {
        question: "Is the virtual pet free?",
        answer:
          "Yes. Ourio is free with no in-app purchases; even her treats and furniture are bought with coins you earn together.",
      },
    ],
    related: ["widgets-and-notifications", "shop-and-coins", "love-streak", "free-couples-app"],
  },
  {
    slug: "lock-screen-drawings",
    title: "Lock screen drawing app for couples: draw on your partner's iPhone",
    description:
      "Draw on a canvas shaped like your partner's Lock Screen. Ourio sends it to their iPhone with a notification and shows it in their Lock Screen widget.",
    eyebrow: "Lock Screen drawings",
    h1: "Draw on your partner's Lock Screen.",
    lead: "Ourio is a lock screen drawing app for couples. You draw on a canvas that shows your partner's Lock Screen, clock and wallpaper included. When you send it, they get a notification and the drawing appears in Ourio's Drawing widget on their Lock Screen or Home Screen. Seven ink colors, one free.",
    hero: {
      kind: "slot",
      shot: "lock-screen-drawings-1",
      crop: "paw",
      alt: "The paw picture on the wall of Mochi's room",
    },
    steps: [
      {
        title: "Tap + and choose Draw",
        text: "The canvas shows your partner's wallpaper, big clock and date.",
      },
      {
        title: "Draw with a finger",
        text: "Undo, erase, clear, change the ink or the wallpaper. If they're drawing too, you see their strokes live.",
      },
      {
        title: "Send it",
        text: "They get “A new drawing on your lock screen”, and the Drawing widget shows it.",
      },
    ],
    sections: [
      {
        id: "canvas",
        heading: "A canvas that is their Lock Screen",
        body: [
          "You see exactly where your doodle will sit next to the clock. Set the background to a paper color or to a photo from your Moments, then draw over it.",
          "If you both have the canvas open at the same time, you see each other's strokes as they happen, with “is drawing…” at the top. It's the closest thing to sitting next to each other with one sheet of paper.",
        ],
      },
      {
        id: "delivery",
        heading: "How it reaches their Lock Screen",
        body: [
          "iOS doesn't let any app change your wallpaper, so drawings arrive through a widget. Your partner adds Ourio's Drawing widget once: to the Lock Screen, or to the Home Screen in small, medium or large. Each new drawing updates it before the notification even shows, with “Tap to draw one back”.",
        ],
        picture: { kind: "lock", line: "A new drawing on your lock screen" },
      },
      {
        id: "inks",
        heading: "Seven inks",
        body: ["Graphite is free. The others belong to the two of you once bought with coins:"],
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
          "For something to keep, write a note. Type, or turn the pen on and draw; pick a paper color and add a stamp and seal. It goes up on Mochi's board in the room, your partner is notified, and the Note widget shows their latest note on your Lock Screen. Each note earns 5 coins.",
        ],
      },
    ],
    questions: [
      {
        question: "Can I draw on my partner's Lock Screen with an app?",
        answer:
          "Yes. With Ourio your drawing appears in the Drawing widget on their Lock Screen or Home Screen, with a notification. They add the widget once.",
      },
      {
        question: "Does the drawing change my partner's wallpaper?",
        answer:
          "No. iOS doesn't let apps change the wallpaper, so the drawing lives in Ourio's widget on top of it.",
      },
      {
        question: "Can we draw at the same time?",
        answer: "Yes. When you both have the canvas open, you see each other's strokes live.",
      },
      {
        question: "Does it work on Android?",
        answer:
          "No. Ourio is iPhone-only for now, so both of you need an iPhone on iOS 18 or later.",
      },
    ],
    related: ["widgets-and-notifications", "moments", "games", "long-distance-relationship-app"],
  },
  {
    slug: "moments",
    title: "Shared photo wall for couples: photos as polaroids · Ourio",
    description:
      "Send your partner a photo in Ourio and it lands on Mochi's wall as an instant-film polaroid with your caption. React with a heart, pin it or share it.",
    eyebrow: "Moments",
    h1: "Your photos, as polaroids on a shared wall.",
    lead: "Moments is Ourio's shared photo wall for couples. Add a photo of the two of you with a short caption and it goes up on Mochi's wall as a little polaroid on both phones. Your partner can react with a heart, and each Moment earns 10 coins.",
    hero: {
      kind: "slot",
      shot: "moments-1",
      crop: "shelf",
      alt: "The little bookshelf on the wall of Mochi's room",
    },
    steps: [
      { title: "Tap + and choose Moment", text: "Pick a photo of the two of you." },
      { title: "Write a little note", text: "A caption, if you want one." },
      {
        title: "It lands as a polaroid",
        text: "On Mochi's wall on both phones, with a notification for your partner.",
      },
    ],
    sections: [
      {
        id: "wall",
        heading: "Photos and board",
        body: [
          "The Moments tab switches between Photos, your polaroids, and Board, the notes and doodles you've pinned. Open a photo to react with a heart, pin it to the wall, edit the caption, share it as a polaroid or as the plain photo, or delete it.",
        ],
        picture: { kind: "crop", crop: "paw", alt: "The paw picture on the wall of Mochi's room" },
      },
      {
        id: "inbox",
        heading: "The Inbox: everything, by day",
        body: [
          "The Inbox in the header keeps what you two did, grouped by Today and Yesterday: who sent a drawing, who reacted to a photo, how you each feel, your streak and the games you played. It's a quiet record of your days, not a feed to scroll.",
        ],
      },
      {
        id: "private",
        heading: "Private by default",
        body: [
          "Photos are kept in your pair's private storage, reachable only by your two accounts. Ourio has no public profile, no followers and no ads, and never uses your photos to train AI.",
        ],
      },
    ],
    questions: [
      {
        question: "Who can see our Moments?",
        answer:
          "Only the two of you. There are no public profiles, and photos are never used for ads or AI training.",
      },
      {
        question: "Can I put one of our photos on my partner's Lock Screen?",
        answer:
          "Yes. Use it as the background of a Lock Screen drawing, or pick a photo for the Block widget on the Home Screen.",
      },
    ],
    related: ["lock-screen-drawings", "widgets-and-notifications", "us", "room-and-mochi"],
  },
  {
    slug: "us",
    title: "Couples planner app: dates, wishlists, lists and calendar · Ourio",
    description:
      "Ourio's Us tab is a planner for two: countdowns, a shared calendar, date night ideas you swipe together, wishlists with secret gifting, shared lists and more.",
    eyebrow: "The Us tab",
    h1: "A shared planner for the two of you.",
    lead: "Ourio's Us tab keeps everything that's yours as a couple in one place: a day counter and countdowns, a shared calendar, 150 date night ideas you swipe together, wishlists with secret gifting, shared lists like Groceries and To watch, Pick tonight for movie night, Places to go and your love streak.",
    hero: {
      src: shotUsTop,
      alt: "The Us tab: one month together, a love streak card, date night, wishlists and calendar",
      kind: "shot",
    },
    sections: [
      {
        id: "overview",
        heading: "What's in the Us tab",
        body: ["Each part has its own page with the details:"],
        table: {
          caption: "The parts of the Us tab",
          head: ["Part", "What it does"],
          rows: [
            [
              "Days together",
              "Counts from the day your story started, with milestones like one month",
            ],
            [
              "Calendar and countdowns",
              "Birthdays, trips and concerts, repeating every year, counting down",
            ],
            ["Date night", "150 ideas you swipe on your own phones; matches you both love"],
            ["Wishlists", "Your wishes and “What I love”; secret “I'll get this” for your partner"],
            [
              "Lists",
              "To watch, Groceries, Places to go, Places to eat, To read, Bucket list, your own",
            ],
            ["Pick tonight", "Swipe movies and shows together until you both want the same one"],
            ["Love streak", "A flame for every day either of you does something together"],
            ["Games", "Who knows who and Draw & guess"],
          ],
        },
        picture: {
          src: shotUsLists,
          alt: "The Us tab lists: groceries, Places to go with flags, places to eat and a bucket list",
          kind: "shot",
        },
      },
      {
        id: "sync",
        heading: "Always the same on both phones",
        body: [
          "Everything in the Us tab belongs to the pair. Tick a grocery item at the store and it's ticked on your partner's phone; add a birthday and it counts down for both of you. The Us widget brings days together and your next date to the Lock Screen.",
        ],
      },
    ],
    questions: [
      {
        question: "Is Ourio a shared calendar and to-do app for couples?",
        answer:
          "Yes, in part. The Us tab has a shared calendar, shared lists and wishlists that sync between two iPhones, alongside the shared room and cat that make Ourio different.",
      },
      {
        question: "Is the planner free?",
        answer:
          "Yes. Everything in the Us tab is free, with no subscription and no in-app purchases.",
      },
    ],
    related: [
      "date-night",
      "wishlists",
      "shared-lists",
      "movie-night",
      "calendar-and-countdown",
      "love-streak",
    ],
  },
  {
    slug: "date-night",
    title: "Date night ideas app for couples: swipe together, match, plan · Ourio",
    description:
      "150 date ideas you each swipe on your own iPhone. When you both love one, it's a match: plan it, get reminders, rate it. For home, out and long distance.",
    eyebrow: "Date night",
    h1: "Date night ideas you swipe together.",
    lead: "Date night in Ourio is a deck of 150 date ideas that you and your partner swipe on your own iPhones. When you both love an idea, it lands in “You both loved these”. Plan it for a day, get a reminder a day and an hour before, and rate it afterwards. 74 of the ideas are free.",
    hero: {
      kind: "slot",
      shot: "date-night-1",
      src: datePlans,
      alt: "Mochi on a suitcase in front of a board of trip photos and a map",
    },
    steps: [
      {
        title: "Swipe on your own",
        text: "Each of you goes through the ideas when you have a minute: love it or skip it.",
      },
      {
        title: "Match",
        text: "An idea you both love moves to “You both loved these”. Each match earns 10 coins.",
      },
      {
        title: "Plan it",
        text: "Pick a day, or make it a surprise with a hint. Reminders come a day and an hour before.",
      },
      { title: "Rate it", text: "After the date, rate it to mark it done. That earns 30 coins." },
    ],
    sections: [
      {
        id: "ideas",
        heading: "150 ideas, for every kind of evening",
        body: [
          "Every idea says where it happens, what it costs and how long it takes. Filter the deck, or tap Surprise us and let Mochi pick.",
        ],
        table: {
          caption: "Date ideas in Ourio by place and cost",
          head: ["", "Ideas"],
          rows: [
            ["At home", "63"],
            ["Out in town", "48"],
            ["Outdoors", "24"],
            ["Long distance, apart", "15"],
            ["Free", "74"],
            ["Cheap ($)", "61"],
            ["A little more ($$)", "15"],
            ["About an hour", "81"],
          ],
        },
      },
      {
        id: "long-distance",
        heading: "Dates for when you're apart",
        body: [
          "Fifteen ideas are made for long distance: a synced movie night with the call on, cooking the same recipe in two kitchens, a same-sky walk at sunset, an online quiz night, reading the same book, touring each other's rooms.",
        ],
      },
      {
        id: "surprise",
        heading: "Surprise dates",
        body: [
          "Planning something? Mark a date as a surprise and leave a hint. Your partner sees that something is coming, not what.",
        ],
      },
    ],
    gallery: "dates",
    questions: [
      {
        question: "Is there an app for couples to pick date ideas together?",
        answer:
          "Yes. In Ourio you each swipe through 150 date ideas on your own iPhone, and the ones you both love become matches you can plan.",
      },
      {
        question: "Are the date ideas free?",
        answer:
          "The app is free, and 74 of the 150 ideas cost nothing to do; 61 are cheap and 15 cost a bit more.",
      },
      {
        question: "Are there date ideas for long-distance couples?",
        answer:
          "Yes, 15 of them, like a synced movie night, cooking the same recipe or a same-sky walk.",
      },
    ],
    related: [
      "movie-night",
      "calendar-and-countdown",
      "wishlists",
      "long-distance-relationship-app",
    ],
  },
  {
    slug: "wishlists",
    title: "Shared wishlist app for couples with secret gifting · Ourio",
    description:
      "Keep gift ideas for each other: paste a link, mark what's most wanted, save sizes and allergies, and claim a gift secretly with “I'll get this”.",
    eyebrow: "Wishlists",
    h1: "A shared wishlist where gifts stay a surprise.",
    lead: "Ourio's wishlists are a shared wishlist app for couples. Each of you keeps a list: paste a link or type a wish, mark what's most wanted, and keep the details that are easy to forget, like sizes, coffee order and allergies. On your partner's list, “I'll get this” claims a gift secretly.",
    hero: {
      src: shotPartnerWishes,
      alt: "A partner's wishlist with a most-wanted bracelet and a secret pick",
      kind: "shot",
    },
    steps: [
      {
        title: "Add a wish",
        text: "Paste a link or type it. Add a price, details, an occasion, or mark it most wanted.",
      },
      {
        title: "Fill in “What I love”",
        text: "Sizes, flowers, coffee order, sweets, allergies and “please don't”.",
      },
      {
        title: "Gift in secret",
        text: "On their list, tap I'll get this. They only see that someone is planning a surprise.",
      },
    ],
    sections: [
      {
        id: "share",
        heading: "Add from Safari in two taps",
        body: [
          "See something you'd love? Tap Share in Safari or any app and choose Ourio. “Add to my wishlist” opens with the link and its picture filled in; add a price or details and save.",
        ],
        picture: {
          src: shotShare,
          alt: "The Add to my wishlist sheet with AirPods filled in from a link",
          kind: "shot",
        },
      },
      {
        id: "loves",
        heading: "“What I love”: the cheat sheet",
        body: [
          "A card for the things a partner should know without asking: sizes, flowers, coffee order, sweets, allergies and things you'd rather not get. Your partner reads it as their cheat sheet.",
        ],
        picture: {
          src: shotLoves,
          alt: "The What I love card with sizes, flowers, coffee order and allergies",
          kind: "shot",
        },
      },
      {
        id: "occasions",
        heading: "Occasions",
        body: ["Tie a wish to a birthday or an anniversary, so it comes up when it matters."],
        picture: {
          src: shotOccasion,
          alt: "A wish tied to a one-year anniversary in 365 days",
          kind: "shot",
        },
      },
      {
        id: "secret",
        heading: "How the secret works",
        body: [
          "When you tap I'll get this, the wish is yours to buy; your partner sees only “someone is planning a surprise”, never what. When it arrives, “Got it ♥” moves it to the gifted list, and the one who got the gift earns 20 coins for the pair.",
        ],
      },
    ],
    questions: [
      {
        question: "Can my partner see what I'm buying from their wishlist?",
        answer: "No. They only see that someone is planning a surprise.",
      },
      {
        question: "Can I add a wish from a website?",
        answer:
          "Yes. Share the page from Safari or another app to Ourio and the link is filled in.",
      },
      {
        question: "Is it only for two people?",
        answer:
          "Yes. Ourio pairs exactly two people, so your wishlists are seen by your partner and nobody else.",
      },
    ],
    related: ["calendar-and-countdown", "shared-lists", "date-night", "us"],
  },
  {
    slug: "shared-lists",
    title: "Shared to-do, grocery and bucket list app for couples · Ourio",
    description:
      "Shared lists that sync between two iPhones: groceries sorted by aisle, To watch, Places to go, a Bucket list and lists of your own. Tick them off together.",
    eyebrow: "Shared lists",
    h1: "Shared lists for two: groceries, bucket list and more.",
    lead: "Ourio has shared lists for couples that stay in sync on both iPhones: Groceries, To watch, Places to go, Places to eat, To read and a Bucket list, plus any list you start together. Tick something off and it's ticked for both of you; each ticked item earns 5 coins.",
    hero: { src: shotGroceries, alt: "A shared grocery list sorted by aisle", kind: "shot" },
    sections: [
      {
        id: "groceries",
        heading: "Groceries that sort themselves",
        body: [
          "Type an item and it lands in its aisle: fruit and veg, dairy, bakery, pantry, frozen, drinks, household, meat and fish, and one for Mochi. “You often buy” suggests the usuals. Bought items move down, ready to clear.",
        ],
        picture: {
          src: shotGroceriesAdding,
          alt: "Adding milk to the shared grocery list with suggestions",
          kind: "shot",
        },
      },
      {
        id: "bucket",
        heading: "A bucket list you finish together",
        body: [
          "Hot air balloon, northern lights, a road trip down the coast: add dreams with an icon each, and tick them off as “Done together” with the date.",
        ],
        picture: {
          src: shotBucketList,
          alt: "A shared bucket list with dreams done together",
          kind: "shot",
        },
      },
      {
        id: "places",
        heading: "Places to go, on a world map",
        body: [
          "Mark countries as Want to go or Been together and watch the map fill in: “Been to 7 of 195 together”. Places to eat keeps the restaurants you keep meaning to try.",
        ],
      },
      {
        id: "own",
        heading: "Lists of your own",
        body: [
          "Start a list together for anything: gifts, a trip packing list, recipes, chores. Both of you can add and tick.",
        ],
      },
    ],
    questions: [
      {
        question: "Is there a shared to-do list app for couples?",
        answer:
          "Yes. Ourio's lists sync between your two iPhones: groceries, a bucket list, places, movies and any list you start.",
      },
      {
        question: "Can I tick a list item from my widget?",
        answer:
          "Yes. The Block widget can show a list, and you can tick an item without opening the app.",
      },
    ],
    related: ["movie-night", "wishlists", "calendar-and-countdown", "us"],
  },
  {
    slug: "movie-night",
    title: "App to pick a movie together: Pick tonight for couples · Ourio",
    description:
      "Can't decide what to watch? You and your partner each swipe movies and shows in Ourio's Pick tonight. When you both want the same title, it's a match.",
    eyebrow: "Movie night",
    h1: "Pick a movie together, without the debate.",
    lead: "Pick tonight is Ourio's movie picker for couples. You each swipe through movies and shows on your own iPhone, Not tonight, Seen it or Want to, and when you both want the same title, it's a match and your partner gets a notification. A shared To watch list keeps the rest for later.",
    hero: {
      kind: "slot",
      shot: "movie-night-1",
      crop: "bed",
      alt: "Mochi in her donut bed at night, the lamp on",
    },
    steps: [
      { title: "Open Pick tonight", text: "From the To watch list in the Us tab." },
      { title: "Swipe", text: "Not tonight, Seen it or Want to, each on your own phone." },
      {
        title: "It's a match!",
        text: "The first title you both want wins, and your partner is told which one.",
      },
    ],
    sections: [
      {
        id: "to-watch",
        heading: "A shared To watch list",
        body: [
          "Keep the movies and shows you want to see together, with posters and where to stream them. Mark them “Watched together” when you're done. Suggestions are titles like the ones already on your list.",
        ],
      },
      {
        id: "privacy",
        heading: "Swipes that don't stick around",
        body: [
          "Pick tonight keeps only each partner's latest swipe on each title for 24 hours. Suggestions come from The Movie Database by title numbers only, never with your account.",
        ],
      },
    ],
    questions: [
      {
        question: "Is there an app for couples to choose a movie together?",
        answer:
          "Yes. In Ourio's Pick tonight you each swipe titles, and the first one you both want is a match.",
      },
      {
        question: "Can we use it when we're long distance?",
        answer:
          "Yes. Swipe apart, then press play at the same time; a synced movie night is one of the long-distance date ideas.",
      },
    ],
    related: ["date-night", "shared-lists", "us", "games"],
  },
  {
    slug: "calendar-and-countdown",
    title: "Couples calendar and countdown app: days together counter · Ourio",
    description:
      "Ourio counts your days together, keeps a shared calendar of birthdays, trips and anniversaries, and counts down to them on both iPhones and Lock Screens.",
    eyebrow: "Calendar and countdown",
    h1: "Days together, and every day you're counting down to.",
    lead: "Ourio counts your days together from the day your story started and keeps a shared calendar of birthdays, trips, concerts and anniversaries that can repeat every year. Each event counts down (“In 12 days”) on both iPhones, and the Us widget shows it on your Lock Screen.",
    hero: {
      src: shotUsCards,
      alt: "The Us tab with the day counter, date night, wishlists and calendar cards",
      kind: "shot",
    },
    sections: [
      {
        id: "counter",
        heading: "A relationship counter",
        body: [
          "Tell Ourio when your story started and the Us tab shows “Day 30 together”, with milestones like one month. The date stays on your phone; it isn't sent to our server.",
        ],
      },
      {
        id: "calendar",
        heading: "A shared calendar for the dates that matter",
        body: [
          "Add a birthday, a trip, a concert or an anniversary; set it to repeat every year. Both of you see it, and both of you get the countdown.",
        ],
      },
      {
        id: "widget",
        heading: "On your Lock Screen",
        body: [
          "The Us widget for the Lock Screen (inline, circular or rectangular) shows your days together or the next date. The Block widget on the Home Screen can show a countdown.",
        ],
        picture: {
          kind: "slot",
          shot: "calendar-1",
          crop: "window",
          alt: "The round window of Mochi's room at night, with the lamp on",
        },
      },
    ],
    questions: [
      {
        question: "Is there a couples app that counts days together?",
        answer:
          "Yes. Ourio counts from the day your story started and can show it on your Lock Screen with the Us widget.",
      },
      {
        question: "Can we count down to seeing each other?",
        answer: "Yes. Add the trip to the shared calendar and it counts down on both phones.",
      },
    ],
    related: [
      "widgets-and-notifications",
      "date-night",
      "wishlists",
      "long-distance-relationship-app",
    ],
  },
  {
    slug: "love-streak",
    title: "Couples streak: a shared flame you keep lit every day · Ourio",
    description:
      "Ourio's love streak grows each day either of you does something together. Milestones from 3 to 365 days; a broken streak can be restored once a month.",
    eyebrow: "Love streak",
    h1: "A streak the two of you keep lit.",
    lead: "The love streak in Ourio counts the days in a row that either of you does something together: pet Mochi, send a note or a photo, swipe a date idea or share your mood. It has milestones at 3, 7, 14, 30, 50, 100, 200 and 365 days, and a broken streak can be restored once a month.",
    hero: {
      kind: "slot",
      shot: "love-streak-1",
      src: streakDay,
      alt: "Mochi on a knitted cushion next to a glowing coral flame",
    },
    sections: [
      {
        id: "count",
        heading: "What counts",
        body: [
          "One of you is enough for the day: caring for Mochi, a note, a Moment, a date night swipe or a mood. The card in the Us tab says “Do something together today to light the flame” until one of you does.",
        ],
        picture: {
          kind: "ui",
          src: streakTasks,
          alt: "Four small icons: a paw, a speech bubble, a photo and a heart",
        },
      },
      {
        id: "milestones",
        heading: "Milestones",
        body: [
          "Badges mark the streak at 3, 7, 14, 30, 50, 100, 200 and 365 days. Your best streak stays on the card.",
        ],
        picture: { kind: "ui", src: streakTiers, alt: "A row of flames in six colors" },
      },
      {
        id: "restore",
        heading: "Missed a day? Bring it back",
        body: [
          "If a streak of 3 days or more broke yesterday, the card offers “Restore N-day streak”. You can do it once every 30 days. Nothing else happens when you miss a day: Mochi doesn't suffer, and no one is told off.",
        ],
        picture: {
          kind: "crop",
          crop: "candle",
          alt: "A candle on the dresser in Mochi's room, the lamp the only other light",
        },
      },
    ],
    questions: [
      {
        question: "Do we both have to open the app every day?",
        answer: "No. One thing from either of you keeps the streak for both.",
      },
      {
        question: "What happens if we break the streak?",
        answer: "If it was 3 days or longer, you can restore it the next day, once every 30 days.",
      },
    ],
    related: ["room-and-mochi", "games", "us", "date-night"],
  },
  {
    slug: "games",
    title: "Couples games and daily questions app for iPhone · Ourio",
    description:
      "Two free couples games: Who knows who, a daily 5-question quiz about your partner, and Draw & guess, where one draws a word and the other guesses it.",
    eyebrow: "Games for two",
    h1: "Couples games and daily questions, across two phones.",
    lead: "Ourio has two free games for couples. Who knows who is a daily round of five questions about one of you, from 150 questions; the other guesses, and the answers open together. Draw & guess has one of you draw a word and the other spell it from 12 letter tiles. Both are turn-based and earn coins.",
    hero: {
      kind: "slot",
      shot: "games-1",
      crop: "post",
      alt: "Mochi's scratching post with a toy on a string, beside her bowls",
    },
    sections: [
      {
        id: "who-knows-who",
        heading: "Who knows who: how well do you know your partner?",
        body: [
          "One round a day, five multiple-choice questions, all about one of you; the subject switches every day. The subject answers about themselves, the other guesses. Nobody sees anything until you have both finished, then the answers open one by one: Right! or Not quite.",
          "The 150 questions cover eight topics: dreams, food, habits, the past, quirks, music, money and the two of you. The weekly score resets on Monday. A right guess earns 2 coins and a finished round 10.",
        ],
        picture: { kind: "slot", shot: "games-2", crop: "mochi", alt: "Mochi in her donut bed" },
      },
      {
        id: "draw-and-guess",
        heading: "Draw & guess",
        body: [
          "One of you picks a word (up to 12 letters) and draws it. The other fills it in from 12 letter tiles, with as many tries as they like. Stuck? Mochi's hint first removes letters that aren't in the word, then reveals letters one at a time; each hint costs 2 of the 10 coins a solve pays. Give up and the word is shown.",
          "Solve in a row to build a series; your best stays on the card. Words are in English.",
        ],
        picture: {
          kind: "slot",
          shot: "games-3",
          crop: "paw",
          alt: "The paw picture on the wall of Mochi's room",
        },
      },
      {
        id: "turns",
        heading: "Turn-based, so it fits two schedules",
        body: [
          "Neither game needs you both online at once. Play your part when you have a minute; a notification tells your partner it's their turn: “Your partner drew you a riddle. 6 letters.”",
        ],
        picture: { kind: "lock", line: "Your partner drew you a riddle. 6 letters." },
      },
    ],
    questions: [
      {
        question: "Is there a free couples games app for iPhone?",
        answer:
          "Yes. Ourio's two games, Who knows who and Draw & guess, are free with no in-app purchases.",
      },
      {
        question: "Is there an app with daily questions for couples?",
        answer:
          "Yes. Who knows who asks five questions a day about one of you, from 150, and the other guesses.",
      },
      {
        question: "Do we need to play at the same time?",
        answer: "No. Both games are turn-based, with a notification when it's your turn.",
      },
      {
        question: "Do the games work for long-distance couples?",
        answer: "Yes. Everything happens over the internet between your two iPhones.",
      },
    ],
    related: [
      "love-streak",
      "room-and-mochi",
      "long-distance-relationship-app",
      "lock-screen-drawings",
    ],
  },
  {
    slug: "shop-and-coins",
    title: "Shop and coins: decorate your room with coins earned together · Ourio",
    description:
      "In Ourio every coin is earned together: caring for Mochi, notes, photos, dates and games. Spend them on furniture, decor, inks and toys. Nothing is for sale.",
    eyebrow: "Shop and coins",
    h1: "Every coin is earned together. Nothing is for sale.",
    lead: "Coins in Ourio belong to the couple and only come from what you do together: caring for Mochi, notes, photos, lists, dates and games. A new pair starts with 560 coins. Spend them on furniture, decor, inks and toys for your shared room. Ourio has no in-app purchases and no subscription.",
    hero: { kind: "set" },
    sections: [
      {
        id: "earn",
        heading: "How you earn coins",
        body: [
          "Daily caps keep it a cozy pace, not a grind. Amounts may be tuned as the app grows.",
        ],
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
        picture: { kind: "slot", shot: "shop-1", crop: "mochi", alt: "Mochi in her donut bed" },
      },
      {
        id: "shop",
        heading: "What's in the shop",
        body: [
          "Furniture, decor and things for Mochi: the Cloud Armchair, Mushroom Lamp, Monstera, Little Bookcase, Woven Rug, Yarn Ball, Toy Mouse, Cat Tower, Sunset Print, Tea Table, Donut Bed and Paper Lantern, plus seven inks for drawings.",
          "The Today tab has daily deals that change at midnight, a free gift once a day for both of you, bundles that cost less than buying one by one, and collections (Cozy Autumn and Mochi's Corner) that pay a bonus when you complete a set. One tap buys, with a few seconds to undo.",
        ],
      },
      {
        id: "money",
        heading: "No subscription, no in-app purchases",
        body: [
          "Ourio has nothing for sale. Coins have no cash value and can't be bought; everything in the shop is earned by the two of you.",
        ],
      },
    ],
    questions: [
      {
        question: "Is there a couples app with no subscription?",
        answer: "Yes. Ourio is free, with no subscription and no in-app purchases.",
      },
      {
        question: "Are coins shared between partners?",
        answer:
          "Yes. Coins belong to the pair. If you unpair, each of you keeps the inks and pieces you bought and half of the coins.",
      },
    ],
    related: ["room-and-mochi", "games", "lock-screen-drawings", "free-couples-app"],
  },
  {
    slug: "widgets-and-notifications",
    title: "Couple widget for iPhone: Lock Screen and Home Screen widgets · Ourio",
    description:
      "Couple widgets for iPhone: your shared cat, your partner's latest drawing and note, days together, mood and countdowns on your Home Screen and Lock Screen.",
    eyebrow: "Couple widgets",
    h1: "Couple widgets for your iPhone Home Screen and Lock Screen.",
    lead: "Ourio has six couple widgets for iPhone: the room with Mochi, the cat with a smart block, a single block, an Us widget for the Lock Screen, your partner's latest note and their latest drawing. Some are interactive: set your mood or tick a list item without opening the app.",
    hero: { kind: "lock", line: "They petted Mochi. She purred." },
    sections: [
      {
        id: "widgets",
        heading: "The six widgets",
        body: ["Add them like any iPhone widget; the Help page shows how."],
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
          "Tap Share in Safari or another app and choose Ourio. “Add to my wishlist” opens with the link filled in; add a price or details, or mark it most wanted.",
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
        question: "What is the best couple widget app for iPhone?",
        answer:
          "It depends on what you want on screen. Ourio's widgets show a shared cat, your partner's drawings and notes, mood, days together and countdowns, with no subscription.",
      },
      {
        question: "Which iPhones do the widgets work on?",
        answer: "Any iPhone on iOS 18 or later.",
      },
      {
        question: "Does Ourio have a distance widget?",
        answer: "No. Ourio doesn't use your location at all.",
      },
    ],
    related: ["lock-screen-drawings", "room-and-mochi", "calendar-and-countdown", "moments"],
  },
];

// The page for long-distance couples: a use case, not a feature, so it lives at the site root.
export const longDistance: Feature = {
  slug: "long-distance-relationship-app",
  title: "Long distance relationship app for iPhone: stay close daily · Ourio",
  description:
    "A free long distance relationship app for two iPhones: draw on each other's Lock Screen, raise a shared cat, play daily games and count down to your next visit.",
  eyebrow: "Long distance",
  h1: "A long distance relationship app for the days in between.",
  lead: "Ourio is a free iPhone app for long-distance couples. Instead of another chat, it gives you small things to do for each other across any distance: a drawing that lands on their Lock Screen, a shared cat to look after, a daily quiz, 15 long-distance date ideas and a countdown to your next visit.",
  hero: {
    kind: "crop",
    crop: "window-lamp",
    alt: "The round window of Mochi's room at night, the lamp on beside it",
  },
  steps: [
    { title: "Both install Ourio", text: "Free on iPhone, iOS 18 or later. No sign-up form." },
    {
      title: "Pair with one code",
      text: "One of you sends a 10-character code; the other types it in within 24 hours.",
    },
    {
      title: "Add the widgets",
      text: "Put the Drawing and Us widgets on your Lock Screens, so the other is there every time you look.",
    },
  ],
  sections: [
    {
      id: "presence",
      heading: "Feel each other's day, not just read it",
      body: [
        "Long distance runs on texts and calls, and both can start to feel like obligations. Ourio adds a quieter layer: you pet the cat, they see it; you draw a heart, it's on their Lock Screen when they wake up; they set their mood to “missing you”, and it's on your widget.",
      ],
      picture: { kind: "pair", yours: "room" },
    },
    {
      id: "what",
      heading: "What long-distance couples use most",
      body: ["Each links to its own page:"],
      table: {
        caption: "Ourio features for long-distance couples",
        head: ["Feature", "Why it helps apart"],
        rows: [
          ["Lock Screen drawings", "A doodle waiting on their Lock Screen; draw together live"],
          ["Shared cat, Mochi", "Something to look after together every day"],
          ["Who knows who", "Five questions a day to keep learning about each other"],
          ["Date night", "15 ideas for dates apart, like a synced movie night"],
          ["Calendar and countdown", "Count down to the next visit on both Lock Screens"],
          ["Love streak", "A flame you keep lit from two time zones"],
          ["Moments", "Photos as polaroids on a shared wall"],
        ],
      },
    },
    {
      id: "time-zones",
      heading: "Made for different time zones",
      body: [
        "Nothing in Ourio needs you both online at once. Games are turn-based, drawings wait in the widget, and the streak counts a day when either of you shows up.",
      ],
    },
    {
      id: "not",
      heading: "What Ourio doesn't do",
      body: [
        "There's no chat, no video calls and no location sharing; keep using the apps you already have for those. Ourio is iPhone-only for now, so both of you need an iPhone.",
      ],
    },
  ],
  questions: [
    {
      question: "What is a good app for long-distance couples?",
      answer:
        "Ourio is a free iPhone app made for staying close apart: Lock Screen drawings, a shared virtual pet, daily questions, long-distance date ideas and a countdown to your next visit.",
    },
    {
      question: "Does Ourio share our locations?",
      answer: "No. Ourio never asks for your location.",
    },
    {
      question: "Can we use it in different countries?",
      answer:
        "Yes, as long as both iPhones have internet. Ourio is in English and on the US App Store.",
    },
  ],
  related: [
    "lock-screen-drawings",
    "room-and-mochi",
    "games",
    "date-night",
    "calendar-and-countdown",
  ],
};

// For "free couples app" and "couples app with no subscription": a use case, at the site root.
export const freeApp: Feature = {
  slug: "free-couples-app",
  title: "Free couples app with no subscription and no in-app purchases · Ourio",
  description:
    "Ourio is a free couples app for iPhone: no subscription, no in-app purchases, no ads. Every feature is free for both partners, from the shared cat to widgets.",
  eyebrow: "Free, no subscription",
  h1: "A couples app that's free. All of it.",
  lead: "Ourio is a free couples app for iPhone: no subscription, no in-app purchases, no ads and no premium tier. Both partners get every feature, from the shared cat and Lock Screen drawings to daily questions, 150 date ideas and six widgets. Coins for the shop are earned together and can't be bought.",
  hero: { kind: "pair", yours: "invite" },
  sections: [
    {
      id: "whats-free",
      heading: "What you get for free",
      body: ["Everything in the app. Nothing below is locked behind a trial or a paywall:"],
      table: {
        caption: "Ourio features and what they cost",
        head: ["Feature", "Price"],
        rows: [
          ["Shared virtual pet, Mochi, and her room", "Free"],
          [
            "Lock Screen drawings and notes",
            "Free (one ink free, six more bought with earned coins)",
          ],
          ["Moments, the shared photo wall", "Free"],
          ["Who knows who, five daily questions", "Free"],
          ["Draw & guess", "Free"],
          ["Date night: 150 ideas you swipe together", "Free"],
          ["Wishlists, shared lists, Pick tonight", "Free"],
          ["Shared calendar, countdowns, days together", "Free"],
          ["Love streak, with a restore once a month", "Free"],
          ["Six widgets and two Control Center buttons", "Free"],
        ],
      },
    },
    {
      id: "coins",
      heading: "How the shop works without money",
      body: [
        "The shop sells furniture, decor, toys and inks for coins, and coins only come from doing things together: caring for Mochi, notes, photos, lists, dates and games. A new pair starts with 560 coins. Coins have no cash value and there is no way to buy them.",
      ],
    },
    {
      id: "no-ads",
      heading: "No ads, no data selling",
      body: [
        "Ourio shows no ads, has no third-party analytics or tracking, and never sells your data or uses your photos and drawings to train AI. The privacy policy lists exactly what is stored.",
      ],
    },
    {
      id: "both",
      heading: "Free for both of you",
      body: [
        "Many couples apps charge one partner for a plan that unlocks features for both. Ourio has nothing to unlock, so neither of you pays. You need two iPhones on iOS 18 or later.",
      ],
    },
  ],
  questions: [
    {
      question: "Is there a free couples app with no subscription?",
      answer: "Yes. Ourio is free on iPhone with no subscription, no in-app purchases and no ads.",
    },
    {
      question: "Does one of us have to pay for the other?",
      answer: "No. There is nothing to pay for: both partners get every feature for free.",
    },
    {
      question: "Are there ads in Ourio?",
      answer: "No. Ourio has no ads and no third-party tracking.",
    },
  ],
  related: ["shop-and-coins", "room-and-mochi", "games", "date-night", "widgets-and-notifications"],
};

// The hub's card for each feature: its picture and a longer line than the page's description.
export const hub: Record<string, { picture: Picture; text: string }> = {
  "room-and-mochi": {
    picture: { src: room, alt: "", kind: "scene" },
    text: "Ourio is a couples app with a shared virtual pet. You and your partner raise one cat, Mochi, in one cozy room on two iPhones: feed, water, play, brush and pet her, and the other sees it.",
  },
  "lock-screen-drawings": {
    picture: { kind: "slot", shot: "lock-screen-drawings-1", crop: "paw", alt: "" },
    text: "Draw on a canvas that looks like your partner's Lock Screen. Ourio sends it to their iPhone with a notification and shows it in the Drawing widget on their Lock Screen or Home Screen.",
  },
  moments: {
    picture: { kind: "slot", shot: "moments-1", crop: "shelf", alt: "" },
    text: "Send your partner a photo in Ourio and it lands on Mochi's wall as an instant-film polaroid with your caption. React with a heart, pin it, and share it as a polaroid.",
  },
  us: {
    picture: { src: shotUsCards, alt: "", kind: "shot" },
    text: "The Us tab in Ourio is a shared planner for two: days together and countdowns, a shared calendar, date night ideas you swipe together, wishlists with secret gifting, shared lists, movie night and a love streak.",
  },
  "date-night": {
    picture: { kind: "slot", shot: "date-night-1", src: datePlans, alt: "" },
    text: "Ourio's date night has 150 date ideas you each swipe on your own iPhone. When you both love one, it's a match; plan it, get reminders, and rate it. Ideas for home, out, outdoors and long distance.",
  },
  wishlists: {
    picture: { src: shotMineAdded, alt: "", kind: "shot" },
    text: "Ourio wishlists let partners keep gift ideas for each other: paste a link, mark what's most wanted, and keep sizes, coffee order and allergies. Claim a gift secretly with “I'll get this”. Add from Safari's share sheet.",
  },
  "shared-lists": {
    picture: { src: shotGroceries, alt: "", kind: "shot" },
    text: "Ourio's shared lists sync between two iPhones: Groceries sorted by aisle with suggestions, To watch, Places to go, Places to eat, To read, a Bucket list and lists of your own. Tick items off as done together.",
  },
  "movie-night": {
    picture: { kind: "slot", shot: "movie-night-1", crop: "bed", alt: "" },
    text: "Can't decide what to watch? In Ourio's Pick tonight you and your partner each swipe movies and shows: Not tonight, Seen it or Want to. When you both want the same title, it's a match. Plus a shared To watch list.",
  },
  "calendar-and-countdown": {
    picture: { src: shotUsTop, alt: "", kind: "shot" },
    text: "Ourio counts your days together, keeps a shared calendar of birthdays, trips and anniversaries that repeat every year, and counts down to them on both iPhones and in the Lock Screen widget.",
  },
  "love-streak": {
    picture: { kind: "slot", shot: "love-streak-1", src: streakDay, alt: "" },
    text: "Ourio's love streak grows each day either partner does something together. Milestones at 3, 7, 14, 30, 50, 100, 200 and 365 days, and a broken streak can be restored once a month.",
  },
  games: {
    picture: { kind: "slot", shot: "games-1", crop: "post", alt: "" },
    text: "Two free couples games in Ourio: Who knows who, a daily 5-question quiz about how well you know your partner, and Draw & guess, where one draws a word and the other spells it from letter tiles.",
  },
  "shop-and-coins": {
    picture: { kind: "set" },
    text: "In Ourio every coin is earned by doing things together: caring for Mochi, notes, photos, lists, dates and games. Spend them on furniture, decor, inks and toys. Nothing is for sale and there's no subscription.",
  },
  "widgets-and-notifications": {
    picture: { kind: "lock", line: "They petted Mochi. She purred." },
    text: "Ourio's couple widgets put your shared cat, your partner's latest drawing and note, days together, mood and countdowns on your iPhone Home Screen and Lock Screen, plus Control Center buttons.",
  },
};
