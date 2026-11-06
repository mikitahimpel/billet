import { Effect, Layer } from "effect";
import { TitleNotFound } from "./titles-error.ts";
import { Tmdb } from "./tmdb.ts";

interface StubTitle {
  readonly kind: "movie" | "tv";
  readonly id: number;
  readonly title: string;
  readonly date: string;
  readonly poster: string;
  readonly rating: number;
  /** Minutes for a film, seasons for a show. */
  readonly length: number;
  readonly genres: ReadonlyArray<string>;
  readonly overview: string;
  readonly stream: ReadonlyArray<readonly [number, string]>;
}

const netflix = [8, "Netflix"] as const;
const appleTv = [350, "Apple TV+"] as const;
const prime = [9, "Amazon Prime Video"] as const;
const max = [1899, "Max"] as const;
const disney = [337, "Disney Plus"] as const;
const mubi = [11, "MUBI"] as const;

// Real TMDB ids and poster files, so the app draws real posters; the rest is made up.
const titles: ReadonlyArray<StubTitle> = [
  {
    kind: "movie",
    id: 329865,
    title: "Arrival",
    date: "2016-11-10",
    poster: "/evHCf9GuBDc42KvW9DRhY7pKx11.jpg",
    rating: 7.6,
    length: 116,
    genres: ["Drama", "Science Fiction"],
    overview: "A linguist is asked to talk with visitors who arrived in twelve ships.",
    stream: [netflix, prime],
  },
  {
    kind: "movie",
    id: 666277,
    title: "Past Lives",
    date: "2023-06-02",
    poster: "/gmTocN1iLLDyjEJir2CBnt2EhGE.jpg",
    rating: 7.7,
    length: 106,
    genres: ["Drama", "Romance"],
    overview: "Two childhood friends meet again, decades and an ocean later.",
    stream: [mubi],
  },
  {
    kind: "movie",
    id: 693134,
    title: "Dune: Part Two",
    date: "2024-02-27",
    poster: "/xdfO6EB9e59qZpzmHxezTdPfTxZ.jpg",
    rating: 8.1,
    length: 167,
    genres: ["Science Fiction", "Adventure"],
    overview: "Paul joins the desert people and heads for a war he foresaw.",
    stream: [max],
  },
  {
    kind: "tv",
    id: 95396,
    title: "Severance",
    date: "2022-02-17",
    poster: "/dqeaJ0aBH3Y5l9qDAhxowfDUYMF.jpg",
    rating: 8.4,
    length: 2,
    genres: ["Drama", "Mystery"],
    overview: "Office workers have their work memories split from the rest of their lives.",
    stream: [appleTv],
  },
  {
    kind: "tv",
    id: 136315,
    title: "The Bear",
    date: "2022-06-23",
    poster: "/eKfVzzEazSIjJMrw9ADa2x8ksLz.jpg",
    rating: 8.1,
    length: 4,
    genres: ["Comedy", "Drama"],
    overview: "A young chef comes home to run his family's sandwich shop.",
    stream: [disney],
  },
  {
    kind: "movie",
    id: 1064213,
    title: "Anora",
    date: "2024-10-14",
    poster: "/v1W88wf5jjMIh3XPluUjWGWHQ0S.jpg",
    rating: 7.1,
    length: 139,
    genres: ["Comedy", "Drama", "Romance"],
    overview: "A whirlwind wedding in Las Vegas meets a family that wants it undone.",
    stream: [],
  },
  {
    kind: "movie",
    id: 545611,
    title: "Everything Everywhere All at Once",
    date: "2022-03-24",
    poster: "/jBJJVeYcfEQPTn9nEL3kv4jgd2D.jpg",
    rating: 7.8,
    length: 140,
    genres: ["Action", "Adventure", "Science Fiction"],
    overview: "A laundromat owner learns she can borrow skills from her other lives.",
    stream: [prime],
  },
  {
    kind: "tv",
    id: 1396,
    title: "Breaking Bad",
    date: "2008-01-20",
    poster: "/anFx9aTOOYqgS3v7x3R84Kz67ly.jpg",
    rating: 8.9,
    length: 5,
    genres: ["Drama", "Crime"],
    overview: "A chemistry teacher turns to crime after a hard diagnosis.",
    stream: [netflix],
  },
];

const resultOf = (title: StubTitle) => ({
  media_type: title.kind,
  id: title.id,
  [title.kind === "movie" ? "title" : "name"]: title.title,
  [title.kind === "movie" ? "release_date" : "first_air_date"]: title.date,
  poster_path: title.poster,
  vote_average: title.rating,
  vote_count: 1000,
});

const providers = (stream: StubTitle["stream"]) =>
  stream.map(([id, name]) => ({ provider_id: id, provider_name: name }));

const detailsOf = (title: StubTitle) => ({
  ...resultOf(title),
  ...(title.kind === "movie" ? { runtime: title.length } : { number_of_seasons: title.length }),
  overview: title.overview,
  genres: title.genres.map((name, id) => ({ id, name })),
  "watch/providers": {
    results: Object.fromEntries(
      ["US", "GB", "PT", "DE", "SE", "PL"].map((country) => [
        country,
        {
          link: `https://www.themoviedb.org/${title.kind}/${title.id}/watch?locale=${country}`,
          flatrate: providers(title.stream),
          rent: providers([appleTv, prime]),
        },
      ]),
    ),
  },
});

/**
 * TMDB for a Worker with no key, such as `alchemy dev`: a few real films and shows, found by any
 * word of their title. No request leaves the Worker.
 */
export const TmdbStub: Layer.Layer<Tmdb> = Layer.succeed(
  Tmdb,
  Tmdb.of({
    get: (path, params) => {
      if (path === "/search/multi") {
        const words = (params["query"] ?? "").toLowerCase().split(" ").filter(Boolean);
        const found = titles.filter((title) =>
          words.every((word) => title.title.toLowerCase().includes(word)),
        );
        return Effect.succeed(JSON.stringify({ page: 1, results: found.map(resultOf) }));
      }
      const liked = titles.find(
        (candidate) => path === `/${candidate.kind}/${candidate.id}/recommendations`,
      );
      if (liked !== undefined) {
        const others = titles.filter((title) => title !== liked).map(resultOf);
        return Effect.succeed(JSON.stringify({ page: 1, results: others }));
      }
      const title = titles.find((candidate) => path === `/${candidate.kind}/${candidate.id}`);
      return title === undefined
        ? Effect.fail(new TitleNotFound())
        : Effect.succeed(JSON.stringify(detailsOf(title)));
    },
  }),
);
