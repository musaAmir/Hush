// Hush website. Everything works without this script; it adds the live demo and entrances.
document.documentElement.classList.add("js");
const reduceMotion = matchMedia("(prefers-reduced-motion: reduce)").matches;
const fadeMs = reduceMotion ? 0 : 500;

// The demo desktop behaves like Hush: the shade over other windows never resets.
// Only the window losing focus fades down under its own veil, then joins the rest.
const desktop = document.querySelector(".desktop");
const windows = [...document.querySelectorAll(".win")];
const frontApp = document.querySelector(".front-app");
const intensity = document.getElementById("intensity");
const intensityValue = document.getElementById("intensity-value");
const ctaLevel = document.getElementById("cta-level");
let order = windows.filter((w) => !w.classList.contains("is-focused"));
let leaveTimer;

function focusWindow(next) {
  const current = document.querySelector(".win.is-focused");
  if (next === current) return;
  clearTimeout(leaveTimer);
  document.querySelectorAll(".win.is-leaving").forEach((w) => w.classList.remove("is-leaving"));
  order = order.filter((w) => w !== next);
  if (current) {
    current.classList.remove("is-focused"); current.setAttribute("aria-pressed", "false");
    order.push(current);
    if (desktop.dataset.dimming === "on" && fadeMs) {
      current.classList.add("is-leaving");
      leaveTimer = setTimeout(() => current.classList.remove("is-leaving"), fadeMs + 40);
    }
  }
  order.forEach((w, i) => w.style.setProperty("--z", i + 1));
  next.classList.add("is-focused"); next.setAttribute("aria-pressed", "true");
  frontApp.textContent = next.dataset.app;
}
windows.forEach((w) => w.addEventListener("click", () => focusWindow(w)));

function setDimming(on) { desktop.dataset.dimming = on ? "on" : "off"; }
document.querySelector(".hush-item").addEventListener("click", () => setDimming(desktop.dataset.dimming !== "on"));
addEventListener("keydown", (event) => {
  if (event.ctrlKey && event.altKey && event.code === "KeyD") { event.preventDefault(); setDimming(desktop.dataset.dimming !== "on"); }
});

function fill(range) {
  range.style.setProperty("--fill", ((range.value - range.min) / (range.max - range.min)) * 100 + "%");
}
function setLevel(value, source) {
  const level = Math.min(85, Math.max(5, Math.round(Number(value) || 45)));
  desktop.style.setProperty("--dim", level / 100);
  intensityValue.textContent = level + "%";
  if (source !== intensity) { intensity.value = level; }
  if (source !== ctaLevel) { ctaLevel.value = level; }
  fill(intensity);
}
intensity.addEventListener("input", () => setLevel(intensity.value, intensity));
ctaLevel.addEventListener("input", () => { if (ctaLevel.value !== "") setLevel(ctaLevel.value, ctaLevel); });
ctaLevel.addEventListener("change", () => setLevel(ctaLevel.value));
fill(intensity);

// Exceptions: type an app and it joins the list.
const known = {
  keynote: ["com.apple.Keynote", "#f39c12"], figma: ["com.figma.Desktop", "#a259ff"],
  "final cut pro": ["com.apple.FinalCut", "#3a3a3c"], "quicktime player": ["com.apple.QuickTimePlayerX", "#1e6fd9"],
  zoom: ["us.zoom.xos", "#2d8cff"], photoshop: ["com.adobe.Photoshop", "#0b2b4f"], xcode: ["com.apple.dt.Xcode", "#1f7fe0"],
};
const appInput = document.getElementById("app-input");
function showException(raw) {
  const name = raw.trim() || "Keynote";
  const [id, colour] = known[name.toLowerCase()] ||
    ["com." + name.toLowerCase().replace(/[^a-z0-9]+/g, "") + ".app", "#5f6b62"];
  document.getElementById("ex-name").textContent = name;
  document.getElementById("ex-id").textContent = id;
  const icon = document.getElementById("ex-icon");
  icon.textContent = name[0].toUpperCase(); icon.style.setProperty("--c", colour);
  document.getElementById("ex-foot").textContent = `Dimming pauses while ${name} is active and comes back when you switch away.`;
}
appInput.addEventListener("input", () => showException(appInput.value));
document.querySelectorAll("[data-example]").forEach((button) => button.addEventListener("click", () => {
  appInput.value = button.dataset.example; showException(appInput.value); appInput.focus();
}));

