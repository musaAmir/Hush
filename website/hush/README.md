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

- The hero demo (wallpaper, windows, menu bar and the Hush menu) is built in HTML and
  dims like the app. The four Settings images are real screenshots of Hush.
- Download links point to the GitHub releases page. Once a release is published,
  link straight to its zip.
- Apple's system font, like the app. No web fonts, analytics, cookies or third-party
  requests.
- Photos from Unsplash (Unsplash License), credited in the footer: the wallpaper by
  Alexey Topolyanskiy and "facade.jpg" by Roman Kraft.
