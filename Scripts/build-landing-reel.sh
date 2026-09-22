#!/bin/bash
# Edit the ShowcaseNook recordings into the single reel the landing page plays.
#
# Why one file rather than several: the site used to cross-fade between
# separate clips in the browser, which read as random switching. This cuts one
# authored sequence instead - each look opens on the collapsed pill, expands,
# holds, then dissolves back into the next look's pill. The last look dissolves
# into the first look's opening pill, so the loop has no seam.
#
# The inputs are site/src/assets/showcase/<scene>.webm from
# Scripts/record-showcase.sh. They are already keyed (VP9 with alpha, the cream
# backdrop and the glow over it unmixed by unmix-backdrop.swift), so nothing is
# keyed here. Each is 840 tall with the notch flush at the top centre, 30 fps,
# and opens on the pill; the expand starts 1.3-1.4 s in and settles about 0.6 s
# later. The scenes are different widths, so each is padded onto a common
# 1740-wide transparent canvas, centred on the notch, before anything else.
#
# Each clip is premultiplied before the dissolves and unpremultiplied after.
# Transparent pixels then carry black, so the notch stays solid through a
# dissolve and only the panel outline fades, which reads as the nook
# collapsing into the next pill; blending straight alpha would drag whatever
# colour the transparent pixels hold into the half-transparent ones.
#
# Outputs, in site/src/assets/reel/:
#   reel-alpha.webm   VP9 with alpha, for Chromium and Firefox
#   reel-alpha.mov    HEVC with alpha, for Safari, which ignores VP9 alpha
#   reel-poster.png   the player look expanded, for no-autoplay and reduced motion
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
showcase="$root/site/src/assets/showcase"
reel="$root/site/src/assets/reel"
out="${1:-$reel/reel-alpha.webm}"
mov="${out%.webm}.mov"
poster="$reel/reel-poster.png"

xf=0.4 # dissolve between looks
canvas=1740:840

# Crop to the nook: on the 1740 canvas, content with any alpha spans x 159-1580
# and y 0-663 across the looks (progress is the tallest, player the
# widest), and the pill is centred on x 870.
crop=1440:672:150:0

# Per look: scene, start, duration. Each start is 1.0 s before the expand
# begins (measured: player 1.27 s, agenda 1.40 s, shelf 1.95 s, timer
# 1.33 s, progress 1.43 s), so after the 0.4 s dissolve in the pill rests for 0.6 s, expands
# over about 0.6 s, holds for about 2.5 s and dissolves out. The agenda take
# (4.1 s) and shelf (4.9 s) takes run out early, so their static last frames
# are held for the rest.
looks=(
  "player 0.25 4.5"
  "agenda 0.4 4.5"
  "shelf 0.95 4.5"
  "timer 0.35 4.5"
  "progress 0.45 4.5"
)

for look in "${looks[@]}"; do
  read -r scene _ _ <<<"$look"
  [[ -f "$showcase/$scene.webm" ]] || { echo "missing $scene.webm" >&2; exit 1; }
done

# libvpx-vp9 is named on each input: ffmpeg's built-in VP9 decoder drops alpha.
prepare() { # $1 = label, $2 = duration
  echo "format=rgba,pad=$canvas:(ow-iw)/2:0:color=black@0,crop=$crop,\
tpad=stop_mode=clone:stop_duration=3,trim=duration=$2,setpts=PTS-STARTPTS,\
setsar=1,premultiply=inplace=1[$1]"
}

inputs=()
graph=""
n=0
for look in "${looks[@]}"; do
  read -r scene ss t <<<"$look"
  inputs+=(-ss "$ss" -c:v libvpx-vp9 -i "$showcase/$scene.webm")
  graph+="[$n:v]$(prepare "s$n" "$t");"
  n=$((n + 1))
done

# The tail: the first look's opening pill again, so the reel ends where it
# starts.
read -r scene ss _ <<<"${looks[0]}"
inputs+=(-ss "$ss" -c:v libvpx-vp9 -i "$showcase/$scene.webm")
graph+="[$n:v]$(prepare "s$n" "$xf");"

# Chain the dissolves. Each xfade offset is the running length so far minus
# the overlap.
prev="s0"
length=$(echo "${looks[0]}" | awk '{print $3}')
for ((i = 1; i <= n; i++)); do
  if ((i < n)); then
    t=$(echo "${looks[$i]}" | awk '{print $3}')
  else
    t=$xf
  fi
  offset=$(echo "$length - $xf" | bc)
  graph+="[$prev][s$i]xfade=transition=fade:duration=$xf:offset=$offset[x$i];"
  prev="x$i"
  length=$(echo "$length + $t - $xf" | bc)
done

# The tail ends on the first look's frame at start + xf, so the reel begins
# there too: drop the first xf seconds and the loop lands on the same frame.
length=$(echo "$length - $xf" | bc)
graph+="[$prev]trim=start=$xf,setpts=PTS-STARTPTS,unpremultiply=inplace=1,split[w][m]"

ffmpeg -y -hide_banner -loglevel error "${inputs[@]}" \
  -filter_complex "$graph" \
  -map "[w]" -c:v libvpx-vp9 -pix_fmt yuva420p -auto-alt-ref 0 -crf 34 -b:v 0 \
  -row-mt 1 "$out" \
  -map "[m]" -c:v hevc_videotoolbox -pix_fmt bgra -alpha_quality 0.75 -q:v 60 \
  -tag:v hvc1 -movflags +faststart "$mov"

# The poster is the first look (player) held fully expanded, on the same
# canvas and crop, so it lines up with the reel exactly.
ffmpeg -y -hide_banner -loglevel error -ss 3.5 -c:v libvpx-vp9 -i "$showcase/player.webm" \
  -vf "format=rgba,pad=$canvas:(ow-iw)/2:0:color=black@0,crop=$crop" -frames:v 1 \
  -update 1 "$poster"

echo "wrote $out, $mov and $poster ($length s)"
ffprobe -v error -show_entries format=duration -of csv=p=0 "$out"
