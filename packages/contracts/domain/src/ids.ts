import { Schema } from "effect";

const nonEmpty = Schema.String.check(Schema.isNonEmpty());

export const UserId = nonEmpty.pipe(Schema.brand("UserId"));
export type UserId = typeof UserId.Type;

/** One signed-in install of the app. The server assigns it at sign-in. */
export const DeviceId = nonEmpty.pipe(Schema.brand("DeviceId"));
export type DeviceId = typeof DeviceId.Type;

export const NoteId = nonEmpty.pipe(Schema.brand("NoteId"));
export type NoteId = typeof NoteId.Type;

/** Opaque invite code. The format is a pairing decision (#15), so only non-empty is enforced. */
export const InviteCode = nonEmpty.pipe(Schema.brand("InviteCode"));
export type InviteCode = typeof InviteCode.Type;

/** Key of a note image in the private R2 bucket. */
export const MediaKey = nonEmpty.pipe(Schema.brand("MediaKey"));
export type MediaKey = typeof MediaKey.Type;

/** Milliseconds since the Unix epoch. */
export const EpochMillis = Schema.Int.check(Schema.isGreaterThanOrEqualTo(0));
export type EpochMillis = typeof EpochMillis.Type;
