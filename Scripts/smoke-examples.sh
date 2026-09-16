#!/usr/bin/env bash
# Launch every example executable (and the Nook demo) under OPENNOOK_SMOKE_TEST=1.
# Each process runs a deterministic expand/compact cycle and exits 0/1.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

TIMEOUT_SECONDS="${OPENNOOK_SMOKE_TIMEOUT:-30}"

run_with_timeout() {
  local duration="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$duration" "$@"
    return
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$duration" "$@"
    return
  fi
  perl -e 'alarm shift; exec @ARGV or die "exec failed: $!\n"' "$duration" "$@"
}

executables=(
  Nook
  HelloNook
  ClockNook
  ThemedNook
  ChromeNook
  LayoutNook
  ShelfNook
  ActivityNook
  VolumeNook
  MultiNook
  CompanionNook
  PlaygroundNook
)

echo "Building executables..."
swift build -c debug

for name in "${executables[@]}"; do
  binary=".build/debug/${name}"
  if [[ ! -x "$binary" ]]; then
    echo "::error::missing executable $binary (did Package.swift change?)" >&2
    exit 1
  fi
  echo "Smoke testing ${name}..."
  if ! run_with_timeout "${TIMEOUT_SECONDS}" env OPENNOOK_SMOKE_TEST=1 "$binary"; then
    echo "::error::smoke test failed for ${name}" >&2
    exit 1
  fi
done

echo "Launch smoke passed for ${#executables[@]} executables."
