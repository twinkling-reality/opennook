#!/bin/bash
# Record the theme media: one ShowcaseNook scene painted by each theme file in
# Examples/Themes, plus the framework's own look.
#
# ShowcaseNook runs once, with `--theme` pointing at a scratch file it watches.
# The script copies each theme over that file in turn and captures the nook after
# the reload, so every frame is the running app re-themed live, with no relaunch.
# The reload has no transition of its own, and the GIF does not add one: it cuts
# from theme to theme.
#
# Every capture is `screencapture -x -o -l<id>` of the nook panel window this
# script's own process launched. No rectangle of the screen is recorded, so no
# other window can appear. The paper behind the nook is painted by ffmpeg.
#
# ShowcaseNook saves its preferences to the `ShowcaseNook` defaults domain and its
# module's domain. Both are exported before the launch and put back afterwards (or
# deleted, if they did not exist), so a run leaves no setting behind.
#
# Outputs:
#   docs/images/nook-themes.gif               the scene cycling through the themes
#   site/src/assets/themes/nook-themes.png    the same captures in a 2x2 grid
#
# Usage:
#   docs/images/record-themes.sh [--dry-run] [--scene <id>]
#
#   --scene    the ShowcaseNook scene to paint (default: agenda, which reads its
#              labels and the day's color from the theme).
#   --dry-run  print every step instead of running it.
#
# Requires ffmpeg (brew install ffmpeg) and the Xcode command line tools.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
bin="$root/.build/debug"
themes_dir="$root/Examples/Themes"
site_out="$root/site/src/assets/themes"
paper=0xEAF1F8
domains=(ShowcaseNook opennook.module.com.opennook.example.showcase)

# Shown in this order; "standard" is the framework's own look, an empty theme file.
themes=(standard dusk aurora ember)
scene=agenda
dry_run=0
# Seconds to hold each theme in the GIF, and to wait for a reload before capturing.
hold=2.2
settle=1.6
# The canvas margin around the nook. The top has none: the nook hangs from the
# canvas's top edge, the way it hangs from the screen, as in the other README media.
margin=72

while (( $# )); do
  case "$1" in
    --dry-run) dry_run=1 ;;
    --scene) scene="${2:?--scene needs an id}"; shift ;;
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

for name in "${themes[@]}"; do
  [[ "$name" == standard || -f "$themes_dir/$name.json" ]] || { echo "missing $themes_dir/$name.json" >&2; exit 1; }
done
if pgrep -x ShowcaseNook >/dev/null; then
  echo "ShowcaseNook is already running; quit it first" >&2
  exit 1
fi

# Crops every capture to the same rectangle: the union of their visible pixels,
# down to the faintest edge of a shadow, so no shadow is cut off in a straight line.
# One rectangle for all of them keeps the nook in the same place in every frame,
# however far each theme's shadow reaches.
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
mkdir -p "$tmp/defaults" "$tmp/live" "$tmp/frames"
for domain in "${domains[@]}"; do
  if defaults read "$domain" >/dev/null 2>&1; then
    run defaults export "$domain" "$tmp/defaults/$domain.plist"
  else
    touch "$tmp/defaults/$domain.absent"
  fi
done

# The standard theme: the envelope and nothing else.
printf '{\n  "format": "opennook.theme",\n  "version": 1\n}\n' >"$tmp/standard.json"
theme_file() {
  [[ "$1" == standard ]] && echo "$tmp/standard.json" || echo "$themes_dir/$1.json"
}
cp "$(theme_file "${themes[0]}")" "$tmp/live/theme.json"

echo "launching ShowcaseNook --scene $scene"
if (( dry_run )); then
  printf '+ %s\n' "$bin/ShowcaseNook --scene $scene --keep-open --theme $tmp/live/theme.json &"
  window=0
