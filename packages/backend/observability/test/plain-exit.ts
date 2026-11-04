import { Cause, Exit } from "effect";

/**
 * The exit without the annotations that `Effect.fn` spans add to a failure (the span's stack
 * trace), so a test can compare it with `Exit.fail(error)`.
 */
export const plainExit = <A, E>(exit: Exit.Exit<A, E>): Exit.Exit<A, E> =>
  Exit.isSuccess(exit)
    ? exit
    : Exit.failCause(
        Cause.fromReasons(
          exit.cause.reasons.map((reason) => {
            switch (reason._tag) {
              case "Fail":
                return Cause.makeFailReason(reason.error);
              case "Die":
                return Cause.makeDieReason(reason.defect);
              case "Interrupt":
                return Cause.makeInterruptReason(reason.fiberId);
            }
          }),
        ),
      );
