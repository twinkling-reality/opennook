# opennook-site

The OpenNook documentation site. Astro 5 + Starlight, live at
[opennook.dev](https://opennook.dev) via Cloudflare Pages.

## Install

```sh
cd site
npm install
```

## Develop

```sh
npm run dev
```

Serves at `http://localhost:4321`.

## Build

```sh
npm run build      # output -> dist/
npm run preview    # serve the built site locally
```

## Deploy: Cloudflare Pages

Connect the GitHub repo to Cloudflare Pages and use:

- **Framework preset:** Astro
- **Build command:** `npm run build`
- **Build output directory:** `dist`
- **Root directory:** `site`
- **Node version:** 20 or later

No `wrangler.toml` is needed for a Pages project configured through the
dashboard. Add one only if you switch to a `wrangler`-driven deploy.

## Structure

```
site/
  astro.config.mjs           Starlight integration, sidebar, component overrides.
  package.json
  tsconfig.json
  src/
    pages/
      index.astro            Landing page (site root): hero copy plus the
                             showcase reel. Standalone, not a Starlight page.
      llms.txt.ts            /llms.txt index of the docs.
      llms-full.txt.ts       /llms-full.txt, every docs page in one file.
      [...slug].md.ts        Raw Markdown for each docs page at /<slug>.md.
    components/
      landing/
        NookShowcase.astro   The looping reel card on the landing page.
      Header.astro           Starlight overrides (Header, SiteTitle,
      SiteTitle.astro        PageTitle, ThemeSelect -> ThemeToggle).
      PageTitle.astro
      ThemeToggle.astro
      NookMark.astro         The OpenNook mark.
    assets/
      reel/                  Raw recordings of example nooks and the edited
                             reel the landing page plays (see below).
    content.config.ts        Starlight docs collection (docsLoader/docsSchema).
    content/docs/
      start/                 Introduction, install, first nook.
      guides/                Components, theming, chrome, layout, playground...
      reference/             API reference (points at Swift Package Index).
    styles/
      tokens.css             Shared colour and type tokens, landing + docs.
      motion.css             Durations, easing, hover and focus primitives,
                             and the reduced-motion fallback, landing + docs.
      landing.css            Landing page layout and ground.
      custom.css             Starlight theme overrides.
```

## The landing reel

The landing page does not run a live demo. It plays one looping reel of the
`Examples/ShowcaseNook` scenes, each opening from the collapsed pill. From the
repo root:

```sh
./Scripts/record-showcase.sh          # record every scene into src/assets/showcase/
./Scripts/record-showcase.sh shelf    # or only some
./Scripts/build-landing-reel.sh       # cut the takes into the reel
```

`record-showcase.sh` builds and launches `ShowcaseNook --scene <id>` in front of
a flat backdrop (`Scripts/reel-backdrop.swift`), captures the expanded window
as a still and a short clip of the pill expanding, keys the backdrop out and
cleans its tinted edges with `Scripts/unmix-backdrop.swift`. It puts windows on
screen and moves the pointer, so run it when the Mac is free.
`build-landing-reel.sh` cuts player, agenda, shelf, timer and progress into the
reel (`src/assets/reel/reel-alpha.webm`, plus the Safari cut and poster the
showcase loads). `NookShowcase.astro` documents the size it expects. Both
scripts need macOS, a built package, and `ffmpeg`; recording also needs Screen
Recording permission for the terminal.

macOS app screenshots and the animated hero for the root README live in
`../docs/images/` (not under `site/public/`), and are cut from the same
recordings by `../docs/images/make-readme-media.sh`.

## Editing content

Docs pages are MDX under `src/content/docs/`. The landing page is
`src/pages/index.astro`. Sidebar order is declared in `astro.config.mjs`.
Use Starlight's built-in components (`Card`, `CardGrid`, `Code`, `Tabs`,
etc.) by importing from `@astrojs/starlight/components`.
