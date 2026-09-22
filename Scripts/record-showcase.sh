#!/bin/zsh
# Record each ShowcaseNook scene for the site into site/src/assets/showcase/.
#
# Per scene this writes:
#   <scene>.png    the expanded nook, captured by window id, so no other window can
#                  leak in and the background is real transparency (no key)
#   <scene>.webm   VP9 with alpha: the collapsed pill, the expand, then a ~3 s hold
#
# `screencapture -v` records the screen or a rectangle only; it does not take -l
# (a window id). So the clip is recorded from a tight rectangle around the nook on
# the cream backdrop from reel-backdrop.swift, and the cream is keyed out the way
# build-landing-reel.sh does it: the capture decodes as #EFECE2, and the top three
# rows drift off that colour, so they get a looser key than the rest. The key alone
# leaves the panel's glow over the cream (a warm halo while it expands) and a light
# antialiased edge, so unmix-backdrop.swift then solves every pixel outside the panel
# for the colour and alpha that, over the cream, would give what was captured.
#
# This puts windows on screen and moves the pointer. Run it when the Mac is free.
#
# Usage:
#   Scripts/record-showcase.sh [--dry-run] [scene ...]
#   scenes: player agenda timer progress shelf hud compact (default: all)
#
# --dry-run prints every step instead of running it.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/site/src/assets/showcase"
bin="$root/.build/debug"
cream=0xEFECE2

dry_run=0
scenes=()
for argument in "$@"; do
  case "$argument" in
    --dry-run) dry_run=1 ;;
    player|agenda|timer|progress|shelf|hud|compact) scenes+=("$argument") ;;
    *) echo "unknown argument: $argument" >&2; exit 2 ;;
  esac
