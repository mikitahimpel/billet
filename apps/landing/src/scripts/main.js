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
  let notice = () => {};

  // A custom property written only when its text changes: each write restyles all under el.
  const written = new WeakMap();
  function setVar(el, name, value) {
    let last = written.get(el);
    if (!last) written.set(el, (last = new Map()));
    if (last.get(name) === value) return;
    last.set(name, value);
    el.style.setProperty(name, value);
  }
  function dropVar(el, name) {
    written.get(el)?.delete(name);
    el.style.removeProperty(name);
  }

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
        // Order along the string, left to right, for the lights-on run.
        bulb.style.setProperty("--k", String(layer.children.length));
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

  // The lights-on (global.css, "The lights coming on"): a short dark beat after the unlit room
  // decodes, capped so a slow network never holds the title back for long.
  run("lights", () => {
    const story = document.getElementById("story");
    const img = story?.querySelector(".room-pic.none img");
    if (!story) return;
    if (still) return story.classList.add("lamp-on", "lamp-settled");
    let started = false;
    const on = () => {
      if (started) return;
      started = true;
      story.classList.add("lamp-on");
      setTimeout(() => story.classList.add("lamp-settled"), 1300);
    };
    const afterDark = () => setTimeout(on, 400);
    if (img?.decode) img.decode().then(afterDark, afterDark);
    else afterDark();
    setTimeout(on, 1200);
  });

  // Mochi is the loop over the cat-less renders; if it can't play, the lit room with her in it
  // comes back once the lights are on (.no-loop).
  run("mochi loop", () => {
    const room = document.getElementById("story-room");
    const loop = room.querySelector(".mochi-loop");
    if (!loop) return;
    const drop = () => {
      room.classList.remove("has-loop");
      room.classList.add("no-loop");
      loop.parentElement.remove();
    };
    if (still) return drop();
    loop
      .decode()
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

    notice = () => {
      if (!still) heart();
    };

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

  /* ---------- the header: compact once the story has scrolled past ---------- */

  run("header", () => {
    // The story starts at the top of the page, so it stops intersecting only once scrolled past,
    // however the reader got there (a flick, a jump, an anchor). On a phone the story isn't pinned
    // and scrolls under the header, which is the bar after 24px.
    const header = document.getElementById("chrome");
    const story = document.getElementById("story");
    if (!header || !story || !("IntersectionObserver" in window))
      return header?.classList.add("compact");
    const phone = matchMedia("(max-width: 900px)");
    let inStory = true;
    const update = () => {
      const past = !phone.matches && story.getBoundingClientRect().bottom < innerHeight - 1;
      header.classList.toggle("compact", !inStory || past || (phone.matches && scrollY > 24));
    };
    new IntersectionObserver(([entry]) => {
      inStory = entry.isIntersecting;
      update();
    }).observe(story);
    addEventListener("scroll", update, { passive: true });
    phone.addEventListener("change", update);
  });

  /* ---------- the pinned story ---------- */

  // Wide screens: the story pins for 1.8 screens of scroll and its progress p (0 to 1) drives it
  // all, in proportion, with nothing on a timer or a threshold. Beat i holds from B[i] to B[i+1],
  // the boundaries halfway between the snap stops (p = 0, 1/3, 2/3, 1), so each stop shows one beat;
  // at each boundary b the outgoing beat fades over b - 0.07 to b + 0.01 and the incoming one over
  // b - 0.01 to b + 0.07, rising 16px into place (the outgoing one leaves 16px up). The room dims
  // to the lamp as beat 1 arrives and comes back as beat 2 does (--dim); beat 2's phones ride in
  // with its arrival (--ride); Mochi gives one heart when beat 3 is 0.9 in, again only after it
  // has gone below 0.5.
  //
  // Phones: no pin. The beats are in flow under the room; the room dims while it leaves, from
  // 0.15 H to 0.4 H of scroll (H: the room and beat 0, at least a screen tall), and the heart is
  // at --dim 0.8; the beat nearest the screen's middle is data-beat, and beat 3 purrs.
  run("story", () => {
    const story = document.getElementById("story");
    const beats = [...story.querySelectorAll(".beat")];
    const phone = matchMedia("(max-width: 900px)");
    const clamp01 = (x) => Math.min(1, Math.max(0, x));
    const B = [0, 1 / 6, 1 / 2, 5 / 6, 1];
    const arrived = (i, p) => (i === 0 ? 1 : clamp01((p - B[i] + 0.01) / 0.08));
    const staying = (i, p) =>
      i === beats.length - 1 ? 1 : 1 - clamp01((p - B[i + 1] + 0.07) / 0.08);

    let current = null;
    let ticking = false;
    let noticed = false;

    function pinned() {
      const rect = story.getBoundingClientRect();
      const travel = Math.max(1, rect.height - innerHeight);
      const p = clamp01(-rect.top / travel);
      // Leaving the pin: the beats and the room fade over the first 0.45 screen of the exit instead
      // of sliding out cut by the viewport and under the header.
      const exit = still ? 0 : clamp01((-rect.top - travel) / (0.45 * innerHeight));
      setVar(story, "--exit", exit.toFixed(3));
      let next = 0;
      let best = -1;
      beats.forEach((beat, i) => {
        const a = arrived(i, p);
        const s = staying(i, p);
        const v = Math.min(a, s) * (1 - exit);
        const y = still ? 0 : a < 1 ? 16 * (1 - a) : -16 * (1 - s);
        setVar(beat, "--v", v.toFixed(3));
        setVar(beat, "--y", y.toFixed(1));
        const hidden = String(v === 0);
        if (beat.getAttribute("aria-hidden") !== hidden) beat.setAttribute("aria-hidden", hidden);
        if (v > best) {
          best = v;
          next = i;
        }
      });
      setVar(story, "--dim", still ? "0" : (arrived(1, p) - arrived(2, p)).toFixed(3));
      setVar(story, "--ride", still ? "1" : arrived(2, p).toFixed(3));
      const cue = arrived(3, p);
      if (cue >= 0.9 && !noticed) {
        noticed = true;
        notice();
      } else if (cue < 0.5) noticed = false;
      return next;
    }

    function flowing() {
      const line = innerHeight / 2;
      let next = 0;
      let gap = Infinity;
      beats.forEach((beat, i) => {
        dropVar(beat, "--v");
        dropVar(beat, "--y");
        beat.removeAttribute("aria-hidden");
        const box = beat.getBoundingClientRect();
        const d = Math.abs(box.top + box.height / 2 - line);
        if (d < gap) {
          gap = d;
          next = i;
        }
      });
      const hero = beats[0].getBoundingClientRect().bottom + scrollY;
      const dim = clamp01((scrollY - 0.15 * hero) / Math.max(1, 0.25 * hero));
      if (!still) {
        setVar(story, "--dim", dim.toFixed(3));
        if (dim > 0.8 && !noticed) {
          noticed = true;
          notice();
        } else if (dim < 0.6) noticed = false;
      }
      return next;
    }

    function update() {
      ticking = false;
      const next = String(phone.matches ? flowing() : pinned());
      if (next !== current) {
        current = next;
        story.dataset.beat = next;
        if (next === "3" && phone.matches) startPurring();
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
      if (close.matches) return;
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

    // Under 900px the thread is hidden (global.css): the notification just arrives after a beat.
    const close = matchMedia("(max-width: 900px)");

    function send(done) {
      if (still) return done();
      if (close.matches) return setTimeout(done, 450);
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
    let first = 0;
    new IntersectionObserver(
      ([entry]) => {
        clearInterval(auto);
        clearTimeout(first);
        if (!entry.isIntersecting || touched) return;
        // The first pat soon after the phones come into view (the reveal has settled by then, so
        // measure the thread again first), then one every 4.2 s.
        first = setTimeout(() => {
          drawThread();
          act(autoStep % 3);
          autoStep += 1;
          auto = setInterval(() => {
            act(autoStep % 3);
            autoStep += 1;
          }, 4200);
        }, 600);
      },
      { threshold: 0.25 },
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

  // A fast scroll (more than 1.5 screens in the last 250 ms) sets html.fast until 500 ms after the
  // last scroll event; global.css drops the reveal fades meanwhile.
  run("fast", () => {
    const samples = [];
    let calm = 0;
    addEventListener(
      "scroll",
      () => {
        const now = performance.now();
        samples.push([now, scrollY]);
        while (samples.length > 1 && now - samples[0][0] > 250) samples.shift();
        if (Math.abs(scrollY - samples[0][1]) > 1.5 * innerHeight) html.classList.add("fast");
        clearTimeout(calm);
        calm = setTimeout(() => html.classList.remove("fast"), 500);
      },
      { passive: true },
    );
  });

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
      { rootMargin: "0px 0px 35% 0px" },
    );
    reveals.forEach((el) => seen.observe(el));
  });
})();
