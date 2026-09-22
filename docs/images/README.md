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

Not recorded yet, and so not referenced from `README.md`:

| File | What it should show | Produced by |
| --- | --- | --- |
| `nook-playground.png` | The PlaygroundNook controls window below the expanded nook | `record-playground.sh` |
| `nook-playground.gif` | The same pair, while one control is changed and the nook follows | `record-playground.sh` |

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

## PlaygroundNook

The playground is the live-tweaking tool, so its media has to show the controls
window and the running nook together - a still of the nook alone says nothing
about it. It is captured live rather than cut from the reel, so it has its own
script:

```sh
./docs/images/record-playground.sh --dry-run   # print the steps
./docs/images/record-playground.sh             # still + clip
./docs/images/record-playground.sh still       # just the still
```

The script hides the desk behind `playground-backdrop.swift` (the README paper,
`#EAF1F8`, one window level *below* normal windows so the controls window stays
in front - `Scripts/reel-backdrop.swift` sits above them and would cover it),
opens `PlaygroundNook --sample glass --expand --keep-open`, captures the nook
panel and the controls window by window id and composites them onto paper for
the still, then records a rectangle around both for the GIF. Nothing is keyed:
the backdrop is already the final colour.

The clip needs a person: when the countdown ends, change one visible control
(Appearance -> Material, or Theme -> Accent) slowly enough to read, and let the
nook settle. The pointer is in frame on purpose.

Until both files exist, `README.md` does not reference them. The markup to paste
in, and where it goes, is the `TODO(playground media)` block at the end of
`make-readme-media.sh`.

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
