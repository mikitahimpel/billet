import { Schema } from "effect";
import { DeviceId, UserId } from "@billet/contracts-domain/ids";

// Dates are ISO text and booleans 0 or 1. Only Better Auth writes these rows, so they exist for the
// schema drift test rather than for decoding.

const IsoDate = Schema.String.check(Schema.isNonEmpty());
const Flag = Schema.Int;

export const AuthUserRow = Schema.Struct({
  id: UserId,
  name: Schema.String,
  email: Schema.String,
  emailVerified: Flag,
  image: Schema.NullOr(Schema.String),
  isAnonymous: Schema.NullOr(Flag),
  createdAt: IsoDate,
  updatedAt: IsoDate,
});

/** `token` is a SHA-256 hex digest (hashed-session-tokens.ts). */
export const AuthSessionRow = Schema.Struct({
  id: Schema.String,
  token: Schema.String,
  userId: UserId,
  deviceId: DeviceId,
  expiresAt: IsoDate,
  ipAddress: Schema.NullOr(Schema.String),
  userAgent: Schema.NullOr(Schema.String),
  createdAt: IsoDate,
  updatedAt: IsoDate,
});

/** The token columns stay empty: the engine drops Apple's tokens before a row is written. */
export const AuthAccountRow = Schema.Struct({
  id: Schema.String,
  accountId: Schema.String,
  providerId: Schema.String,
  userId: UserId,
  accessToken: Schema.NullOr(Schema.String),
  refreshToken: Schema.NullOr(Schema.String),
  idToken: Schema.NullOr(Schema.String),
  accessTokenExpiresAt: Schema.NullOr(IsoDate),
  refreshTokenExpiresAt: Schema.NullOr(IsoDate),
  scope: Schema.NullOr(Schema.String),
  password: Schema.NullOr(Schema.String),
  createdAt: IsoDate,
  updatedAt: IsoDate,
});

export const AuthVerificationRow = Schema.Struct({
  id: Schema.String,
  identifier: Schema.String,
  value: Schema.String,
  expiresAt: IsoDate,
  createdAt: IsoDate,
  updatedAt: IsoDate,
});
