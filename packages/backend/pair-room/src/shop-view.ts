import { freeInk } from "@billet/contracts-domain/inks";
import { starterItems } from "@billet/contracts-domain/shop";
import type { ShopResponse } from "@billet/contracts-http-api/shop";
import type { RoomState } from "./room-state.ts";

/** What the pair has, as `GET /v1/shop` answers it. A room not opened yet has only the free things. */
export const shopOf = (state: RoomState): ShopResponse => {
  switch (state._tag) {
    case "Vacant":
      return {
        balance: 0,
        inks: [freeInk],
        items: [...starterItems],
        wishlist: [],
        bonuses: [],
        layout: [],
        stowed: [],
      };
    case "Active":
      return {
        balance: state.wallet.balance,
        inks: [freeInk, ...state.inks.filter((ink) => ink !== freeInk)],
        items: [...starterItems, ...state.items],
        wishlist: state.wishlist,
        ...(state.giftDay === undefined ? {} : { giftDay: state.giftDay }),
        bonuses: state.bonuses,
        layout: state.layout,
        stowed: state.stowed,
      };
  }
};
