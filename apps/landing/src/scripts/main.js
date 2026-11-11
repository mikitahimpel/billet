// Each part of the page runs on its own: one that throws drops the page to its no-script state
// (the "js" class off <html>, so nothing stays hidden), and the parts after it still run.
(() => {
  const html = document.documentElement;
  html.classList.add("js-ready");
  const run = (name, part) => {
    try {
      part();
    } catch (error) {
      html.classList.remove("js");
      console.error(`main.js: ${name}`, error);
    }
  };

  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
  // The site stylesheet loads without blocking the first paint; parts that measure the page wait for it.
  const sheet = document.querySelector("link[data-sheet]");
  const styled = new Promise((resolve) => {
    if (!sheet || sheet.media !== "print") resolve();
    else sheet.addEventListener("load", resolve, { once: true });
  });
  const heartSvg =
    '<svg viewBox="0 0 24 22" aria-hidden="true"><path d="M12 21.5 10.3 20C4.4 14.6.5 11.1.5 6.8.5 3.3 3.2.6 6.7.6c2 0 3.9.9 5.3 2.4C13.4 1.5 15.3.6 17.3.6c3.5 0 6.2 2.7 6.2 6.2 0 4.3-3.9 7.8-9.8 13.2L12 21.5Z"/></svg>';

  function heartIn(layer, className, setup) {
    const el = document.createElement("span");
    el.className = className;
    el.innerHTML = heartSvg;
    setup?.(el);
    layer.append(el);
    el.addEventListener("animationend", () => el.remove());
    if (still) setTimeout(() => el.remove(), 1600);
  }

  // Set by the Mochi part, called by the story part; no-ops until then or if it fails.
  let startPurring = () => {};
  let stopPurring = () => {};

  /* ---------- fairy lights, from the render's bulb positions in :root ---------- */

  run("bulbs", () => {
    const bulbs = getComputedStyle(html)
      .getPropertyValue("--bulbs")
      .split(",")
      .map((pair) => pair.trim().split(/\s+/).map(Number))
      .filter((pair) => pair.length === 2 && pair.every(Number.isFinite));
    for (const layer of document.querySelectorAll(".bulbs")) {
      for (const [x, y] of bulbs) {
        const bulb = document.createElement("span");
        bulb.className = "bulb";
        bulb.style.left = `${x}%`;
        bulb.style.top = `${y}%`;
        // Periods that share no beat, so the string never pulses together.
        bulb.style.setProperty("--d", `${(2.6 + Math.random() * 4.8).toFixed(2)}s`);
        bulb.style.setProperty("--delay", `${(Math.random() * 3).toFixed(2)}s`);
        layer.append(bulb);
      }
    }
  });

  /* ---------- the phone menu closes on a tap outside it and on Escape ---------- */

  run("menu", () => {
    const menu = document.querySelector(".menu");
    if (!menu) return;
    document.addEventListener("click", (e) => {
      if (menu.open && !menu.contains(e.target)) menu.open = false;
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") menu.open = false;
    });
  });

  /* ---------- the animated Mochi, swapped in only once she has decoded ---------- */

  // The lamp comes on a beat after the room has decoded; the title keeps its own schedule.
  run("lights", () => {
    const room = document.getElementById("story-room");
    if (!room) return;
    const on = () => room.classList.add("lit");
    if (still) return on();
    const img = room.querySelector(".room-pic.clean img");
    const later = () => setTimeout(on, 600);
    if (img?.decode) img.decode().then(later, later);
    else later();
  });

  run("mochi loop", () => {
    const room = document.getElementById("story-room");
    const empty = room.querySelector(".room-pic.empty");
    const loop = room.querySelector(".mochi-loop");
    if (!empty || !loop) return;
    const drop = () => {
      room.classList.remove("has-loop");
      empty.remove();
      loop.parentElement.remove();
    };
    if (still) return drop();
    Promise.all([empty.querySelector("img").decode(), loop.decode()])
      .then(() => room.classList.add("has-loop"))
      .catch(drop);
  });

  /* ---------- Mochi: tap for a heart, drag to turn the room ---------- */

  run("mochi hearts", () => {
    const stage = document.getElementById("story-stage");
    const turn = stage.querySelector(".turn");
    const hearts = stage.querySelector(".hearts");
    const heart = () =>
      heartIn(hearts, "heart", (el) =>
        el.style.setProperty("--dx", `${(Math.random() - 0.5) * 5}%`),
      );

    let purr = 0;
    startPurring = () => {
      if (purr || still) return;
      heart();
      purr = setInterval(heart, 2600);
    };
    stopPurring = () => {
      clearInterval(purr);
      purr = 0;
    };

    let drag = null;
    stage.addEventListener("pointerdown", (e) => {
      drag = { x: e.clientX, y: e.clientY, moved: false, id: e.pointerId };
    });
    stage.addEventListener("pointermove", (e) => {
      if (!drag || e.pointerId !== drag.id) return;
      const dx = e.clientX - drag.x;
      const dy = e.clientY - drag.y;
      if (!drag.moved && Math.abs(dx) > 6 && Math.abs(dx) > Math.abs(dy)) {
        drag.moved = true;
        stage.classList.add("dragging");
        stage.setPointerCapture(e.pointerId);
      }
      if (drag.moved && !still) {
        turn.style.setProperty("--ry", `${Math.max(-12, Math.min(12, dx * 0.05))}deg`);
        turn.style.setProperty("--rx", `${Math.max(-4, Math.min(4, -dy * 0.02))}deg`);
      }
    });
    function release(e) {
      if (!drag || e.pointerId !== drag.id) return;
      if (!drag.moved && e.type === "pointerup") heart();
      drag = null;
      stage.classList.remove("dragging");
      turn.style.setProperty("--ry", "0deg");
      turn.style.setProperty("--rx", "0deg");
    }
    stage.addEventListener("pointerup", release);
    stage.addEventListener("pointercancel", release);
  });

  /* ---------- the pinned story ---------- */

  run("story", () => {
    const story = document.getElementById("story");
    const beats = [...story.querySelectorAll(".beat")];

    // Which beat shows at each stretch of the story's scroll.
    const beatAt = (p) => (p < 0.16 ? "0" : p < 0.43 ? "1" : p < 0.7 ? "2" : "3");

    let current = null;
    let ticking = false;

    function update() {
      ticking = false;
      const rect = story.getBoundingClientRect();
      const p = Math.min(1, Math.max(0, -rect.top / Math.max(1, rect.height - innerHeight)));
      const next = beatAt(p);
      if (next !== current) {
        current = next;
        story.dataset.beat = next;
        for (const beat of beats)
          beat.setAttribute("aria-hidden", String(beat.dataset.for !== next));
        if (next === "3") startPurring();
        else stopPurring();
      }
    }

    const schedule = () => {
      if (!ticking) {
        ticking = true;
        requestAnimationFrame(update);
      }
    };
    addEventListener("scroll", schedule, { passive: true });
    addEventListener("resize", schedule, { passive: true });
    update();
  });

  /* ---------- here / there: two phones and the thread between them ---------- */

  run("duo", () => {
    const duo = document.getElementById("duo");
    const svg = duo.querySelector(".thread");
    const base = svg.querySelector(".thread-base");
    const lit = svg.querySelector(".thread-lit");
    const grad = svg.querySelector("linearGradient");
    const spark = duo.querySelector(".spark");
    const acts = duo.querySelector(".acts");
    const notif = document.getElementById("notif");
    const line = document.getElementById("widget-line");
    const when = document.getElementById("widget-when");
    const note = document.getElementById("widget-note");
    const appHearts = duo.querySelector(".app-hearts");

    const notes = ["Dinner's on me tonight", "Miss you already", "She's asleep on your hoodie"];
    const lines = [
      "You petted Mochi. She purred.",
      "You fed Mochi. She's rested.",
      "You left a note on the wall.",
    ];
    let noteIndex = 0;

    // From the actions on your phone to the notification on theirs, in the duo's own pixels.
    function drawThread() {
      const box = duo.getBoundingClientRect();
      if (!box.width) return;
      const a = acts.getBoundingClientRect();
      const b = notif.getBoundingClientRect();
      let d;
      if (b.top > a.bottom) {
        // Stacked phones: leave from under your actions, bow out to the side, land on top of the notification.
        const sx = a.left + a.width / 2 - box.left;
        const sy = a.bottom - box.top;
        const ex = b.left + b.width / 2 - box.left;
        const ey = b.top - box.top;
        const bow = Math.min(120, box.width * 0.3);
        d = `M${sx} ${sy} C${sx + bow} ${sy + 80}, ${ex + bow} ${ey - 80}, ${ex} ${ey}`;
      } else {
        const sx = a.right - box.left;
        const sy = a.top + a.height / 2 - box.top;
        const ex = b.left - box.left;
        const ey = b.top + b.height / 2 - box.top;
        const span = ex - sx;
        d = `M${sx} ${sy} C${sx + span * 0.45} ${sy - 90}, ${ex - span * 0.45} ${ey - 90}, ${ex} ${ey}`;
      }
      svg.setAttribute("viewBox", `0 0 ${box.width} ${box.height}`);
      base.setAttribute("d", d);
      lit.setAttribute("d", d);
      const start = base.getPointAtLength(0);
      const finish = base.getPointAtLength(base.getTotalLength());
      grad.setAttribute("x1", start.x);
      grad.setAttribute("y1", start.y);
      grad.setAttribute("x2", finish.x);
      grad.setAttribute("y2", finish.y);
    }

    function send(done) {
      if (still) return done();
      const length = lit.getTotalLength();
      const t0 = performance.now();
      const duration = 950;
      lit.style.transition = "";
      lit.style.strokeDasharray = `${length}`;
      lit.style.opacity = "1";
      spark.style.opacity = "1";
      (function frame(now) {
        const t = Math.min(1, (now - t0) / duration);
        const eased = t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2;
        const point = lit.getPointAtLength(length * eased);
        lit.style.strokeDashoffset = `${length * (1 - eased)}`;
        spark.style.transform = `translate(${point.x}px, ${point.y}px)`;
        if (t < 1) return requestAnimationFrame(frame);
        spark.style.opacity = "0";
        lit.style.transition = "opacity 0.8s ease";
        lit.style.opacity = "0";
        done();
      })(t0);
    }

    function act(index) {
      heartIn(appHearts, "app-heart");
      send(() => {
        line.textContent = lines[index];
        when.textContent = "now";
        line.classList.remove("swap");
        notif.classList.remove("arrive");
        void notif.offsetWidth;
        line.classList.add("swap");
        notif.classList.add("arrive");
        if (index === 2) {
          note.hidden = false;
          const paper = document.createElement("p");
          paper.textContent = notes[noteIndex % notes.length];
          note.replaceChildren(paper);
          noteIndex += 1;
        }
      });
    }

    // The scene plays itself while in view, until someone taps.
    let auto = 0;
    let autoStep = 0;
    let touched = false;
    duo.querySelectorAll("[data-act]").forEach((button) => {
      button.addEventListener("click", () => {
        touched = true;
        clearInterval(auto);
        act(Number(button.dataset.act));
      });
    });

    styled.then(drawThread);
    addEventListener("resize", () => requestAnimationFrame(drawThread), { passive: true });
    document.fonts?.ready.then(drawThread);

    if (still || !("IntersectionObserver" in window)) return;
    new IntersectionObserver(
      ([entry]) => {
        clearInterval(auto);
        if (!entry.isIntersecting || touched) return;
        // The reveal has moved the phones by now; measure again before the first spark.
        setTimeout(drawThread, 800);
        auto = setInterval(() => {
          act(autoStep % 3);
          autoStep += 1;
        }, 4200);
      },
      { threshold: 0.4 },
    ).observe(duo);
  });

  /* ---------- shop: the camera finds one prop at a time ---------- */

  run("shop", () => {
    const set = document.getElementById("set");
    const props = [...set.querySelectorAll(".prop")];
    const rows = [...document.querySelectorAll(".roll li")];
    let focusIndex = -1;
    let focusTimer = 0;
    let holding = false;

    function focus(name) {
      set.classList.toggle("focusing", Boolean(name));
      for (const el of [...props, ...rows]) el.classList.toggle("lit", el.dataset.prop === name);
    }
    function nextFocus() {
      if (holding) return;
      focusIndex = (focusIndex + 1) % rows.length;
      focus(rows[focusIndex].dataset.prop);
    }
    for (const row of rows) {
      row.addEventListener("pointerenter", () => {
        holding = true;
        focus(row.dataset.prop);
      });
      row.addEventListener("pointerleave", () => {
        holding = false;
        focus(null);
      });
    }

    if (still || !("IntersectionObserver" in window)) return;
    new IntersectionObserver(
      ([entry]) => {
        clearInterval(focusTimer);
        if (!entry.isIntersecting) return focus(null);
        nextFocus();
        focusTimer = setInterval(nextFocus, 2600);
      },
      { threshold: 0.35 },
    ).observe(set);
  });

  /* ---------- reveals on scroll ---------- */

  run("reveal", () => {
    for (const group of document.querySelectorAll(".strip, .posters, .steps")) {
      [...group.children].forEach((child, n) => child.style.setProperty("--n", n));
    }
    const reveals = document.querySelectorAll(".reveal");
    if (!("IntersectionObserver" in window)) {
      reveals.forEach((el) => el.classList.add("in"));
      return;
    }
    const seen = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) {
            entry.target.classList.add("in");
            seen.unobserve(entry.target);
          }
        }
      },
      { rootMargin: "0px 0px 20% 0px" },
    );
    reveals.forEach((el) => seen.observe(el));
  });
})();
