import { AnimatePresence, motion, useReducedMotion } from "motion/react";
import { useState } from "react";

type Moment = { id: number; line: string; note?: string };

const notes = ["Dinner's on me tonight", "Miss you already", "She's asleep on your hoodie"];

const actions = [
  { label: "Pet her", line: "You petted Mochi. She purred." },
  { label: "Feed her", line: "You fed Mochi. She's rested." },
  { label: "Leave a note", line: "You left a note on the wall." },
] as const;

export function TwoPhones({ mochi }: { mochi: string }) {
  const reduce = useReducedMotion();
  const [moment, setMoment] = useState<Moment>({ id: 0, line: "Mochi is napping by the lamp." });
  const [noteIndex, setNoteIndex] = useState(0);
  const [hop, setHop] = useState(0);

  function act(index: number) {
    const action = actions[index];
    if (!action) return;
    const isNote = action.label === "Leave a note";
    setMoment((last) => ({
      id: last.id + 1,
      line: action.line,
      note: isNote ? notes[noteIndex % notes.length] : last.note,
    }));
    if (isNote) setNoteIndex((n) => n + 1);
    setHop((n) => n + 1);
  }

  return (
    <div className="flex flex-col items-center gap-6 md:flex-row md:items-start md:justify-center md:gap-12">
      <Phone label="Your phone">
        <div className="flex h-full flex-col px-4 pt-12 pb-6">
          <p className="text-[12px] tracking-[0.06em] text-muted uppercase">Living room</p>
          <div className="relative mt-3 flex flex-1 items-end justify-center">
            <div className="lamp-glow absolute inset-x-0 top-2 bottom-0" aria-hidden />
            <motion.img
              key={hop}
              src={mochi}
              alt="Mochi, a grey tabby kitten with a red collar and a bell"
              width={176}
              height={176}
              className="relative w-44 [mask-image:linear-gradient(#000_75%,transparent)]"
              initial={reduce || hop === 0 ? false : { y: 0 }}
              animate={reduce ? undefined : { y: [0, -14, 0] }}
              transition={{ duration: 0.45, ease: "easeOut" }}
            />
          </div>
          <div className="mt-4 grid gap-2">
            {actions.map((action, index) => (
              <button
                key={action.label}
                type="button"
                onClick={() => act(index)}
                className={
                  index === 2
                    ? "min-h-11 rounded-full bg-gold font-semibold text-ink transition-transform active:scale-[0.97]"
                    : "min-h-11 rounded-full bg-raised-top font-medium text-paper transition-transform active:scale-[0.97]"
                }
              >
                {action.label}
              </button>
            ))}
          </div>
        </div>
      </Phone>

      <span aria-hidden className="text-2xl text-gold md:mt-64">
        <span className="md:hidden">↓</span>
        <span className="hidden md:inline">→</span>
      </span>

      <Phone label="Their lock screen">
        <div className="flex h-full flex-col items-center px-3 pt-12 pb-6">
          <p className="text-[14px] text-soft">Thursday 5 November</p>
          <p className="text-[64px] leading-none font-bold tracking-[-0.03em] text-paper">9:41</p>

          <div className="lit-panel relative mt-8 w-full p-3" aria-live="polite">
            <div className="mb-2 flex items-center justify-between">
              <span className="text-[12px] font-semibold tracking-[0.06em] text-soft uppercase">
                Ourio
              </span>
              <span className="rounded-[8px] bg-plate px-2 py-1 font-mono text-[12px] text-honey">
                Day 127
              </span>
            </div>
            <div className="flex items-center gap-3">
              <img src={mochi} alt="" width={56} height={56} className="size-14 shrink-0" />
              <div className="min-w-0 flex-1">
                <AnimatePresence mode="wait" initial={false}>
                  <motion.p
                    key={moment.id}
                    className="text-[14px] leading-snug text-paper"
                    initial={reduce ? { opacity: 0 } : { opacity: 0, y: 8 }}
                    animate={{ opacity: 1, y: 0 }}
                    exit={{ opacity: 0 }}
                    transition={{ duration: 0.3, ease: "easeOut" }}
                  >
                    {moment.line}
                  </motion.p>
                </AnimatePresence>
                <p className="mt-1 text-[12px] text-muted">{moment.id === 0 ? "earlier" : "now"}</p>
              </div>
            </div>
            <AnimatePresence>
              {moment.note && (
                <motion.div
                  key={moment.note}
                  className="relative mt-3 border-t border-dashed border-paper-turned/40 pt-3"
                  initial={reduce ? { opacity: 0 } : { opacity: 0, y: -12, rotate: -2 }}
                  animate={{ opacity: 1, y: 0, rotate: -1.5 }}
                  transition={{ duration: 0.5, ease: "easeOut" }}
                >
                  <p className="mx-auto w-fit rounded-[3px] bg-paper px-3 py-2 text-[14px] font-medium text-ink shadow-md">
                    {moment.note}
                  </p>
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        </div>
      </Phone>
    </div>
  );
}

function Phone({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <figure className="flex flex-col items-center gap-3">
      <div className="relative h-[520px] w-[264px] overflow-hidden rounded-[44px] border-[6px] border-plate bg-page-deep shadow-[0_40px_80px_-30px_var(--color-page-deep)]">
        <div
          className="absolute top-2 left-1/2 h-6 w-24 -translate-x-1/2 rounded-full bg-plate"
          aria-hidden
        />
        {children}
      </div>
      <figcaption className="text-[14px] text-muted">{label}</figcaption>
    </figure>
  );
}
