#!/bin/bash
# Build the README media in docs/images/ from the ShowcaseNook recordings.
#
# Inputs, read and never modified:
#   site/src/assets/reel/reel-alpha.webm   the landing reel from
#       Scripts/build-landing-reel.sh: player -> agenda -> shelf -> timer -> progress,
#       each opening on the collapsed pill, 1440x672 with alpha, the notch on
#       the first row, and a seamless loop
#   site/src/assets/showcase/<scene>.png   window captures of each expanded
#       scene from Scripts/record-showcase.sh, with real transparency
#
# Outputs:
#   nook-hero.gif        the reel, on paper
#   nook-player.png      ShowcaseNook --scene player, expanded
#   nook-agenda.png      ShowcaseNook --scene agenda, expanded
#   nook-timer.png       ShowcaseNook --scene timer, expanded
#   nook-progress.png    ShowcaseNook --scene progress, expanded
#   nook-shelf.png       ShowcaseNook --scene shelf, expanded
#
# Everything is composited onto a cool paper (#EAF1F8) that reads as a soft
# card on both GitHub themes; the black nook needs a light surface around it to
# show its outline on the dark theme. The inputs carry alpha (the rim glows are
# already unmixed from the recording backdrop), so there is no key here.
#
# Requires ffmpeg. Run from anywhere: ./docs/images/make-readme-media.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
reel="$root/site/src/assets/reel/reel-alpha.webm"
showcase="$root/site/src/assets/showcase"
paper=0xEAF1F8
scenes=(player agenda timer progress shelf)

[[ -f "$reel" ]] || { echo "missing $reel" >&2; exit 1; }
for scene in "${scenes[@]}"; do
  [[ -f "$showcase/$scene.png" ]] || { echo "missing $showcase/$scene.png" >&2; exit 1; }
done

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ---- hero GIF ----------------------------------------------------------------
# The whole reel, flattened onto paper at 12 fps and 840 wide. The reel already
# ends on the frame it starts with, so the GIF loops without a seam. One global
# 256-colour palette; diff_mode=rectangle re-encodes only the changing region
# of each frame, which keeps the file small while the panels hold.
# libvpx-vp9 is named on the input: ffmpeg's built-in VP9 decoder drops alpha.
ffmpeg -y -hide_banner -loglevel error -c:v libvpx-vp9 -i "$reel" \
  -filter_complex "color=$paper:s=1440x672:r=12[bg];\
[0:v]fps=12,format=rgba[v];[bg][v]overlay=shortest=1:format=auto,\
scale=840:-2:flags=lanczos,setsar=1,split[a][b];\
[a]palettegen=max_colors=256:stats_mode=full[p];\
[b][p]paletteuse=dither=sierra2_4a:diff_mode=rectangle" \
  -loop 0 "$tmp/hero.gif"
mv "$tmp/hero.gif" "$here/nook-hero.gif"

# ---- stills ------------------------------------------------------------------
# Each capture is centred on one 1440x672 paper canvas, the same frame as the
# reel, with the notch on the top edge, so the four stills line up in the
# README grid. Then halved to 720x336.
for scene in "${scenes[@]}"; do
  ffmpeg -y -hide_banner -loglevel error -i "$showcase/$scene.png" \
    -filter_complex "color=$paper:s=1440x672[bg];[bg][0:v]overlay=(W-w)/2:0:format=auto,\
scale=720:-2:flags=lanczos,format=rgb24" \
    -frames:v 1 -update 1 -compression_level 100 "$here/nook-$scene.png"
done

ls -la "$here"/nook-hero.gif "$here"/nook-{player,agenda,timer,progress,shelf}.png
