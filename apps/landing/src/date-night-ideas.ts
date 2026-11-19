import catalog from "@billet/backend-dates/date-catalog.json" with { type: "json" };

// The ideas of Date night in the app, for the date idea pages. Ideas that name the cat ({cat}) only make sense in
// the app and stay out.

type Idea = (typeof catalog.ideas)[number];

export const updated = { iso: "2026-11-19", label: "November 19, 2026" };

const ideas = catalog.ideas.filter(
  (idea) => !idea.title.includes("{cat}") && !idea.pitch.includes("{cat}"),
);

const lengths: Record<Idea["time"], string> = {
  "1h": "About an hour",
  evening: "An evening",
  day: "A day",
};
const costs: Record<Idea["cost"], string> = { free: "Free", $: "$", $$: "$$" };

export const details = (idea: Idea) =>
  [lengths[idea.time], costs[idea.cost], idea.season === "any" ? null : `Best in ${idea.season}`]
    .filter(Boolean)
    .join(" · ");

export const homeIdeas = ideas.filter((idea) => idea.place === "home");

export const homeByCost = [
  {
    id: "free",
    heading: "Free date night ideas at home",
    intro: "Nothing to buy: what's already in the house, a phone and each other.",
    ideas: homeIdeas.filter((idea) => idea.cost === "free"),
  },
  {
    id: "cheap",
    heading: "Cheap date night ideas at home",
    intro: "A trip to the grocery or craft store, and the evening is set.",
    ideas: homeIdeas.filter((idea) => idea.cost === "$"),
  },
  {
    id: "splurge",
    heading: "Date nights at home worth a splurge",
    intro: "For an anniversary or a night you want to feel bigger.",
    ideas: homeIdeas.filter((idea) => idea.cost === "$$"),
  },
];

export const apartIdeas = ideas.filter((idea) => idea.place === "apart");

// Home ideas that work just as well with a video call between two homes.
const onCall = [2, 5, 9, 10, 13, 17, 21, 25, 97, 102, 103, 104, 105, 111, 113, 115, 137, 141, 144];
export const callIdeas = onCall.map((id) => ideas.find((idea) => idea.id === id)!);
