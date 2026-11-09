import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { lazy, Suspense, useCallback, useEffect, useState } from "react";

const Diorama = lazy(() => import("./diorama").then((module) => ({ default: module.Diorama })));

type Heart = { id: number; x: number; y: number; drift: number };

export function HeroStage({
  portrait,
  storyId,
  posterId,
}: {
  portrait: string;
  storyId: string;
  // A still of the room the page shows until the scene is up; faded out once it is.
  posterId: string;
}) {
  const reduce = useReducedMotion() ?? false;
  const [purrs, setPurrs] = useState(0);
  const [ready, setReady] = useState(false);
  const [hearts, setHearts] = useState<Heart[]>([]);

  // The scene is 3.5 MB of script and keeps the main thread busy while it starts. The page shows a still of the room
  // instead, and the scene loads on the visitor's first scroll, tap or key, or a few seconds after the page has loaded.
  const [start, setStart] = useState(false);
  useEffect(() => {
    const events = ["pointerdown", "touchstart", "wheel", "scroll", "keydown"] as const;
    let timer = 0;
    const go = () => setStart(true);
    const later = () => {
      timer = window.setTimeout(go, 3000);
    };
    for (const name of events) window.addEventListener(name, go, { once: true, passive: true });
    if (document.readyState === "complete") later();
    else window.addEventListener("load", later, { once: true });
    return () => {
      for (const name of events) window.removeEventListener(name, go);
      window.removeEventListener("load", later);
      window.clearTimeout(timer);
    };
  }, []);

  const onReady = useCallback(() => {
    setReady(true);
    document.getElementById(posterId)?.classList.add("opacity-0");
  }, [posterId]);
  const onPet = useCallback(
    (anchor: { x: number; y: number }) => {
      setPurrs((n) => n + 1);
      if (reduce) return;
      const born = Array.from({ length: 5 }, (_, i) => ({
        id: performance.now() + i,
        x: anchor.x + (i - 2) * 12,
        y: anchor.y - 30,
        drift: (Math.random() - 0.5) * 70,
      }));
      setHearts((all) => [...all.slice(-15), ...born]);
    },
    [reduce],
  );

  return (
    <div className="relative h-full w-full touch-pan-y select-none">
      <motion.div
        className="absolute inset-0"
        initial={{ opacity: 0, scale: 0.94 }}
        animate={ready ? { opacity: 1, scale: 1 } : {}}
        transition={{ duration: 1.2, ease: [0.16, 1, 0.3, 1] }}
      >
        {start && (
          <Suspense fallback={null}>
            <Diorama storyId={storyId} reduceMotion={reduce} onPet={onPet} onReady={onReady} />
          </Suspense>
        )}
      </motion.div>

      {hearts.map((heart) => (
        <motion.span
          key={heart.id}
          aria-hidden
          className="pointer-events-none absolute -translate-x-1/2 text-[24px] text-light drop-shadow-[0_0_12px_var(--color-ember)]"
          style={{ left: heart.x, top: heart.y }}
          initial={{ opacity: 0, y: 0, x: 0, scale: 0.5 }}
          animate={{ opacity: [0, 1, 0], y: -150, x: heart.drift, scale: 1.15 }}
          transition={{ duration: 1.7, ease: "easeOut" }}
          onAnimationComplete={() => setHearts((all) => all.filter((h) => h.id !== heart.id))}
        >
          ♥
        </motion.span>
      ))}

      <AnimatePresence>
        {purrs > 0 && (
          <motion.div
            key={purrs}
            className="pointer-events-none absolute top-20 right-4 left-4 mx-auto max-w-[340px] rounded-[22px] border border-paper/10 bg-plate/80 p-3 shadow-2xl backdrop-blur-xl md:top-24 md:right-8 md:left-auto"
            initial={reduce ? { opacity: 0 } : { opacity: 0, y: -24, scale: 0.96 }}
            animate={{ opacity: 1, y: 0, scale: 1 }}
            exit={{ opacity: 0, y: -12 }}
            transition={{ duration: 0.45, ease: [0.16, 1, 0.3, 1] }}
            aria-live="polite"
          >
            <div className="flex items-center gap-3">
              <img
                src={portrait}
                alt=""
                width={40}
                height={40}
                className="size-10 rounded-[10px] bg-raised"
              />
              <div className="min-w-0 flex-1">
                <div className="flex justify-between text-[12px] text-muted">
                  <span className="font-semibold tracking-[0.06em] uppercase">Ourio</span>
                  <span>now</span>
                </div>
                <p className="text-[14px] leading-snug text-paper">
                  {purrs === 1
                    ? "Mochi purred. Your partner just felt it."
                    : `Purr #${purrs} on your partner's lock screen.`}
                </p>
              </div>
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
