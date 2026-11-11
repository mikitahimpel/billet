// Dust drifting in the lamp light. Positions are fractions of the stage box.
(() => {
  // Not part of the first paint: it starts once the browser is idle.
  const begin = () => {
    try {
      start();
    } catch (error) {
      document.documentElement.classList.remove("js");
      console.error("motes.js", error);
    }
  };
  if ("requestIdleCallback" in window) requestIdleCallback(begin, { timeout: 2000 });
  else setTimeout(begin, 1000);

  function start() {
    const canvas = document.querySelector(".motes");
    if (!canvas) return;
    const still = matchMedia("(prefers-reduced-motion: reduce)").matches;
    const ctx = canvas.getContext("2d");
    const css = getComputedStyle(document.documentElement);
    const lamp = {
      x: parseFloat(css.getPropertyValue("--lamp-x")) / 100 || 0.63,
      y: parseFloat(css.getPropertyValue("--lamp-y")) / 100 || 0.44,
    };
    let w = 0;
    let h = 0;
    let dpr = 1;

    const motes = Array.from({ length: 34 }, () => spawn(true));

    function spawn(anywhere) {
      const a = Math.random() * Math.PI * 2;
      const r = Math.sqrt(Math.random()) * 0.26;
      return {
        x: lamp.x - 0.12 + Math.cos(a) * r * 1.4,
        y: anywhere ? lamp.y + Math.sin(a) * r : lamp.y + 0.28,
        vx: (Math.random() - 0.5) * 0.00006,
        vy: -0.00002 - Math.random() * 0.00005,
        size: 0.6 + Math.random() * 1.5,
        phase: Math.random() * Math.PI * 2,
      };
    }

    function resize() {
      dpr = Math.min(devicePixelRatio || 1, 2);
      const box = canvas.getBoundingClientRect();
      w = box.width;
      h = box.height;
      canvas.width = Math.round(w * dpr);
      canvas.height = Math.round(h * dpr);
    }

    function draw(t) {
      ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
      ctx.clearRect(0, 0, w, h);
      for (const m of motes) {
        if (!still) {
          m.x += m.vx * 16 + Math.sin(t / 2400 + m.phase) * 0.00004;
          m.y += m.vy * 16;
          if (m.y < 0.12 || m.x < 0.1 || m.x > 0.95) Object.assign(m, spawn(false));
        }
        const dx = (m.x - lamp.x) / 0.32;
        const dy = (m.y - lamp.y) / 0.3;
        const lit = Math.max(0, 1 - Math.sqrt(dx * dx + dy * dy));
        const twinkle = 0.55 + 0.45 * Math.sin(t / 900 + m.phase * 3);
        const alpha = lit * twinkle * 0.85;
        if (alpha < 0.02) continue;
        const px = m.x * w;
        const py = m.y * h;
        const g = ctx.createRadialGradient(px, py, 0, px, py, m.size * 3);
        g.addColorStop(0, `rgba(255, 224, 180, ${alpha})`);
        g.addColorStop(1, "rgba(255, 190, 120, 0)");
        ctx.fillStyle = g;
        ctx.beginPath();
        ctx.arc(px, py, m.size * 3, 0, Math.PI * 2);
        ctx.fill();
      }
      if (!still) play();
    }

    // Runs only while the room is on screen and the tab is visible.
    let onScreen = true;
    let frame = 0;
    const tick = (t) => {
      frame = 0;
      draw(t);
    };
    const play = () => {
      if (!frame && onScreen && !document.hidden) frame = requestAnimationFrame(tick);
    };
    const pause = () => {
      cancelAnimationFrame(frame);
      frame = 0;
    };
    const wake = () => (onScreen && !document.hidden ? play() : pause());

    resize();
    addEventListener("resize", () => requestAnimationFrame(resize), { passive: true });
    document.addEventListener("visibilitychange", wake);
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(([entry]) => {
        onScreen = entry.isIntersecting;
        wake();
      }).observe(canvas);
    }
    play();
  }
})();
