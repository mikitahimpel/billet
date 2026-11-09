// Every page of the site, once: the header, the footer, sitemap.xml and llms.txt all read this list.
export type SitePage = {
  path: string;
  // The name in navigation and in llms.txt.
  label: string;
  // One sentence for llms.txt and the footer's hub cards.
  summary: string;
  group: "product" | "features" | "help" | "legal";
};

export const features: SitePage[] = [
  {
    path: "/features/room-and-mochi/",
    label: "Virtual pet: Mochi and the room",
    summary:
      "A shared cozy room and a cat you both look after: pet, feed and play with her, pick her coat.",
    group: "features",
  },
  {
    path: "/features/lock-screen-drawings/",
    label: "Lock Screen drawings",
    summary:
      "Draw on a canvas that looks like your partner's Lock Screen, or pin a note; it lands in their widget.",
    group: "features",
  },
  {
    path: "/features/moments/",
    label: "Moments",
    summary:
      "Photos that arrive as instant-film polaroids with your caption, kept as your shared album.",
    group: "features",
  },
  {
    path: "/features/us/",
    label: "The Us tab: planner for two",
    summary:
      "Everything that is yours as a couple in one tab: dates, wishlists, lists, calendar and streak.",
    group: "features",
  },
  {
    path: "/features/date-night/",
    label: "Date night ideas",
    summary: "150 date ideas you each swipe; the ones you both love become plans, with reminders.",
    group: "features",
  },
  {
    path: "/features/wishlists/",
    label: "Shared wishlists",
    summary:
      "Wishlists for each other with secret “I'll get this” gifting and a “What I love” cheat sheet.",
    group: "features",
  },
  {
    path: "/features/shared-lists/",
    label: "Shared lists",
    summary:
      "Groceries sorted by aisle, a bucket list, places to go and lists of your own, in sync.",
    group: "features",
  },
  {
    path: "/features/movie-night/",
    label: "Movie night: Pick tonight",
    summary: "Swipe movies and shows together until you both want the same one.",
    group: "features",
  },
  {
    path: "/features/calendar-and-countdown/",
    label: "Calendar and countdown",
    summary: "Days together, a shared calendar and countdowns on both Lock Screens.",
    group: "features",
  },
  {
    path: "/features/love-streak/",
    label: "Couples streak",
    summary:
      "A shared flame you light by doing something together each day; a broken streak can be restored once a month.",
    group: "features",
  },
  {
    path: "/features/games/",
    label: "Couples games",
    summary:
      "Who knows who, a daily quiz about each other, and Draw & guess, a turn-based drawing game.",
    group: "features",
  },
  {
    path: "/features/shop-and-coins/",
    label: "Shop and coins",
    summary:
      "Furniture, decor, inks and toys for Mochi's room, bought with coins you earn together. No in-app purchases.",
    group: "features",
  },
  {
    path: "/features/widgets-and-notifications/",
    label: "Couple widgets",
    summary:
      "Six Home and Lock Screen widgets, Control Center buttons, quiet notifications and a Safari share extension.",
    group: "features",
  },
];

export const pages: SitePage[] = [
  {
    path: "/",
    label: "Home",
    summary: "What Ourio is: a free iPhone app for couples with a shared room and a cat.",
    group: "product",
  },
  {
    path: "/features/",
    label: "All features",
    summary: "Every feature of Ourio on one page.",
    group: "product",
  },
  ...features,
  {
    path: "/long-distance-relationship-app/",
    label: "For long-distance couples",
    summary:
      "How Ourio keeps two people close apart: Lock Screen drawings, a shared cat, daily games and countdowns.",
    group: "product",
  },
  {
    path: "/how-it-works/",
    label: "How pairing works",
    summary: "Install, share a 10-character code, and your two phones share one room.",
    group: "help",
  },
  {
    path: "/faq/",
    label: "FAQ",
    summary:
      "Price, devices, pairing, privacy, long distance and what happens when you miss a day.",
    group: "help",
  },
  {
    path: "/help/",
    label: "Help",
    summary: "Getting started, widgets, notifications, unpairing and deleting your account.",
    group: "help",
  },
  {
    path: "/support/",
    label: "Support",
    summary: "How to reach us, and fixes for the most common problems.",
    group: "help",
  },
  {
    path: "/privacy/",
    label: "Privacy policy",
    summary: "What Ourio stores, why, for how long, and how to delete it.",
    group: "legal",
  },
  {
    path: "/terms/",
    label: "Terms of use",
    summary: "The rules for using Ourio.",
    group: "legal",
  },
];

export const supportEmail = "gimpelllll@gmail.com";
