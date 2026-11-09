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
    label: "The Room and Mochi",
    summary:
      "A shared cozy room and a cat you both look after: pet, feed and play with her, pick her coat.",
    group: "features",
  },
  {
    path: "/features/lock-screen-drawings/",
    label: "Lock Screen drawings and notes",
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
    label: "The Us tab",
    summary:
      "Countdown, love streak, date night, wishlists, calendar, shared lists, To watch with Pick tonight and Places to go.",
    group: "features",
  },
  {
    path: "/features/love-streak/",
    label: "Love streak",
    summary:
      "A shared flame you light by doing something together each day; a broken streak can be restored once a month.",
    group: "features",
  },
  {
    path: "/features/games/",
    label: "Games for two",
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
    label: "Widgets, notifications and sharing",
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
