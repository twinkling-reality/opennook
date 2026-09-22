#!/bin/bash
# Record the PlaygroundNook media for the root README: one still and one short
# GIF of the controls window beside the live nook.
#
# The point of the playground is that the window on the desk changes the real
# nook above it, so both are in frame. Everything else here follows
# Scripts/record-showcase.sh: the app is captured by window id so no other
# window can leak in, the pointer is parked for the stills, and the surface
# behind everything is a backdrop window rather than whatever the desk holds.
#
# Two differences from record-showcase.sh, both forced by the controls window:
#
#   1. Scripts/reel-backdrop.swift sits above normal windows, which would cover
#      the controls window, and it paints the recording cream that the showcase
#      pipeline keys out afterwards. This script uses playground-backdrop.swift
#      instead: one level below normal windows, painted the README paper
#      (#EAF1F8) directly. Nothing is keyed or unmixed here.
#   2. `screencapture -v` takes a rectangle, not a window id, so the clip is a
#      rectangle around both windows. The still is still two window-id captures
#      (the nook panel, the controls window) composited onto paper, which is
#      sharper and cannot pick up a stray window between them.
#
# This puts windows on screen, moves the pointer, and records the screen. Run it
# when the Mac is free, with other apps hidden (Command-Option-H) so nothing can
# surface over the backdrop.
#
# Outputs, both in docs/images/:
#   nook-playground.png   the controls window under the expanded nook, on paper
#   nook-playground.gif   ~8 s of a control being changed and the nook following
#
# Usage:
#   docs/images/record-playground.sh [--dry-run] [--yes] [--sample <id>]
#                                    [--seconds <n>] [still|clip|all]
#
#   --sample   a built-in playground look: defaults, media, glass, glance, call
#              (default: glass). The nook's own content is the playground home
#              view either way; the sample is what makes it look like a product
#              rather than a settings screen.
#   --yes      skip the "arrange the window" pause before each capture.
#   --dry-run  print every step instead of running it.
#
# Requires ffmpeg (brew install ffmpeg) and the Xcode command line tools.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
bin="$root/.build/debug"
paper=0xEAF1F8

sample=glass
seconds=8
what=all
dry_run=0
assume_yes=0

while (( $# )); do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --yes) assume_yes=1 ;;
    --sample) sample="${2:?--sample needs an id}"; shift ;;
    --seconds) seconds="${2:?--seconds needs a number}"; shift ;;
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

echo "building PlaygroundNook and the capture helpers..."
run swift build --package-path "$root" --product PlaygroundNook
run swiftc -O -o "$tmp/nook-windows" "$root/Scripts/nook-windows.swift"
run swiftc -O -o "$tmp/park-cursor" "$root/Scripts/park-cursor.swift"
run swiftc -O -o "$tmp/playground-backdrop" "$here/playground-backdrop.swift"
run swiftc -O -o "$tmp/trim-alpha" "$tmp/trim-alpha.swift"

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

# Prints "<panel id> <controls id> <x>,<y>,<w>,<h>": the nook panel (the highest
# window the process owns), the controls window (the largest ordinary window),
# and a rectangle covering both with a margin, clamped to the main display.
windows_and_rect() {
  local pid="$1"
  "$tmp/nook-windows" "$pid" | python3 -c '
import json, subprocess, sys

wins = json.load(sys.stdin)["windows"]
if not wins:
    raise SystemExit("no windows")
top = max(w["layer"] for w in wins)
panel = max((w for w in wins if w["layer"] == top), key=lambda w: w["w"] * w["h"])
ordinary = [w for w in wins if w["layer"] == 0 and w["id"] != panel["id"]]
if not ordinary:
    raise SystemExit("no controls window: launch without --hide-controls")
controls = max(ordinary, key=lambda w: w["w"] * w["h"])

pad = 28
left = max(0, min(panel["x"], controls["x"]) - pad)
top_y = max(0, min(panel["y"], controls["y"]))
right = max(panel["x"] + panel["w"], controls["x"] + controls["w"]) + pad
bottom = max(panel["y"] + panel["h"], controls["y"] + controls["h"]) + pad
print(panel["id"], controls["id"], f"{left},{top_y},{int(right - left)},{int(bottom - top_y)}")
'
}

if (( dry_run )); then
  printf '+ %s\n' "nook-windows <pid> -> panel id, controls id, union rectangle"
  panel_id=PANEL; controls_id=CONTROLS; rect=RECT
else
  pid="$(wait_for_pid)"
  sleep 2.5
  read -r panel_id controls_id rect <<<"$(windows_and_rect "$pid")"
  echo "panel $panel_id, controls $controls_id, rectangle $rect"
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
    margin=48
    gap=40
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
# A rectangle around both windows while a control is changed. The pointer is in
# frame on purpose here: the GIF is about the act of changing something. The
# backdrop is already paper, so this is only a resize and a palette pass.
if [[ "$what" == clip || "$what" == all ]]; then
  pause "Ready to record ${seconds}s. When the countdown ends, change one visible control (Appearance -> Material, or Theme -> Accent) slowly, then stop. Do not move the pointer out of the rectangle."
  echo "== clip"
  if (( dry_run )); then
    printf '+ %s\n' "screencapture -x -v -V $seconds -R $rect $tmp/playground.mov" \
      "ffmpeg <12 fps, 840 wide, palettegen + paletteuse> $here/nook-playground.gif"
  else
    for n in 3 2 1; do printf '%s... ' "$n"; sleep 1; done; echo "go"
    screencapture -x -v -V "$seconds" -R "$rect" "$tmp/playground.mov"

    # One global 256-colour palette, the same recipe as the hero GIF in
    # make-readme-media.sh: diff_mode=rectangle only re-encodes the region that
    # changes, which matters because most of this frame holds still.
    ffmpeg -y -hide_banner -loglevel error -i "$tmp/playground.mov" \
      -filter_complex "fps=12,scale=840:-2:flags=lanczos,setsar=1,split[a][b];\
[a]palettegen=max_colors=256:stats_mode=full[p];\
[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
      -loop 0 "$here/nook-playground.gif"
  fi
fi

(( dry_run )) || {
  echo "wrote:"
  ls -la "$here"/nook-playground.* 2>/dev/null || true
  echo
  echo "Check the GIF is under 3 MB. If it is not, drop --seconds or record a"
  echo "smaller controls window, then re-run."
}
