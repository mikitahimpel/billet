// A dozen of the 150 date ideas in packages/backend/dates/src/date-catalog.json, with the app's own art.
import type { ImageMetadata } from "astro";
import date1 from "./assets/dates/date-1.webp";
import date2 from "./assets/dates/date-2.webp";
import date10 from "./assets/dates/date-10.webp";
import date11 from "./assets/dates/date-11.webp";
import date73 from "./assets/dates/date-73.webp";
import date97 from "./assets/dates/date-97.webp";
import date31 from "./assets/dates/date-31.webp";
import date109 from "./assets/dates/date-109.webp";
import date121 from "./assets/dates/date-121.webp";
import date122 from "./assets/dates/date-122.webp";
import date127 from "./assets/dates/date-127.webp";
import date133 from "./assets/dates/date-133.webp";

export type DateIdea = {
  title: string;
  pitch: string;
  place: string;
  cost: string;
  art: ImageMetadata;
};

export const dateIdeas: DateIdea[] = [
  {
    title: "Blanket fort cinema",
    pitch: "Build a fort, pick a movie, phones stay outside",
    place: "At home",
    cost: "Free",
    art: date1,
  },
  {
    title: "Cook a country",
    pitch: "Pick a random country, cook one dish from it",
    place: "At home",
    cost: "$",
    art: date2,
  },
  {
    title: "Paint each other",
    pitch: "20 minutes, two canvases, portraits of each other",
    place: "At home",
    cost: "$",
    art: date10,
  },
  {
    title: "Recreate your first date",
    pitch: "Same food, same music, same topics, at home",
    place: "At home",
    cost: "$",
    art: date11,
  },
  {
    title: "Stargazing",
    pitch: "Blanket, star app, count shooting stars",
    place: "Outdoors",
    cost: "Free",
    art: date73,
  },
  {
    title: "Write love letters",
    pitch: "Real paper, sealed, open them in a year",
    place: "At home",
    cost: "Free",
    art: date97,
  },
  {
    title: "Coffee shop crawl",
    pitch: "Three caf\u00e9s, one drink each, crown the winner",
    place: "Out in town",
    cost: "$",
    art: date31,
  },
  {
    title: "Chalk art",
    pitch: "Draw a giant picture on the sidewalk together",
    place: "Out in town",
    cost: "$",
    art: date109,
  },
  {
    title: "Synced movie night",
    pitch: "Press play together, keep the call on",
    place: "Long distance",
    cost: "Free",
    art: date121,
  },
  {
    title: "Cook the same recipe",
    pitch: "Same dish, two kitchens, taste-compare live",
    place: "Long distance",
    cost: "$",
    art: date122,
  },
  {
    title: "Same-sky walk",
    pitch: "Both go out at sunset and share the view",
    place: "Long distance",
    cost: "Free",
    art: date127,
  },
  {
    title: "Quiz night online",
    pitch: "Join one live trivia together",
    place: "Long distance",
    cost: "Free",
    art: date133,
  },
];

// The cards fanned out like a hand under date night's steps, left to right.
export const fanCards: ImageMetadata[] = [date1, date10, date31, date97, date133];
