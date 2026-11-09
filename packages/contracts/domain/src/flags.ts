import { Schema } from "effect";

/** So a key reads the same in code, logs and the database. */
const slug = Schema.String.check(
  Schema.isPattern(/^[a-z][a-z0-9]*(-[a-z0-9]+)*$/),
  Schema.isMaxLength(40),
);

/** Never reused for a different question. */
export const ExperimentKey = slug.pipe(Schema.brand("ExperimentKey"));
export type ExperimentKey = typeof ExperimentKey.Type;

/** The build must already contain it. */
export const VariantId = slug.pipe(Schema.brand("VariantId"));
export type VariantId = typeof VariantId.Type;
