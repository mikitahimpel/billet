// Each part runs on its own: one that throws drops the page to its no-script state
// (the "js" class off <html>, so nothing stays hidden), and the parts after it still run.
(() => {
  const html = document.documentElement;
  html.classList.add("js-ready");
  const run = (name, part) => {
    try {
      part();
    } catch (error) {
      html.classList.remove("js");
      console.error(`site.js: ${name}`, error);
    }
  };
  const still = matchMedia("(prefers-reduced-motion: reduce)").matches;

  // The end card's fairy lights, from the render's bulb positions in :root.
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
        bulb.style.setProperty("--d", `${(2.6 + Math.random() * 4.8).toFixed(2)}s`);
        bulb.style.setProperty("--delay", `${(Math.random() * 3).toFixed(2)}s`);
        layer.append(bulb);
      }
    }
  });

  // The phone menu closes on a tap outside it, on Escape and when a link is followed.
  run("menu", () => {
    const menu = document.querySelector(".menu");
    if (!menu) return;
    document.addEventListener("click", (e) => {
      if (menu.open && !menu.contains(e.target)) menu.open = false;
    });
    document.addEventListener("keydown", (e) => {
      if (e.key === "Escape") menu.open = false;
    });
    menu
      .querySelectorAll("a")
      .forEach((a) => a.addEventListener("click", () => (menu.open = false)));
  });

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
    for (const group of document.querySelectorAll(".pg-steps, .ideas, .hub-list")) {
      [...group.children].forEach((child, n) => child.style.setProperty("--n", n % 4));
    }
    const reveals = document.querySelectorAll(".reveal");
    if (still || !("IntersectionObserver" in window)) {
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
