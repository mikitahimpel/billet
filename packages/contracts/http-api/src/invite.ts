import { Schema } from "effect";
import { EpochMillis, InviteCode } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";

/** `expiresAt` is when the server stops accepting `code`. */
export const CreateInviteResponse = Schema.Struct({ code: InviteCode, expiresAt: EpochMillis });
export type CreateInviteResponse = typeof CreateInviteResponse.Type;

export const ClaimInviteRequest = Schema.Struct({ code: InviteCode });
export type ClaimInviteRequest = typeof ClaimInviteRequest.Type;

export const ClaimInviteResponse = Schema.Struct({ pairId: PairId });
export type ClaimInviteResponse = typeof ClaimInviteResponse.Type;
