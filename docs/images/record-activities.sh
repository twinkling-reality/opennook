#!/bin/bash
# Record the live activity media: ShowcaseNook's `compact` scene, where the song holds
# the pill and the focus session waits in a capsule beside it, then the song's peek,
# then the nook opened onto the song.
#
# Each state is its own launch: plain, `--peek`, and `--open-activity`. The last two
# alert the song activity shortly after launch and hold the alert, so every frame is
# the running app in that state. The GIF cuts from state to state; it does not invent
# the transitions between them.
#
# Every capture is `screencapture -x -o -l<id>` of the nook panel window this
# script's own process launched. No rectangle of the screen is recorded, so no
# other window can appear. The paper behind the nook is painted by ffmpeg.
#
# ShowcaseNook saves its preferences to the `ShowcaseNook` defaults domain and its
# module's domain. Both are exported before the first launch and put back afterwards
# (or deleted, if they did not exist), so a run leaves no setting behind.
#
# Outputs:
#   docs/images/nook-activities.gif                the pill, the peek, the open nook
#   site/src/assets/activities/nook-activities.png the pill and the peek side by side
#
# Usage:
#   docs/images/record-activities.sh [--dry-run]
#
# Requires ffmpeg (brew install ffmpeg) and the Xcode command line tools.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
bin="$root/.build/debug"
site_out="$root/site/src/assets/activities"
paper=0xEAF1F8
domains=(ShowcaseNook opennook.module.com.opennook.example.showcase)

# The states in order, with the flags that put the scene in each, and how long the GIF
# holds each one.
states=(pill peek open)
flags_pill=""
flags_peek="--peek"
flags_open="--open-activity"
hold_pill=1.8
hold_peek=2.4
hold_open=2.8
# Seconds from launch to the capture: the alert fires after 0.9 s and needs to settle.
settle=3
# The canvas margin around the nook. The top has none: the nook hangs from the
# canvas's top edge, the way it hangs from the screen, as in the other README media.
margin=72
dry_run=0

