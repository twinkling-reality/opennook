#!/bin/bash
# Record the PlaygroundNook media for the root README: one still and one short
# GIF of the controls window beside the live nook.
#
# The point of the playground is that the window on the desk changes the real
# nook above it, so both are in frame. Everything else here follows
# Scripts/record-showcase.sh: the app is captured by window id so no other
# window can leak in, the pointer is parked for the still, and the surface
# behind everything is a backdrop window rather than whatever the desk holds.
#
# Nothing outside PlaygroundNook's own two windows can reach the frame. Every
# capture here, still and clip alike, is `screencapture -x -o -l<id>` of a
# window this script's own process owns; no rectangle of the screen is
# recorded, and none is even computed. The paper around the nook is painted by
# ffmpeg rather than photographed, so playground-backdrop.swift is only there
# to let the operator see the shot they are composing.
#
# One difference from record-showcase.sh, forced by the controls window:
# Scripts/reel-backdrop.swift sits above normal windows, which would cover the
# controls window, and it paints the recording cream that the showcase pipeline
# keys out afterwards. This script uses playground-backdrop.swift instead: one
# level below normal windows, painted the README paper (#EAF1F8) directly.
# Nothing is keyed or unmixed here.
#
# The clip is a burst of window captures rather than a movie, because
# `screencapture -v` records a rectangle and takes no window id. The loop grabs
# both windows as fast as macOS hands them over, which measured about 5 pairs a
# second on an M-series Mac; each pair is composited onto paper in the still's
# layout, and the pairs are resampled to a steady --fps from the time each one
# landed, so a slider being dragged reads evenly even when the pairs do not.
# That rate is enough for a control being moved deliberately, which is what the
# GIF shows; it is not enough for the expand animation, and the still already
# covers the open nook.
#
# The control the clip shows being changed is pressed by the script itself.
# playground-poke.swift walks the accessibility tree of the PlaygroundNook the
# script launched, by pid, and presses the Material segments in turn, so the GIF
# has a setting moving and the nook re-rendering above it with nobody at the
# keyboard. It is scoped to that one pid: only that app's AXWindows are read,
# every element is checked to belong to it before it is pressed, and its menu
# bar is never touched. Driving needs Accessibility permission for whatever runs
# this script; without it the script says what to grant and stops, or you can
# pass --no-drive and change the control by hand as before.
#
# This puts windows on screen and moves the pointer. Run it when the Mac is
# free: other windows cannot appear in the media, but they can sit under the
# pointer you are about to drag.
#
# Outputs, both in docs/images/:
#   nook-playground.png   the controls window under the expanded nook, on paper
#   nook-playground.gif   ~8 s of a control being changed and the nook following
#
# Usage:
#   docs/images/record-playground.sh [--dry-run] [--yes] [--sample <id>]
#                                    [--seconds <n>] [--fps <n>] [--no-drive]
#                                    [--drive-steps <list>] [still|clip|all]
#
#   --sample   a built-in playground look: defaults, media, glass, glance, call
#              (default: glass). The nook's own content is the playground home
#              view either way; the sample is what makes it look like a product
#              rather than a settings screen.
#   --seconds  how long the clip's capture loop runs (default: 8).
#   --fps      the clip's frame rate (default: 6). Lowered to the rate the loop
#              actually managed if the captures come in slower than that.
#   --no-drive    leave the controls alone during the clip and change one by
#                 hand, the way this script worked before it could press them.
#   --drive-steps a comma separated list of controls to press during the clip,
#                 each "<row label>=<choice label>" as the Appearance page
#                 spells them, or "id=<accessibility id>" or "page=<page id>"
#                 (default: Material=Solid,Material=Translucent,Material=Glass).
#                 They are spread evenly across --seconds.
#   --yes      skip the "arrange the window" pause before each capture.
#   --dry-run  print every step instead of running it.
#
# Requires ffmpeg (brew install ffmpeg) and the Xcode command line tools.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
bin="$root/.build/debug"
paper=0xEAF1F8

# The still's layout, shared with the clip so both read as the same shot: the
# canvas margin around the pair and the gap between the nook and the controls.
margin=48
gap=40

sample=glass
seconds=8
fps=6
what=all
dry_run=0
assume_yes=0
drive=1
drive_steps=Material=Solid,Material=Translucent,Material=Glass
# What the poker spends on its first query before it can press anything: the
# first cross-process read is what makes SwiftUI build its accessibility tree.
settle=0.6

