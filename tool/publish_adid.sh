#!/usr/bin/env bash
# Publish packages/flutter_adto_adid from a copy outside this repo.
#
# packages/.pubignore keeps the companion package out of the flutter_adto
# archive, and pub applies a repository's ignore files to every package in
# it, so the companion cannot publish from where it lives. The copy has no
# git and no parent ignore files.
#
#   tool/publish_adid.sh --dry-run   # builds against this repo's flutter_adto
#   tool/publish_adid.sh             # after flutter_adto is on pub.dev
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

rsync -a \
  --exclude .dart_tool --exclude build --exclude pubspec.lock \
  --exclude pubspec_overrides.yaml \
  "$repo/packages/flutter_adto_adid/" "$tmp/flutter_adto_adid/"
cd "$tmp/flutter_adto_adid"

if [[ "${1:-}" == "--dry-run" ]]; then
  # Until flutter_adto is published, resolve it from this repo.
  printf 'dependency_overrides:\n  flutter_adto:\n    path: %s\n' "$repo" > pubspec_overrides.yaml
fi
flutter pub publish "$@"