done
(( ${#scenes[@]} == 0 )) && scenes=(player agenda timer progress shelf hud compact)

# Seconds from launch to the expand, and how long each clip runs. The capture starts
# `settle` seconds after launch, so the expand lands about 1.4 s into the clip, with the
# pill on camera first. The clip then holds the open nook for about 3 s.
settle=2.0
expand_after=3.4
clip_seconds=6

# The content column width of each scene (ShowcaseScene.expandedWidth), so the capture
# rectangle is only as wide as the nook plus a margin.
typeset -A column_width=(
  player 640 compact 640 agenda 560 timer 440 progress 500 shelf 548 hud 380
)

run() {
  if (( dry_run )); then
    print -r -- "+ $*"
  else
    "$@"
  fi
}

tmp="$(mktemp -d)"
cleanup() {
  if (( ! dry_run )); then
    pkill -x ShowcaseNook >/dev/null 2>&1 || true
    pkill -x reel-backdrop >/dev/null 2>&1 || true
  fi
  rm -rf "$tmp"
}
trap cleanup EXIT

# Crops a window capture to its visible pixels, dropping the transparent margin.
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

echo "building ShowcaseNook and the capture helpers..."
run swift build --package-path "$root" --product ShowcaseNook
for helper in nook-windows park-cursor reel-backdrop unmix-backdrop; do
  run swiftc -O -o "$tmp/$helper" "$root/Scripts/$helper.swift"
done
run swiftc -O -o "$tmp/trim-alpha" "$tmp/trim-alpha.swift"
run mkdir -p "$out"

echo "opening the cream backdrop"
if (( dry_run )); then
  print -r -- "+ $tmp/reel-backdrop &"
else
  "$tmp/reel-backdrop" >/dev/null 2>&1 &
  sleep 0.6
fi

wait_for_pid() {
  local tries=40 pid=""
  while (( tries-- > 0 )); do
    pid="$(pgrep -n -x ShowcaseNook || true)"
    [[ -n "$pid" ]] && { echo "$pid"; return 0; }
    sleep 0.25
  done
  echo "timed out waiting for ShowcaseNook" >&2
  return 1
}

# Prints "<window id> <x>,<y>,<w>,<h>": the nook's panel (the highest window the process
# owns) and a rectangle around it, `column + chrome + margin` wide and 420 tall from the
# top of the screen.
panel_and_rect() {
  local pid="$1" width="$2"
  "$tmp/nook-windows" "$pid" | python3 -c '
import json, sys
width = int(sys.argv[1])
wins = json.load(sys.stdin)["windows"]
if not wins:
    raise SystemExit("no windows")
top = max(w["layer"] for w in wins)
panel = max((w for w in wins if w["layer"] == top), key=lambda w: w["w"] * w["h"])
# column + edge padding and content insets (2 x 16) + notch ears (2 x 19) + margin
rect_w = width + 70 + 160
cx = panel["x"] + panel["w"] / 2
x = max(0, int(cx - rect_w / 2))
y = panel["y"]
print(panel["id"], f"{x},{y},{rect_w},420")
' "$width"
}

record_scene() {
  local scene="$1"
  local raw="$tmp/$scene.mov"
  local still="$tmp/$scene-window.png"
  local args=(--scene "$scene")
  # The compact scene is about the collapsed pill, so it never opens.
  if [[ "$scene" != compact ]]; then
    args+=(--expand-after "$expand_after" --keep-open)
  fi

  echo "== $scene"
  run pkill -x ShowcaseNook || true
  if (( dry_run )); then
    print -r -- "+ $bin/ShowcaseNook ${args[*]} &"
    print -r -- "+ sleep $settle; nook-windows <pid> -> panel id and a ${column_width[$scene]}pt-column rectangle"
    print -r -- "+ $tmp/park-cursor"
    print -r -- "+ screencapture -x -v -V $clip_seconds -R <rect> $raw"
    print -r -- "+ screencapture -x -o -l <panel id> $still"
    print -r -- "+ $tmp/trim-alpha $still $out/$scene.png"
    print -r -- "+ ffmpeg -i $raw <cream key> | unmix-backdrop | ffmpeg -c:v libvpx-vp9 -pix_fmt yuva420p $out/$scene.webm"
    return 0
  fi

  "$bin/ShowcaseNook" "${args[@]}" >/dev/null 2>&1 &
  local pid window rect
  pid="$(wait_for_pid)"
  sleep "$settle"
  read -r window rect <<<"$(panel_and_rect "$pid" "${column_width[$scene]}")"
  echo "panel $window, recording $rect"

  # `screencapture -v` always draws the pointer, so park it away from the top strip.
  "$tmp/park-cursor" >/dev/null 2>&1 || true
  screencapture -x -v -V "$clip_seconds" -R "$rect" "$raw"

  local key_filter="format=gbrap,split[top][body];\
[top]crop=iw:3:0:0,colorkey=$cream:0.08:0.0[topk];\
[body]crop=iw:ih-3:0:3,colorkey=$cream:0.02:0.0[bodyk];\
[topk][bodyk]vstack"

  # The window capture is the panel alone, with real transparency around the chrome;
  # --keep-open still holds an expanded scene open here, and the compact scene is its pill.
  screencapture -x -o -l "$window" "$still"
  "$tmp/trim-alpha" "$still" "$out/$scene.png"

  local size
  size="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$raw")"
  ffmpeg -hide_banner -loglevel error -i "$raw" \
    -vf "fps=30,$key_filter" -an -f rawvideo -pix_fmt rgba - \
    | "$tmp/unmix-backdrop" "${size%x*}" "${size#*x}" "${cream#0x}" \
    | ffmpeg -y -hide_banner -loglevel error -f rawvideo -pix_fmt rgba -s "$size" -r 30 -i - \
      -c:v libvpx-vp9 -pix_fmt yuva420p -auto-alt-ref 0 -crf 30 -b:v 0 -row-mt 1 \
      "$out/$scene.webm"

  pkill -x ShowcaseNook >/dev/null 2>&1 || true
  sleep 0.5
}

for scene in "${scenes[@]}"; do
  record_scene "$scene"
done

(( dry_run )) || { echo "wrote:"; ls -la "$out"; }
