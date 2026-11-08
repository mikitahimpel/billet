import { Schema } from "effect";

const nonEmpty = Schema.String.check(Schema.isNonEmpty());

export const UserId = nonEmpty.pipe(Schema.brand("UserId"));
export type UserId = typeof UserId.Type;

/** One signed-in install of the app. The server assigns it at sign-in. */
export const DeviceId = nonEmpty.pipe(Schema.brand("DeviceId"));
export type DeviceId = typeof DeviceId.Type;

export const NoteId = nonEmpty.pipe(Schema.brand("NoteId"));
export type NoteId = typeof NoteId.Type;

/** 32 symbols, without 0, O, 1 and I, so that a code survives being read aloud or typed. */
export const inviteCodeAlphabet = "23456789ABCDEFGHJKLMNPQRSTUVWXYZ";
export const inviteCodeLength = 10;

/** A one-time pairing code: 50 random bits, uppercase. */
export const InviteCode = Schema.String.check(Schema.isPattern(/^[2-9A-HJ-NP-Z]{10}$/)).pipe(
  Schema.brand("InviteCode"),
);
export type InviteCode = typeof InviteCode.Type;

/** 26 symbols of the invite alphabet: 130 random bits, too many to guess or enumerate. */
export const reviewCodeLength = 26;

/**
 * The App Review pair's code (docs/app-review.md): reusable while it is live, set from the admin
 * only, and each claim pairs the claimer with the reserved review partner.
 */
export const ReviewCode = Schema.String.check(Schema.isPattern(/^[2-9A-HJ-NP-Z]{26}$/)).pipe(
  Schema.brand("ReviewCode"),
);
export type ReviewCode = typeof ReviewCode.Type;

/**
 * A UUID the client makes once per note and repeats on every retry of the same send. The room
 * remembers it with the note, for as long as it keeps the note.
 */
export const IdempotencyKey = Schema.String.check(
  Schema.isPattern(/^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$/),
).pipe(Schema.brand("IdempotencyKey"));
export type IdempotencyKey = typeof IdempotencyKey.Type;

/** Key of a note image in the private R2 bucket. */
export const MediaKey = nonEmpty.pipe(Schema.brand("MediaKey"));
export type MediaKey = typeof MediaKey.Type;

/** Milliseconds since the Unix epoch. */
export const EpochMillis = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));
export type EpochMillis = typeof EpochMillis.Type;