while (( $# )); do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --yes) assume_yes=1 ;;
    --drive) drive=1 ;;
    --no-drive) drive=0 ;;
    --drive-steps) drive_steps="${2:?--drive-steps needs a list}"; shift ;;
    --sample) sample="${2:?--sample needs an id}"; shift ;;
    --seconds) seconds="${2:?--seconds needs a number}"; shift ;;
    --fps) fps="${2:?--fps needs a number}"; shift ;;
    still|clip|all) what="$1" ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done

run() {
  if (( dry_run )); then
    printf '+ %s\n' "$*"
  else
    "$@"
  fi
}

pause() {
  (( assume_yes || dry_run )) && return 0
  printf '\n%s\n' "$1"
  read -r -p "Press Return when it looks right. "
}

tmp="$(mktemp -d)"
cleanup() {
  if (( ! dry_run )); then
    pkill -x PlaygroundNook >/dev/null 2>&1 || true
    pkill -x playground-backdrop >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

# Crops a window capture to its visible pixels, dropping the transparent margin.
# The same helper record-showcase.sh writes; the nook panel's capture is mostly
# empty space, and the composite below needs its real bounds.
cat >"$tmp/trim-alpha.swift" <<'SWIFT'
import AppKit

let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let source = CGImageSourceCreateWithURL(input as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else { exit(1) }
let width = image.width
let height = image.height
var pixels = [UInt8](repeating: 0, count: width * height * 4)
let context = CGContext(
    data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
    space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
)!
context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
var minX = width, minY = height, maxX = -1, maxY = -1
for y in 0..<height {
    for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 8 {
        minX = min(minX, x); maxX = max(maxX, x)
        minY = min(minY, y); maxY = max(maxY, y)
    }
}
guard maxX >= minX, let cropped = image.cropping(to: CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1))
else { exit(1) }
let rep = NSBitmapImageRep(cgImage: cropped)
try rep.representation(using: .png, properties: [:])!.write(to: output)
SWIFT

# Turns the clip's burst of captures into an even sequence. Reads the raw
# directory, prints "<canvas w> <canvas h> <fps>" on stdout and the measured
# capture rate on stderr, and writes one line per output frame to the plan file:
# the stem of the pair that should be shown at that instant.
#
# The pairs are stamped by the modification time of their PNGs, which is when
# screencapture finished writing them, so the resample follows real time rather
# than the loop's count. The canvas is the largest panel and the largest
# controls window in the take, so a frame where the nook expands does not resize
# the GIF.
cat >"$tmp/plan-clip.py" <<'PYTHON'
import bisect
import os
import sys

raw, target_fps, margin, gap, plan_path = (
    sys.argv[1], float(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
)


def png_size(path):
    with open(path, "rb") as handle:
        header = handle.read(26)
    return int.from_bytes(header[16:20], "big"), int.from_bytes(header[20:24], "big")


frames = []
for name in sorted(os.listdir(raw)):
    if not name.endswith("-panel.png"):
        continue
    stem = name[: -len("-panel.png")]
    panel = os.path.join(raw, stem + "-panel-trimmed.png")
    controls = os.path.join(raw, stem + "-controls.png")
    if not (os.path.exists(panel) and os.path.exists(controls)):
        continue
    when = max(os.stat(os.path.join(raw, name)).st_mtime, os.stat(controls).st_mtime)
    frames.append((when, stem, png_size(panel), png_size(controls)))
if len(frames) < 2:
    raise SystemExit("not enough pairs to build a clip")
frames.sort()

times = [f[0] for f in frames]
elapsed = times[-1] - times[0]
rate = (len(frames) - 1) / elapsed if elapsed > 0 else target_fps
fps = max(2, min(int(target_fps), round(rate)))
print(
    f"captured {len(frames)} pairs in {elapsed:.1f}s, {rate:.1f} pairs/s; encoding at {fps} fps",
    file=sys.stderr,
)

width = max(max(f[2][0] for f in frames), max(f[3][0] for f in frames)) + margin * 2
height = max(f[2][1] for f in frames) + gap + max(f[3][1] for f in frames) + margin
width += width % 2
height += height % 2

# Nearest pair at or before each tick, so a stall holds the last real frame
# instead of sliding the whole take earlier.
with open(plan_path, "w") as plan:
    for step in range(int(elapsed * fps) + 1):
        moment = times[0] + step / fps
        plan.write(frames[max(0, bisect.bisect_right(times, moment) - 1)][1] + "\n")

print(width, height, fps)
PYTHON

echo "building PlaygroundNook and the capture helpers..."
run swift build --package-path "$root" --product PlaygroundNook
run swiftc -O -o "$tmp/nook-windows" "$root/Scripts/nook-windows.swift"
run swiftc -O -o "$tmp/park-cursor" "$root/Scripts/park-cursor.swift"
run swiftc -O -o "$tmp/playground-backdrop" "$here/playground-backdrop.swift"
run swiftc -O -o "$tmp/trim-alpha" "$tmp/trim-alpha.swift"
if (( drive )); then
  run swiftc -O -o "$tmp/playground-poke" "$here/playground-poke.swift"
fi

echo "opening the paper backdrop"
if (( dry_run )); then
  printf '+ %s\n' "$tmp/playground-backdrop &"
else
  "$tmp/playground-backdrop" >/dev/null 2>&1 &
  sleep 0.6
fi

# --expand --keep-open holds the nook open while the controls window has focus,
# which is the whole point of the shot: a control changes, the nook follows.
echo "launching PlaygroundNook --sample $sample"
if (( dry_run )); then
  printf '+ %s\n' "$bin/PlaygroundNook --sample $sample --expand --keep-open &"
else
  "$bin/PlaygroundNook" --sample "$sample" --expand --keep-open >/dev/null 2>&1 &
fi

wait_for_pid() {
  local tries=40 pid=""
  while (( tries-- > 0 )); do
    pid="$(pgrep -n -x PlaygroundNook || true)"
    [[ -n "$pid" ]] && { echo "$pid"; return 0; }
    sleep 0.25
  done
  echo "timed out waiting for PlaygroundNook" >&2
  return 1
}

# Prints "<panel id> <controls id>": the nook panel (the highest window the
# process owns) and the controls window (the largest ordinary window). These two
# ids are the whole of what this script can capture. Nothing here computes a
# rectangle, so there is no path by which a neighbouring window could be
# photographed even if one surfaced over the backdrop mid-take.
window_ids() {
  local pid="$1"
  "$tmp/nook-windows" "$pid" | python3 -c '
import json, sys

wins = json.load(sys.stdin)["windows"]
if not wins:
    raise SystemExit("no windows")
top = max(w["layer"] for w in wins)
panel = max((w for w in wins if w["layer"] == top), key=lambda w: w["w"] * w["h"])
ordinary = [w for w in wins if w["layer"] == 0 and w["id"] != panel["id"]]
if not ordinary:
    raise SystemExit("no controls window: launch without --hide-controls")
controls = max(ordinary, key=lambda w: w["w"] * w["h"])
print(panel["id"], controls["id"])
'
}

if (( dry_run )); then
  printf '+ %s\n' "nook-windows <pid> -> panel id, controls id"
  panel_id=PANEL; controls_id=CONTROLS
else
  pid="$(wait_for_pid)"
  sleep 2.5
  read -r panel_id controls_id <<<"$(window_ids "$pid")"
  echo "panel $panel_id, controls $controls_id"

  # The poker with no steps only asks whether this process may drive another
  # app, so the take fails here rather than after a still is already recorded.
  if (( drive )) && ! "$tmp/playground-poke" "$pid" >/dev/null; then
    echo "re-run with --no-drive to change the control by hand instead." >&2
    exit 1
  fi
fi

# ---- still -------------------------------------------------------------------
# Two window-id captures composited onto one paper canvas: the nook flush with
# the top edge (the notch on the first row, the way the ShowcaseNook stills sit)
# and the controls window centred below it. 840 wide, matching the hero GIF.
if [[ "$what" == still || "$what" == all ]]; then
  pause "Arrange the shot: Appearance page selected, the code panel showing, the controls window about 980x700 and roughly centred under the nook."
  echo "== still"
  if (( dry_run )); then
    printf '+ %s\n' "park-cursor" \
      "screencapture -x -o -l $panel_id $tmp/panel.png" \
      "screencapture -x -o -l $controls_id $tmp/controls.png" \
      "trim-alpha $tmp/panel.png $tmp/panel-trimmed.png" \
      "ffmpeg <paper canvas, nook on the top edge, controls below> $here/nook-playground.png"
  else
    "$tmp/park-cursor" >/dev/null 2>&1 || true
    sleep 0.4
    screencapture -x -o -l "$panel_id" "$tmp/panel.png"
    screencapture -x -o -l "$controls_id" "$tmp/controls.png"
    "$tmp/trim-alpha" "$tmp/panel.png" "$tmp/panel-trimmed.png"

    size() { ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$1"; }
    panel_size="$(size "$tmp/panel-trimmed.png")"
    controls_size="$(size "$tmp/controls.png")"
    canvas_w=$(( ( ${panel_size%x*} > ${controls_size%x*} ? ${panel_size%x*} : ${controls_size%x*} ) + margin * 2 ))
    canvas_h=$(( ${panel_size#*x} + gap + ${controls_size#*x} + margin ))
    (( canvas_w % 2 )) && canvas_w=$(( canvas_w + 1 ))
    (( canvas_h % 2 )) && canvas_h=$(( canvas_h + 1 ))

    ffmpeg -y -hide_banner -loglevel error \
      -i "$tmp/panel-trimmed.png" -i "$tmp/controls.png" \
      -filter_complex "color=$paper:s=${canvas_w}x${canvas_h}[bg];\
[bg][0:v]overlay=(W-w)/2:0:format=auto[a];\
[a][1:v]overlay=(W-w)/2:H-h-$margin:format=auto,\
scale=840:-2:flags=lanczos,format=rgb24" \
      -frames:v 1 -update 1 -compression_level 100 "$here/nook-playground.png"
  fi
fi

# ---- clip --------------------------------------------------------------------
# The same two windows as the still, captured over and over while a control is
# changed, then composited frame by frame into the still's layout. No movie is
# recorded and no rectangle is read, so the clip is exactly as private as the
# still: the only pixels that exist are the app's own two windows.
#
# The pairs arrive at whatever rate screencapture manages, which wobbles, so
# each pair is stamped with the time it landed (its file's modification time)
# and the sequence is resampled onto an even --fps grid before encoding.
if [[ "$what" == clip || "$what" == all ]]; then
  if (( drive )); then
    pause "Ready to record ${seconds}s. The script presses the controls itself ($drive_steps); keep your hands off the keyboard and leave the app frontmost."
  else
    pause "Ready to record ${seconds}s. When the countdown ends, change one visible control (Appearance -> Material, or Theme -> Accent) slowly, then stop. Keep the pointer over the controls window: it is drawn only where the capture can see it."
  fi
  echo "== clip"
  if (( dry_run )); then
    if (( drive )); then
      printf '+ %s\n' "playground-poke <pid> --delay <seconds/steps> $drive_steps &"
    fi
    printf '+ %s\n' \
      "for ${seconds}s: screencapture -x -o -l $panel_id $tmp/raw/NNNNN-panel.png" \
      "                 screencapture -x -o -l $controls_id $tmp/raw/NNNNN-controls.png" \
      "                 (re-resolving both ids whenever a capture comes back empty)" \
      "trim-alpha each panel, then plan-clip.py -> canvas size, measured rate, ${fps} fps grid" \
      "ffmpeg <paper canvas, nook on the top edge, controls below> per frame" \
      "ffmpeg <840 wide, palettegen + paletteuse> $here/nook-playground.gif"
  else
    mkdir -p "$tmp/raw" "$tmp/frame" "$tmp/seq"
    for n in 3 2 1; do printf '%s... ' "$n"; sleep 1; done; echo "go"

    # The controls are pressed alongside the capture loop, spread evenly over
    # the take with a beat of held frames at either end, so the GIF opens on a
    # settled shot before the first segment moves. The poker only ever touches
    # the app this script launched; it is given that pid and nothing else.
    poke_job=""
    if (( drive )); then
      IFS=, read -r -a steps <<<"$drive_steps"
      # One beat before the first press and a beat and a half after the last,
      # less the settle the poker spends building the tree before it presses
      # anything. The capture loop takes a moment to reach its rate, so a step
      # timed to the very end of --seconds would fall off the take.
      read -r step_delay lead < <(
        python3 -c "
delay = max(0.6, $seconds / (${#steps[@]} + 1.5))
print(delay, max(0.2, delay - $settle))
"
      )
      (
        sleep "$lead"
        "$tmp/playground-poke" "$pid" --settle "$settle" --delay "$step_delay" "${steps[@]}"
      ) >/dev/null 2>"$tmp/poke.log" &
      poke_job=$!
      echo "driving: ${steps[*]} every ${step_delay}s"
    fi

    frame=0
    SECONDS=0
    while (( SECONDS < seconds )); do
      index="$(printf '%05d' "$frame")"
      # Both windows at once: the pair is only as fresh as its slower half, and
      # in parallel that half is the whole cost of the frame.
      screencapture -x -o -l "$panel_id" "$tmp/raw/$index-panel.png" 2>/dev/null &
      panel_job=$!
      screencapture -x -o -l "$controls_id" "$tmp/raw/$index-controls.png" 2>/dev/null &
      controls_job=$!
      wait "$panel_job" || true
      wait "$controls_job" || true

      # The panel's window id changes when the nook expands or its window is
      # rebuilt, and a capture of an id that no longer exists writes nothing.
      # Re-resolve both ids and carry the previous frame's half over, so the
      # take neither dies here nor freezes on a stale window.
      if [[ ! -s "$tmp/raw/$index-panel.png" || ! -s "$tmp/raw/$index-controls.png" ]]; then
        read -r panel_id controls_id <<<"$(window_ids "$pid" 2>/dev/null || echo "$panel_id $controls_id")"
        previous="$(printf '%05d' $(( frame - 1 )))"
        for part in panel controls; do
          [[ -s "$tmp/raw/$index-$part.png" ]] && continue
          if (( frame > 0 )) && [[ -s "$tmp/raw/$previous-$part.png" ]]; then
            cp "$tmp/raw/$previous-$part.png" "$tmp/raw/$index-$part.png"
          else
            rm -f "$tmp/raw/$index-panel.png" "$tmp/raw/$index-controls.png"
            break
          fi
        done
        [[ -s "$tmp/raw/$index-panel.png" ]] || continue
      fi
      frame=$(( frame + 1 ))
    done
    if [[ -n "$poke_job" ]]; then
      wait "$poke_job" || echo "some controls were not pressed; see below" >&2
      if [[ -s "$tmp/poke.log" ]]; then cat "$tmp/poke.log" >&2; fi
    fi
    (( frame > 1 )) || { echo "the capture loop got no usable pairs" >&2; exit 1; }

    # The panel capture is mostly transparent margin, the same as the still's.
    for panel_png in "$tmp/raw"/*-panel.png; do
      "$tmp/trim-alpha" "$panel_png" "${panel_png%-panel.png}-panel-trimmed.png"
    done

    read -r canvas_w canvas_h fps < <(
      python3 "$tmp/plan-clip.py" "$tmp/raw" "$fps" "$margin" "$gap" "$tmp/plan.txt"
    )
    echo "clip: $(( $(wc -l <"$tmp/plan.txt") )) frames at $fps fps on a ${canvas_w}x${canvas_h} canvas"

    # Each pair onto paper in the still's layout: the nook flush with the top
    # edge, the controls window centred below it. The canvas is sized once, from
    # the largest panel in the take, so an expand does not shift the frame.
    order=1
    while read -r stem; do
      if [[ ! -f "$tmp/frame/$stem.png" ]]; then
        ffmpeg -y -hide_banner -loglevel error \
          -i "$tmp/raw/$stem-panel-trimmed.png" -i "$tmp/raw/$stem-controls.png" \
          -filter_complex "color=$paper:s=${canvas_w}x${canvas_h}[bg];\
[bg][0:v]overlay=(W-w)/2:0:format=auto[a];\
[a][1:v]overlay=(W-w)/2:H-h-$margin:format=auto,format=rgb24" \
          -frames:v 1 -update 1 "$tmp/frame/$stem.png"
      fi
      ln -sf "$tmp/frame/$stem.png" "$(printf '%s/%05d.png' "$tmp/seq" "$order")"
      order=$(( order + 1 ))
    done <"$tmp/plan.txt"

    # One global 256-colour palette, the same recipe as the hero GIF in
    # make-readme-media.sh: diff_mode=rectangle only re-encodes the region that
    # changes, which matters because most of this frame holds still.
    ffmpeg -y -hide_banner -loglevel error \
      -framerate "$fps" -start_number 1 -i "$tmp/seq/%05d.png" \
      -filter_complex "scale=840:-2:flags=lanczos,setsar=1,split[a][b];\
[a]palettegen=max_colors=256:stats_mode=full[p];\
[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
      -r "$fps" -loop 0 "$here/nook-playground.gif"
  fi
fi

(( dry_run )) || {
  echo "wrote:"
  ls -la "$here"/nook-playground.* 2>/dev/null || true
  echo
  echo "Check the GIF is under 3 MB. If it is not, drop --seconds or --fps, or"
  echo "record a smaller controls window, then re-run."
}
