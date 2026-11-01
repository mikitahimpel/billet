import { Schema } from "effect";
import { InviteCode } from "@billet/contracts-domain/ids";
import { PairId } from "@billet/contracts-domain/pair-id";

export const CreateInviteResponse = Schema.Struct({ code: InviteCode });
export type CreateInviteResponse = typeof CreateInviteResponse.Type;

export const ClaimInviteRequest = Schema.Struct({ code: InviteCode });
export type ClaimInviteRequest = typeof ClaimInviteRequest.Type;

export const ClaimInviteResponse = Schema.Struct({ pairId: PairId });
export type ClaimInviteResponse = typeof ClaimInviteResponse.Type;
