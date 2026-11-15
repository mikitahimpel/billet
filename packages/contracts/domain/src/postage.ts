import { Schema } from "effect";
import type { Note, NoteSeal, NoteStamp } from "./note.ts";

/** A note's stamp or seal as the shop sells it: `stamp-<NoteStamp>` or `seal-<NoteSeal>`. Never
 * reused, like the stamps and seals themselves. */
export const PostageId = Schema.Literals([
  "stamp-heart",
  "stamp-moon",
  "stamp-bloom",
  "stamp-paw",
  "stamp-sun",
  "seal-rose",
  "seal-night",
  "seal-meadow",
  "seal-honey",
  "seal-plum",
]);
export type PostageId = typeof PostageId.Type;

/** In coins. Nothing is free: a note with neither stays free to send. See docs/economy.md. */
export const stampPrice = 30;
export const sealPrice = 45;

export interface Postage {
  readonly id: PostageId;
  /** In coins. */
  readonly price: number;
}

export const stampPostage = (stamp: NoteStamp): PostageId => `stamp-${stamp}`;
export const sealPostage = (seal: NoteSeal): PostageId => `seal-${seal}`;

/** Canonical: one partner's unlock is both partners', and it is kept for good. */
export const postage: ReadonlyArray<Postage> = PostageId.literals.map((id) => ({
  id,
  price: id.startsWith("stamp-") ? stampPrice : sealPrice,
}));

export const postageOf = (id: string): Postage | undefined =>
  postage.find((entry) => entry.id === id);

/** What the sender must own to send `note`: its stamp and its seal. A photo has neither. */
export const postageOn = (note: Note): ReadonlyArray<PostageId> => {
  switch (note._tag) {
    case "Text":
    case "Drawing":
      return [
        ...(note.stamp === undefined ? [] : [stampPostage(note.stamp)]),
        ...(note.seal === undefined ? [] : [sealPostage(note.seal)]),
      ];
    case "Photo":
      return [];
  }
};
