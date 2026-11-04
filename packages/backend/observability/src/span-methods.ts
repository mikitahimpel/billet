import { Effect } from "effect";

/**
 * The same service with a span named `<name>.<member>` around each call: every method that
 * returns an Effect, and every member that is an Effect. Other members pass through. Use it on a
 * repository or adapter built as an object literal, where `Effect.fn` would mean rewriting each
 * method.
 */
export const spanMethods = <Service extends object>(name: string, service: Service): Service => {
  const traced: Record<string, unknown> = {};
  for (const [member, value] of Object.entries(service)) {
    const spanName = `${name}.${member}`;
    if (Effect.isEffect(value)) {
      traced[member] = Effect.withSpan(value, spanName);
    } else if (typeof value === "function") {
      traced[member] = (...args: ReadonlyArray<unknown>) => {
        const result: unknown = value.apply(service, args);
        return Effect.isEffect(result) ? Effect.withSpan(result, spanName) : result;
      };
    } else {
      traced[member] = value;
    }
  }
  return traced as Service;
};
