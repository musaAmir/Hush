// Hush website. The page reads fine without this script; it adds the live demo.
document.documentElement.classList.add("js");
const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
const fadeMs = reduceMotion ? 0 : 500;

// Scale the 1280 × 800 desktop to fit its screen.
const screen = document.querySelector(".screen");
const desktop = document.querySelector(".desktop");
new ResizeObserver(([entry]) => desktop.style.setProperty("--scale", entry.contentRect.width / 1280)).observe(screen);

// Focus behaves like Hush: the dimming over other windows never resets.
// Only the window losing focus fades down under its own veil, then joins the rest.
const windows = [...document.querySelectorAll(".win")];
const frontApp = document.querySelector(".front-app");
let order = windows.filter((w) => !w.classList.contains("is-focused"));
let leaveTimer;
function focusWindow(next) {
  const current = document.querySelector(".win.is-focused");
  if (next === current) return;
  clearTimeout(leaveTimer);
  document.querySelectorAll(".win.is-leaving").forEach((w) => w.classList.remove("is-leaving"));
  order = order.filter((w) => w !== next);
  if (current) {
    current.classList.remove("is-focused");
    order.push(current);
    if (desktop.dataset.dimming === "on" && fadeMs) {
      current.classList.add("is-leaving");
      leaveTimer = setTimeout(() => current.classList.remove("is-leaving"), fadeMs + 40);
    }
  }
  order.forEach((w, i) => w.style.setProperty("--z", i + 1));
  next.classList.add("is-focused");
  frontApp.textContent = next.dataset.app;
}
windows.forEach((w) => w.addEventListener("click", () => { closeMenu(); focusWindow(w); }));

// The Hush menu bar item and its menu.
const item = document.querySelector(".hush-item");
const menu = document.querySelector(".hush-menu");
const toggleItem = menu.querySelector('[data-action="toggle"]');
const pauseGroup = menu.querySelector(".has-sub");
const resumeItem = menu.querySelector('[data-action="resume"]');
let paused = false;
function render() {
  const on = toggleItem.getAttribute("aria-checked") === "true";
  desktop.dataset.dimming = on && !paused ? "on" : "off";
  toggleItem.querySelector(".check").textContent = on && !paused ? "✓" : "";
  pauseGroup.hidden = !on || paused;
  resumeItem.hidden = !paused;
}
function setEnabled(on) { paused = false; toggleItem.setAttribute("aria-checked", String(on)); render(); }
function closeMenu() { menu.hidden = true; item.setAttribute("aria-expanded", "false"); }
item.addEventListener("click", (event) => {
  event.stopPropagation();
  desktop.classList.add("has-tried");
  const open = menu.hidden;
  menu.hidden = !open; item.setAttribute("aria-expanded", String(open));
  // Keyboard users land on the first item; a mouse click leaves the menu unfocused, like macOS.
  if (open && event.detail === 0) toggleItem.focus({ preventScroll: true });
});
menu.addEventListener("click", (event) => {
  const button = event.target.closest("button");
  if (!button) return;
  event.stopPropagation();
  const action = button.dataset.action;
  if (action === "pause") return;
  if (action === "toggle") setEnabled(toggleItem.getAttribute("aria-checked") !== "true");
  if (button.dataset.pause) { paused = true; render(); }
  if (action === "resume") { paused = false; render(); }
  if (action === "settings") document.getElementById("features").scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth" });
  closeMenu();
});
document.addEventListener("click", closeMenu);
addEventListener("keydown", (event) => {
  if (event.key === "Escape") closeMenu();
  if (event.ctrlKey && event.altKey && event.code === "KeyD") {
    event.preventDefault(); desktop.classList.add("has-tried");
    setEnabled(paused ? true : toggleItem.getAttribute("aria-checked") !== "true");
  }
});

const intensity = document.getElementById("intensity");
const intensityValue = document.getElementById("intensity-value");
intensity.addEventListener("input", () => {
  desktop.style.setProperty("--dim", intensity.value / 100);
  intensityValue.textContent = intensity.value + "%";
});

// Features: each one shows its page of the real Settings window.
const features = [...document.querySelectorAll(".feature")];
const shots = [...document.querySelectorAll(".shot img")];
function show(feature) {
  features.forEach((f) => { f.classList.toggle("is-on", f === feature); f.setAttribute("aria-selected", String(f === feature)); });
  shots.forEach((img) => img.classList.toggle("is-on", img.dataset.name === feature.dataset.shot));
}
features.forEach((f) => {
  f.addEventListener("click", () => show(f));
  f.addEventListener("mouseenter", () => { if (matchMedia("(hover: hover)").matches) show(f); });
});

// Entrances: each section's parts rise in turn as it enters.
const reveals = new IntersectionObserver((entries) => entries.forEach((entry) => {
  if (!entry.isIntersecting) return;
  entry.target.classList.add("is-in"); reveals.unobserve(entry.target);
}), { rootMargin: "0px 0px -6% 0px" });
document.querySelectorAll("section").forEach((section) => {
  section.querySelectorAll(".reveal").forEach((el, i) => { el.style.setProperty("--i", i); reveals.observe(el); });
});