else
  "$bin/ShowcaseNook" --scene "$scene" --keep-open --theme "$tmp/live/theme.json" >/dev/null 2>&1 &
  app_pid=$!
  # The nook panel is the app's window on layer 33.
  window=""
  for _ in $(seq 1 60); do
    json="$("$tmp/nook-windows" "$app_pid")"
    count="$(plutil -extract windows raw -o - - <<<"$json" 2>/dev/null || echo 0)"
    for (( i = 0; i < count; i++ )); do
      if [[ "$(plutil -extract "windows.$i.layer" raw -o - - <<<"$json")" == 33 ]]; then
        window="$(plutil -extract "windows.$i.id" raw -o - - <<<"$json")"
      fi
    done
    [[ -n "$window" ]] && break
    sleep 0.25
  done
  [[ -n "$window" ]] || { echo "the nook panel never appeared" >&2; exit 1; }
  # Let the nook open and its content settle.
  sleep 3
fi

for name in "${themes[@]}"; do
  echo "capturing $name"
  run cp "$(theme_file "$name")" "$tmp/live/theme.json"
  (( dry_run )) || sleep "$settle"
  run screencapture -x -o -l"$window" "$tmp/frames/$name.png"
done

if [[ -n "$app_pid" ]]; then
  kill "$app_pid"
  wait "$app_pid" 2>/dev/null || true
  app_pid=""
fi
(( dry_run )) || restore_defaults

frames=()
for name in "${themes[@]}"; do frames+=("$tmp/frames/$name.png"); done
run "$tmp/trim-union" "${frames[@]}"

# Each capture on paper, hanging from the top edge. The paper is painted opaque
# (geq, #EAF1F8) under the capture, so a theme's shadow blends into it rather than
# keeping its own color when the alpha is dropped.
for name in "${themes[@]}"; do
  run ffmpeg -y -hide_banner -loglevel error -i "$tmp/frames/$name.png" \
    -filter_complex "[0:v]format=rgba,pad=iw+2*$margin:ih+$margin:$margin:0:color=$paper@0,split[n][s];\
[s]geq=r='234':g='241':b='248':a='255'[bg];[bg][n]overlay=format=rgb,format=rgb24" \
    -frames:v 1 -update 1 "$tmp/frames/$name-paper.png"
done

# ---- GIF ---------------------------------------------------------------------
# Each theme held for $hold seconds, at 840 wide like the hero. One palette for
# the whole loop; diff_mode=rectangle re-encodes only what changes per frame.
inputs=()
for name in "${themes[@]}"; do inputs+=(-loop 1 -t "$hold" -i "$tmp/frames/$name-paper.png"); done
concat=""
for (( i = 0; i < ${#themes[@]}; i++ )); do concat+="[$i:v]"; done
run ffmpeg -y -hide_banner -loglevel error "${inputs[@]}" \
  -filter_complex "${concat}concat=n=${#themes[@]}:v=1:a=0,fps=10,scale=840:-2:flags=lanczos,setsar=1,split[a][b];\
[a]palettegen=max_colors=256:stats_mode=full[p];[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
  -loop 0 "$tmp/nook-themes.gif"
run mv "$tmp/nook-themes.gif" "$here/nook-themes.gif"

# ---- grid --------------------------------------------------------------------
# The four captures two by two, for the Theming guide. The site's image pipeline
# scales it, so it stays at the capture's full resolution here.
run mkdir -p "$site_out"
grid_inputs=()
for name in "${themes[@]}"; do grid_inputs+=(-i "$tmp/frames/$name-paper.png"); done
run ffmpeg -y -hide_banner -loglevel error "${grid_inputs[@]}" \
  -filter_complex "[0:v][1:v][2:v][3:v]xstack=inputs=4:layout=0_0|w0_0|0_h0|w0_h0,format=rgb24" \
  -frames:v 1 -update 1 -compression_level 100 "$site_out/nook-themes.png"

(( dry_run )) || ls -la "$here/nook-themes.gif" "$site_out/nook-themes.png"
