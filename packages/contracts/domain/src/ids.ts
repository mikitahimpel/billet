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

/** Key of a note image in the private R2 bucket. */
export const MediaKey = nonEmpty.pipe(Schema.brand("MediaKey"));
export type MediaKey = typeof MediaKey.Type;

/** Milliseconds since the Unix epoch. */
export const EpochMillis = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));
export type EpochMillis = typeof EpochMillis.Type;
