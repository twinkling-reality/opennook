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
| `nook-playground.gif` | The same pair, while Material moves Solid -> Translucent -> Glass and the nook follows | `record-playground.sh` |

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
./docs/images/record-playground.sh clip --seconds 9 --fps 6
./docs/images/record-playground.sh clip --no-drive    # change the control by hand
```

The script hides the desk behind `playground-backdrop.swift` (the README paper,
`#EAF1F8`, one window level *below* normal windows so the controls window stays
in front - `Scripts/reel-backdrop.swift` sits above them and would cover it),
opens `PlaygroundNook --sample glass --expand --keep-open`, and captures the
nook panel and the controls window by window id. Nothing is keyed: the backdrop
is already the final colour.

**Only the app's own two windows are ever captured.** Both the still and the
clip are `screencapture -x -o -l<id>` of windows the launched PlaygroundNook
owns; no rectangle of the screen is recorded, and the script does not so much as
compute one. The paper behind the pair is painted by ffmpeg rather than
photographed, so `playground-backdrop.swift` is only there to let the operator
see the shot they are composing. Nothing on the desk, in front of the backdrop
or behind it, can reach either file.

- **Still.** The panel capture is trimmed of its transparent margin, then the
  pair is composited onto one paper canvas: the nook flush with the top edge
  (the notch on the first row, as the ShowcaseNook stills sit) and the controls
  window centred below, scaled to 840 wide.

- **Clip.** `screencapture -v` takes a rectangle and no window id, so the clip
  is not a movie: it is a burst of window-id captures. For `--seconds`, the loop
  grabs both windows in parallel as fast as macOS manages, about 5 pairs a
  second here, re-resolving both ids whenever a capture comes back empty (the
  panel's id changes when the nook expands or its window is rebuilt) and
  carrying the previous frame's half over so the take neither dies nor freezes.
  Each pair is then composited exactly as the still is, onto one canvas sized
  from the largest panel in the take, and the pairs are resampled onto an even
  `--fps` grid using the time each one landed, so uneven captures still read as
  even motion. `--fps` defaults to 6 and drops to the rate the loop actually
  managed. The GIF pass is the hero GIF's recipe: 840 wide, one global
  256-colour `palettegen`, `paletteuse=dither=sierra2_4a:diff_mode=rectangle`,
  `-loop 0`.

- **Driving.** The control the clip shows being changed is pressed by the
  script, not by a person. `playground-poke.swift` builds an accessibility
  element from the pid the script launched, walks only that app's `AXWindows`,
  and presses the button it is asked for. The Appearance page's segmented rows
  carry no accessibility identifiers, so a step names the row and the choice by
  the labels `PillPicker` already exposes - the row is an `AXGroup` labelled
  `Material` holding `AXButton`s labelled `Solid`, `Translucent` and `Glass` -
  and a step matches only when one element carries the row's label *and* has
  that choice under it, which keeps the row's plain `Text("Material")` out of
  the way. Steps also take `id=<identifier>` for anything that does expose one
  (`toolbar.code`, `toolbar.expand`, `assistant.apply`) and `page=<id>` for the
  sidebar rows (`page.theme`, `page.effects`).

  The default is `Material=Solid,Material=Translucent,Material=Glass`, which
  ends on the material `--sample glass` starts from, so the GIF loops without a
  jump. The steps are spread evenly over `--seconds`, leaving a beat of settled
  frames at either end. `--drive-steps` takes a different list; `--no-drive`
  leaves the app alone and the clip waits for a person, the way it used to.

  Two things bound what the poker can touch. It is given one pid and nothing
  else, and every element is checked to belong to that pid before it is
  pressed; and it never reads the app's `AXMenuBar`, which on a real Mac
  carries the Apple menu's recent documents. It needs Accessibility permission
  for whatever runs the script (System Settings -> Privacy & Security ->
  Accessibility). Without it the script says so and stops before recording
  anything, rather than producing a take where nothing moves.

With `--no-drive` the clip needs a person: when the countdown ends, change one
visible control (Appearance -> Material, or Theme -> Accent) slowly enough to
read, and let the nook settle. Keep the pointer over the controls window, which
is the only place the capture can see it.

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
