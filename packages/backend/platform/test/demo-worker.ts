import { DemoRoom as LiveDemoRoom } from "../src/demo-room-durable-object.ts";
import { testNowOf } from "./test-now.ts";

// The demo tests run in their own Worker so they do not load Effect and Drizzle, which only the
// PairRoom tests need. Loading those dominated the cold start of the first test of a file.
/** DemoRoom at the test instant, so nothing it does depends on when the suite runs. */
export class DemoRoom extends LiveDemoRoom {
  protected override clock(): number {
    return testNowOf(this.env as { readonly TEST_NOW?: string });
  }
}

/** DemoRoom with a throwaway APNs key and a recording transport, so no request leaves the test. */
export class StubbedDemoRoom extends DemoRoom {
  protected override async apnsCredentials() {
    const pair = (await crypto.subtle.generateKey({ name: "ECDSA", namedCurve: "P-256" }, true, [
      "sign",
    ])) as CryptoKeyPair;
    const der = new Uint8Array(
      (await crypto.subtle.exportKey("pkcs8", pair.privateKey)) as ArrayBuffer,
    );
    const body = btoa(String.fromCharCode(...der));
    return {
      key: `-----BEGIN PRIVATE KEY-----
${body}
-----END PRIVATE KEY-----`,
      keyId: "TESTKEYID1",
    };
  }

  protected override apnsFetch = async (url: string, init: RequestInit) => {
    const calls = (await this.ctx.storage.get<unknown[]>("apnsCalls")) ?? [];
    const headers = Object.fromEntries(new Headers(init.headers).entries());
    await this.ctx.storage.put("apnsCalls", [...calls, { url, headers, body: String(init.body) }]);
    return new Response(null, { status: 200 });
  };
}

/** DemoRoom whose APNs request never completes, to prove an ack does not wait on it. */
export class HangingApnsRoom extends StubbedDemoRoom {
  protected override apnsFetch = (): Promise<Response> => new Promise(() => {});
}

/** StubbedDemoRoom on a clock the test sets, for the evening reminder. */
export class ClockedDemoRoom extends StubbedDemoRoom {
  private fixedNow: number | undefined;

  setNow(ms: number): void {
    this.fixedNow = ms;
  }

  protected override clock(): number {
    return this.fixedNow ?? super.clock();
  }
}

export default {
  fetch: () => new Response(null, { status: 404 }),
};
