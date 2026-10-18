# Hush website

Live at **https://musaamir.github.io/Hush/**, hosted on GitHub Pages.

A buildless page: `dist/index.html`, `dist/styles.css`, `dist/app.js` and `dist/assets/`.
Preview locally from this folder:

```sh
python3 -m http.server 4173 --directory dist
```

Then open http://localhost:4173. No dependencies or build step.

## Deployment

Pushing changes under `website/hush/dist/` to `main` runs the
[Pages workflow](../../.github/workflows/pages.yml), which checks the JavaScript and
publishes `dist/`. Re-run it from the Actions tab with **Run workflow**.

## Content

- The hero desktop, the Exceptions list, the Settings panel and the setup steps are
  HTML recreations of Hush; the three Settings images are real screenshots of the app.
- Download links point to the GitHub releases page. Once a release is published,
  link straight to its zip.
- Bricolage Grotesque (SIL Open Font License) is self-hosted. No analytics, cookies or
  third-party requests.
- Photos: "facade.jpg" by Roman Kraft and "curves.jpg" by Len dela Cruz, both on
  Unsplash (Unsplash License), credited in the footer.