while (( $# )); do
  case "$1" in
    --dry-run) dry_run=1 ;;
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

tmp="$(mktemp -d)"
app_pid=""
restore_defaults() {
  for domain in "${domains[@]}"; do
    if [[ -f "$tmp/defaults/$domain.plist" ]]; then
      defaults import "$domain" "$tmp/defaults/$domain.plist"
    elif [[ -f "$tmp/defaults/$domain.absent" ]]; then
      defaults delete "$domain" >/dev/null 2>&1 || true
    fi
  done
}
cleanup() {
  if [[ -n "$app_pid" ]]; then
    kill "$app_pid" >/dev/null 2>&1 || true
    wait "$app_pid" 2>/dev/null || true
  fi
  (( dry_run )) || restore_defaults
  rm -rf "$tmp"
}
trap cleanup EXIT

if pgrep -x ShowcaseNook >/dev/null; then
  echo "ShowcaseNook is already running; quit it first" >&2
  exit 1
fi

# Crops captures to one rectangle: the union of their visible pixels, down to the
# faintest edge, so the nook stays put from frame to frame.
cat >"$tmp/trim-union.swift" <<'SWIFT'
import AppKit

let paths = Array(CommandLine.arguments.dropFirst())
var images: [CGImage] = []
var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
for path in paths {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else { exit(1) }
    images.append(image)
    let width = image.width
    let height = image.height
    var pixels = [UInt8](repeating: 0, count: width * height * 4)
    let context = CGContext(
        data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
    for y in 0..<height {
        for x in 0..<width where pixels[(y * width + x) * 4 + 3] > 0 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
guard maxX >= minX else { exit(1) }
// Even sizes, for the encoders.
let width = (maxX - minX + 2) / 2 * 2
let height = (maxY - minY + 2) / 2 * 2
for (path, image) in zip(paths, images) {
    guard let cropped = image.cropping(to: CGRect(x: minX, y: minY, width: width, height: height)) else { exit(1) }
    let rep = NSBitmapImageRep(cgImage: cropped)
    try rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
}
SWIFT

echo "building ShowcaseNook and the capture helpers..."
run swift build --package-path "$root" --product ShowcaseNook
run swiftc -O -o "$tmp/nook-windows" "$root/Scripts/nook-windows.swift"
run swiftc -O -o "$tmp/trim-union" "$tmp/trim-union.swift"

echo "saving the ShowcaseNook preferences"
mkdir -p "$tmp/defaults" "$tmp/frames"
for domain in "${domains[@]}"; do
  if defaults read "$domain" >/dev/null 2>&1; then
    run defaults export "$domain" "$tmp/defaults/$domain.plist"
  else
    touch "$tmp/defaults/$domain.absent"
  fi
done

# The visible nook panel: the app's window on layer 33 that is on screen.
nook_window() {
  local json count i
  json="$("$tmp/nook-windows" "$1")"
  count="$(plutil -extract windows raw -o - - <<<"$json" 2>/dev/null || echo 0)"
  for (( i = 0; i < count; i++ )); do
    if [[ "$(plutil -extract "windows.$i.layer" raw -o - - <<<"$json")" == 33 ]]; then
      plutil -extract "windows.$i.id" raw -o - - <<<"$json"
    fi
  done | tail -1
}

for state in "${states[@]}"; do
  flags_name="flags_$state"
  echo "capturing $state"
  if (( dry_run )); then
    printf '+ %s\n' "$bin/ShowcaseNook --scene compact ${!flags_name} &"
    printf '+ %s\n' "screencapture -x -o -l<nook> $tmp/frames/$state.png"
    continue
  fi
  # shellcheck disable=SC2086
  "$bin/ShowcaseNook" --scene compact ${!flags_name} >/dev/null 2>&1 &
  app_pid=$!
  window=""
  for _ in $(seq 1 60); do
    window="$(nook_window "$app_pid")"
    [[ -n "$window" ]] && break
    sleep 0.25
  done
  [[ -n "$window" ]] || { echo "the nook panel never appeared" >&2; exit 1; }
  sleep "$settle"
  # The window can be rebuilt as the nook opens, so look it up again before capturing.
  window="$(nook_window "$app_pid")"
  screencapture -x -o -l"$window" "$tmp/frames/$state.png"
  kill "$app_pid"
  wait "$app_pid" 2>/dev/null || true
  app_pid=""
done
(( dry_run )) || restore_defaults

# Each capture on paper, hanging from the top edge. The paper is painted opaque
# (geq, #EAF1F8) under the capture, so soft edges blend into it.
paper_frame() {
  run ffmpeg -y -hide_banner -loglevel error -i "$1" \
    -filter_complex "[0:v]format=rgba,pad=iw+2*$margin:ih+$margin:$margin:0:color=$paper@0,split[n][s];\
[s]geq=r='234':g='241':b='248':a='255'[bg];[bg][n]overlay=format=rgb,format=rgb24" \
    -frames:v 1 -update 1 "$2"
}

# ---- GIF ---------------------------------------------------------------------
# All three states cropped to one rectangle (the open nook's), so the pill and the
# peek sit where they do on screen, under the notch, and the nook grows from them.
mkdir -p "$tmp/gif"
for state in "${states[@]}"; do run cp "$tmp/frames/$state.png" "$tmp/gif/$state.png"; done
run "$tmp/trim-union" "$tmp/gif/pill.png" "$tmp/gif/peek.png" "$tmp/gif/open.png"
inputs=()
for state in "${states[@]}"; do
  hold_name="hold_$state"
  paper_frame "$tmp/gif/$state.png" "$tmp/gif/$state-paper.png"
  inputs+=(-loop 1 -t "${!hold_name}" -i "$tmp/gif/$state-paper.png")
done
run ffmpeg -y -hide_banner -loglevel error "${inputs[@]}" \
  -filter_complex "[0:v][1:v][2:v]concat=n=3:v=1:a=0,fps=10,scale=840:-2:flags=lanczos,setsar=1,split[a][b];\
[a]palettegen=max_colors=256:stats_mode=full[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
  -loop 0 "$tmp/nook-activities.gif"
run mv "$tmp/nook-activities.gif" "$here/nook-activities.gif"

# ---- still -------------------------------------------------------------------
# The pill and the peek side by side, cropped to their own rectangle, for the Live
# activities guide. The site's image pipeline scales it.
mkdir -p "$tmp/still"
run cp "$tmp/frames/pill.png" "$tmp/still/pill.png"
run cp "$tmp/frames/peek.png" "$tmp/still/peek.png"
run "$tmp/trim-union" "$tmp/still/pill.png" "$tmp/still/peek.png"
paper_frame "$tmp/still/pill.png" "$tmp/still/pill-paper.png"
paper_frame "$tmp/still/peek.png" "$tmp/still/peek-paper.png"
run mkdir -p "$site_out"
run ffmpeg -y -hide_banner -loglevel error -i "$tmp/still/pill-paper.png" -i "$tmp/still/peek-paper.png" \
  -filter_complex "[0:v][1:v]hstack=inputs=2,format=rgb24" \
  -frames:v 1 -update 1 -compression_level 100 "$site_out/nook-activities.png"

(( dry_run )) || ls -la "$here/nook-activities.gif" "$site_out/nook-activities.png"
