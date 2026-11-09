import { Schema } from "effect";
import { UtcOffsetSeconds } from "@billet/contracts-domain/cat";
import { ListCommand, SharedList } from "@billet/contracts-domain/list";

/** `GET /v1/lists`, and the answer to every change: the pair's lists, oldest first. */
export const ListsResponse = Schema.Struct({ lists: Schema.Array(SharedList) });
export type ListsResponse = typeof ListsResponse.Type;

/** A tick that earns counts against the cap on the local day: caller's, else cat's, else UTC. */
export const ChangeListRequest = Schema.Struct({
  change: ListCommand,
  utcOffsetSeconds: Schema.optionalKey(UtcOffsetSeconds),
});
export type ChangeListRequest = typeof ChangeListRequest.Type;
