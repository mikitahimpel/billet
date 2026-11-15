// The shop pieces on the home page's set and the Shop pages, pre-sized as 300 and 600 px WebPs in src/assets/props.
const files = import.meta.glob<string>("../assets/props/*.webp", {
  eager: true,
  query: "?url",
  import: "default",
});

function prop(name: string): string {
  const url = files[`../assets/props/${name}`];
  if (url === undefined) {
    throw new Error(`No prop named ${name} in src/assets/props`);
  }
  return url;
}

// Names and blurbs are the shop's own (packages/ios/features/Sources/FeatureShop/Shop.swift). The box is the
// piece's measured outline in its 1024 px image (x, y, width, height), which its glow and floor light centre on.
export const shopItems = [
  {
    key: "armchair",
    name: "Cloud Armchair",
    blurb: "Big enough for two and a cat who insists.",
    box: [186, 208, 754, 668],
  },
  {
    key: "lamp",
    name: "Mushroom Lamp",
    blurb: "Warm glow for late-night talks.",
    box: [284, 222, 598, 602],
  },
  { key: "teatable", name: "Tea Table", blurb: "Two cups, always.", box: [258, 296, 614, 534] },
  {
    key: "donutbed",
    name: "Donut Bed",
    blurb: "Sprinkles included, calories not.",
    box: [222, 354, 612, 376],
  },
  {
    key: "bookcase",
    name: "Little Bookcase",
    blurb: "Room for both your favourite stories.",
    box: [266, 204, 624, 692],
  },
  {
    key: "monstera",
    name: "Monstera",
    blurb: "Grows a new leaf every week you visit.",
    box: [286, 168, 588, 664],
  },
  {
    key: "yarn",
    name: "Yarn Ball",
    blurb: "Mochi's favourite thing to unravel.",
    box: [268, 220, 458, 634],
  },
  {
    key: "lantern",
    name: "Paper Lantern",
    blurb: "Hangs by the window and hums with light.",
    box: [354, 180, 402, 660],
  },
].map((item) => {
  const [bx, by, bw, bh] = item.box;
  return {
    ...item,
    small: prop(`Item_${item.key}-300.webp`),
    large: prop(`Item_${item.key}-600.webp`),
    style: `--bx: ${bx}; --by: ${by}; --bw: ${bw}; --bh: ${bh}`,
  };
});