// Settings plate: pointing at a note dims the rest of the panel, the way Hush would.
const panel = document.querySelector(".panel");
function light(target) {
  panel.querySelectorAll(".is-lit").forEach((el) => el.classList.remove("is-lit"));
  document.querySelectorAll(".note.is-on").forEach((el) => el.classList.remove("is-on"));
  if (!target) { panel.classList.remove("has-focus"); return; }
  panel.querySelector(`[data-part="${target.dataset.target}"]`)?.classList.add("is-lit");
  target.classList.add("is-on"); panel.classList.add("has-focus");
}
document.querySelectorAll(".note").forEach((note) => {
  note.addEventListener("mouseenter", () => light(note));
  note.addEventListener("focus", () => light(note));
  note.addEventListener("click", () => light(note.classList.contains("is-on") && panel.classList.contains("has-focus") ? null : note));
  note.addEventListener("mouseleave", () => light(null));
  note.addEventListener("blur", () => light(null));
});

// Privacy: the pinned fragment follows the statement in view.
const sees = document.querySelector(".sees");
const steps = new IntersectionObserver((entries) => {
  entries.forEach((entry) => { if (entry.isIntersecting) sees.dataset.step = entry.target.dataset.step; });
}, { rootMargin: "-45% 0px -45% 0px" });
document.querySelectorAll(".pstep").forEach((step) => steps.observe(step));

// Setup: one slider drives the clause and the fragment.
const clauses = ["First, download and unzip.", "Then, allow Accessibility.", "Next, click any window.", "Finally, rest with ⌃⌥D."];
const names = ["Download and unzip", "Allow Accessibility", "Click any window", "Rest with Control, Option, D"];
const stage = document.getElementById("stage");
const clause = document.querySelector(".clause");
const frag = document.querySelector(".setup-frag");
const stageNames = document.querySelectorAll(".stage-names span");
let swap;
stage.addEventListener("input", () => {
  const i = Number(stage.value);
  fill(stage); frag.dataset.stage = i;
  stage.setAttribute("aria-valuetext", names[i]);
  stageNames.forEach((el, n) => el.classList.toggle("is-on", n === i));
  clearTimeout(swap);
  clause.classList.add("is-swapping");
  swap = setTimeout(() => { clause.textContent = clauses[i]; clause.classList.remove("is-swapping"); }, reduceMotion ? 0 : 200);
});
fill(stage);

// Questions: one answer pane on wide screens, inline answers on phones.
const questions = [...document.querySelectorAll(".q")];
const answer = document.getElementById("faq-answer");
function choose(q) {
  questions.forEach((other) => { other.classList.toggle("is-on", other === q); other.setAttribute("aria-expanded", String(other === q)); });
  if (answer.textContent === q.nextElementSibling.textContent) return;
  answer.classList.add("is-swapping");
  setTimeout(() => { answer.textContent = q.nextElementSibling.textContent; answer.classList.remove("is-swapping"); }, reduceMotion ? 0 : 150);
}
const wide = matchMedia("(min-width: 901px)");
questions.forEach((q) => {
  q.addEventListener("click", () => choose(q));
  q.addEventListener("focus", () => choose(q));
  q.addEventListener("mouseenter", () => { if (wide.matches) choose(q); });
});

// Entrances: each section's parts rise in turn as it enters.
const reveals = new IntersectionObserver((entries) => {
  entries.forEach((entry) => {
    if (!entry.isIntersecting) return;
    entry.target.classList.add("is-in"); reveals.unobserve(entry.target);
  });
}, { rootMargin: "0px 0px -8% 0px" });
document.querySelectorAll("section").forEach((section) => {
  section.querySelectorAll(".reveal").forEach((el, i) => { el.style.setProperty("--i", i); reveals.observe(el); });
});
