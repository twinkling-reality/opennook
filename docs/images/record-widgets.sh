#!/bin/bash
# Record the widget and shared element media: ShowcaseNook's `board` scene (a widget from
# each of three resident modules on one board), and the `compact` scene opening onto the
# song, its cover moving from the pill into the player.
#
# The board is one capture of the running app. The cover's move lasts about half a second,
# longer than a window capture takes but not by much, so the move is recorded slowed: the
# run uses a theme whose conversion spring is `slow` times slower (response times `slow`,
# the same damping), and the GIF plays the frames back `slow` times faster, by the time each
# was taken. A spring scaled in time this way traces the same motion, so the GIF shows the
# real move, sampled more densely. The pill before and the player after are held.
#
# Every capture is `screencapture -x -o -l<id>` of the nook panel window this script's own
# process launched. No rectangle of the screen is recorded, so no other window can appear.
# The paper behind the nook is painted by ffmpeg.
#
# ShowcaseNook saves its preferences to its defaults domains. Each is exported before the
# first launch and put back exactly afterwards (deleted first, since an import only adds
# keys), or deleted if it did not exist.
#
# Outputs:
#   docs/images/nook-shared.gif                 the cover moving from the pill into the player
#   site/src/assets/widgets/nook-board.png      the board, for the Widgets and boards guide
#
# Usage:
#   docs/images/record-widgets.sh [--dry-run]
#
# Requires ffmpeg (brew install ffmpeg) and the Xcode command line tools.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
bin="$root/.build/debug"
site_out="$root/site/src/assets/widgets"
paper=0xEAF1F8
domains=(
  ShowcaseNook
  opennook.module.com.opennook.example.showcase
  opennook.module.com.opennook.example.showcase.player
  opennook.module.com.opennook.example.showcase.agenda
  opennook.module.com.opennook.example.showcase.timer
  opennook.module.com.opennook.example.showcase.board
)
# How many times slower the recorded move runs than the real one.
slow=5
# When the alert opens the nook, from launch: late enough for the pill's slots, which arrive on
# the slowed curve too, to have settled. And how long to record from launch.
alert_after=4
record_until=8
# How long the GIF holds the pill before the move and the player after it.
hold_before=1.2
hold_after=2.2
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
    defaults delete "$domain" >/dev/null 2>&1 || true
    if [[ -f "$tmp/defaults/$domain.plist" ]]; then
      defaults import "$domain" "$tmp/defaults/$domain.plist"
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

# Crops captures to one rectangle: the union of their visible pixels, so the nook stays put
# from frame to frame.
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
mkdir -p "$tmp/defaults" "$tmp/board" "$tmp/move"
for domain in "${domains[@]}"; do
  if defaults read "$domain" >/dev/null 2>&1; then
    run defaults export "$domain" "$tmp/defaults/$domain.plist"
  fi
done

# The slowed conversion: the default `transition.convert` spring, `slow` times slower.
cat >"$tmp/slow.json" <<JSON
{
  "format": "opennook.theme",
  "version": 1,
  "name": "Slowed",
  "tokens": {
    "transition.convert": { "response": $(echo "0.54 * $slow" | bc -l), "dampingFraction": 0.86 }
  }
}
JSON

# The visible nook panel: the app's window on layer 33.
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

launch() {
  # shellcheck disable=SC2068
  "$bin/ShowcaseNook" $@ >/dev/null 2>&1 &
  app_pid=$!
  window=""
  for _ in $(seq 1 80); do
    window="$(nook_window "$app_pid")"
    [[ -n "$window" ]] && break
    sleep 0.05
  done
  [[ -n "$window" ]] || { echo "the nook panel never appeared" >&2; exit 1; }
}

quit() {
  kill "$app_pid"
  wait "$app_pid" 2>/dev/null || true
  app_pid=""
}

if (( dry_run )); then
  printf '+ %s\n' "$bin/ShowcaseNook --scene board --keep-open &" "screencapture -x -o -l<nook> board.png"
  printf '+ %s\n' "$bin/ShowcaseNook --scene compact --open-activity --theme slow.json &" "screencapture -x -o -l<nook> (repeated)"
