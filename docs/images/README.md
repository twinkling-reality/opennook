# OpenNook README media

Images and the animated hero for the root `README.md`.

| File | What it shows | Produced by |
| --- | --- | --- |
| `nook-hero.gif` | Five ShowcaseNook scenes, each opening from the collapsed pill: player, agenda, shelf, timer, progress | `make-readme-media.sh` |
| `nook-player.png` | `ShowcaseNook --scene player`, expanded | `make-readme-media.sh` |
| `nook-agenda.png` | `ShowcaseNook --scene agenda`, expanded | `make-readme-media.sh` |
| `nook-timer.png` | `ShowcaseNook --scene timer`, expanded | `make-readme-media.sh` |
| `nook-progress.png` | `ShowcaseNook --scene progress`, expanded | `make-readme-media.sh` |
| `nook-shelf.png` | `ShowcaseNook --scene shelf`, expanded | `make-readme-media.sh` |

## Regenerate

The generated files come from the same ShowcaseNook recordings as the landing
page, so one recording session feeds both the site and the README:

```sh
./Scripts/record-showcase.sh player agenda timer progress   # re-record the scenes (optional)
./Scripts/build-landing-reel.sh                             # cut the landing reel from them
./docs/images/make-readme-media.sh                          # rebuild the five files above
```

`make-readme-media.sh` only reads its inputs. It needs `ffmpeg` and takes a
few seconds.

### What the script does

Its inputs already carry alpha: `record-showcase.sh` keys the cream recording
backdrop out and unmixes the rim glow from it (`Scripts/unmix-backdrop.swift`),
and `build-landing-reel.sh` cuts the scenes into one 1440x672 reel with the
notch on the first row and a seamless loop.

1. **Backdrop.** Everything is composited onto a cool paper, `#EAF1F8`. The
   black nook needs a light surface around it so its outline shows on GitHub's
   dark theme, and the paper reads as a soft card on the light one too.

2. **Hero GIF.** The whole reel (`site/src/assets/reel/reel-alpha.webm`, about
   16 s) on paper at 12 fps, scaled to 840x392 with lanczos. The reel ends on
   the frame it starts with, so the GIF loops without a seam. One global
   256-colour `palettegen` pass, applied with
   `paletteuse=dither=sierra2_4a:diff_mode=rectangle`, keeps it under 3 MB.

3. **Stills.** Each window capture in `site/src/assets/showcase/<scene>.png`
   is centred on a 1440x672 paper canvas (the reel's frame) with the notch on
   the top edge, so the four stills line up in the README grid, then halved to
   720x336.

`shelf` is left out until its last tile is no longer clipped; `hud` and
`compact` are small enough that they read poorly at README size.

## Manual captures

For a still the script does not cover, run the example from the repo root
(after `swift build` once), expand with **⌥⌘;**, and capture:

```sh
swift run ShelfNook     # file shelf (NookComponents)
```

OpenNook defaults to the built-in (notched) display. On a multi-display setup,
capture from the laptop panel, or pick another display in Settings -> Display
for the session. **Cmd+Shift+4**, then **Space**, then click the nook window
captures it on its own. Crop tightly to the nook and keep the width near the
existing stills (about 720px).
