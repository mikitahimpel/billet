import { Effect } from "effect";

/**
 * Spans each call `<name>.<member>`, for object literals where `Effect.fn` means a rewrite.
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