else
  echo "capturing the board"
  launch --scene board --keep-open
  sleep 3
  window="$(nook_window "$app_pid")"
  screencapture -x -o -l"$window" "$tmp/board/board.png"
  quit

  echo "capturing the cover's move, $slow times slowed"
  start=$(python3 -c 'import time; print(time.time())')
  launch --scene compact --open-activity --alert-after "$alert_after" --theme "$tmp/slow.json"
  n=0
  while :; do
    now=$(python3 -c "import time; print(time.time() - $start)")
    python3 -c "import sys; sys.exit(0 if $now > $record_until else 1)" && break
    window="$(nook_window "$app_pid")"
    # The panel can be rebuilt between the lookup and the capture; that frame is skipped.
    if [[ -n "$window" ]] && screencapture -x -o -l"$window" "$tmp/move/$(printf %04d $n).png" 2>/dev/null; then
      echo "$now" >"$tmp/move/$(printf %04d $n).t"
      n=$((n + 1))
    fi
  done
  quit
  restore_defaults
fi

paper_frame() {
  run ffmpeg -y -hide_banner -loglevel error -i "$1" \
    -filter_complex "[0:v]format=rgba,pad=iw+2*$margin:ih+$margin:$margin:0:color=$paper@0,split[n][s];\
[s]geq=r='234':g='241':b='248':a='255'[bg];[bg][n]overlay=format=rgb,format=rgb24" \
    -frames:v 1 -update 1 "$2"
}

# ---- board still -------------------------------------------------------------
run "$tmp/trim-union" "$tmp/board/board.png"
paper_frame "$tmp/board/board.png" "$tmp/board/board-paper.png"
run mkdir -p "$site_out"
run ffmpeg -y -hide_banner -loglevel error -i "$tmp/board/board-paper.png" \
  -frames:v 1 -update 1 -compression_level 100 "$site_out/nook-board.png"

# ---- shared element GIF -------------------------------------------------------
# Every frame cropped to one rectangle, put on paper, and given the real time it stands for.
if (( ! dry_run )); then
  frames=("$tmp"/move/*.png)
  "$tmp/trim-union" "${frames[@]}"
  for frame in "${frames[@]}"; do paper_frame "$frame" "${frame%.png}-paper.png"; done
  # The last frame before the move stands for the pill and is held; every frame from the move
  # on lasts the real time it stands for; the last is held as the player.
  python3 - "$tmp/move" "$alert_after" "$slow" "$hold_before" "$hold_after" <<'PY' >"$tmp/move/list.txt"
import glob, sys
folder, alert_after, slow, hold_before, hold_after = sys.argv[1], *map(float, sys.argv[2:])
frames = sorted(glob.glob(f"{folder}/[0-9][0-9][0-9][0-9].png"))
times = [float(open(f[:-4] + ".t").read()) for f in frames]
before = [i for i, t in enumerate(times) if t < alert_after - 0.2]
keep = ([before[-1]] if before else []) + [i for i, t in enumerate(times) if t >= alert_after - 0.2]
for n, i in enumerate(keep):
    if n == 0 and before:
        duration = hold_before
    elif n + 1 < len(keep):
        duration = (times[keep[n + 1]] - times[i]) / slow
    else:
        duration = hold_after
    print(f"file '{frames[i][:-4]}-paper.png'\nduration {duration:.3f}")
print(f"file '{frames[keep[-1]][:-4]}-paper.png'")
PY
fi
run ffmpeg -y -hide_banner -loglevel error -f concat -safe 0 -i "$tmp/move/list.txt" \
  -filter_complex "fps=30,scale=840:-2:flags=lanczos,setsar=1,split[a][b];\
[a]palettegen=max_colors=256:stats_mode=full[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
  -loop 0 "$tmp/nook-shared.gif"
run mv "$tmp/nook-shared.gif" "$here/nook-shared.gif"

(( dry_run )) || ls -la "$here/nook-shared.gif" "$site_out/nook-board.png"
