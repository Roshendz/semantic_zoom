#!/usr/bin/env bash
# Release gate: everything that must pass before a commit or publish.
# Usage: tool/check.sh   (from anywhere; runs in the package root)
set -euo pipefail
cd "$(dirname "$0")/.."

BASE_TAG="${BASE_TAG:-v0.3.0}" # last published release
FLUTTER_MIN="${FLUTTER_MIN:-$HOME/fvm/versions/3.22.3/bin/flutter}"
DEMO_APP="${DEMO_APP:-../semantic_zoom_demo}"
export PATH="$PWD/.fvm/flutter_sdk/bin:$PATH" # dart_apitool needs flutter

step() { printf '\n\033[1m▶ %s\033[0m\n' "$1"; }

step "Format"
fvm dart format --output=none --set-exit-if-changed lib test example/lib

step "Analyze"
fvm flutter analyze --fatal-infos

step "Tests, including golden baselines"
fvm flutter test

step "Tests released in $BASE_TAG are unchanged"
released=$(git ls-tree --name-only "$BASE_TAG" test/ | grep '_test\.dart$')
# shellcheck disable=SC2086
if ! git diff --quiet "$BASE_TAG" -- $released; then
  git diff --stat "$BASE_TAG" -- $released
  exit 1
fi
echo "ok: $(echo "$released" | wc -l | tr -d ' ') files"

step "Public API has no breaking changes vs pub.dev ${BASE_TAG#v}"
report=$(fvm dart pub global run dart_apitool:main diff \
  --old "pub://semantic_zoom/${BASE_TAG#v}" --new . \
  --version-check-mode=none 2>&1)
echo "$report" | sed -n '/Generating report/,$p'
if ! grep -qE "No breaking changes!|No changes detected!" <<<"$report"; then
  echo "✗ Breaking API change detected"
  exit 1
fi

step "Example app"
(cd example && fvm flutter analyze --fatal-infos && fvm flutter test)

step "Demo app against this code"
if [ -d "$DEMO_APP" ]; then
  tmp=$(mktemp -d)
  rsync -a --exclude .fvm --exclude .dart_tool --exclude build "$DEMO_APP"/ "$tmp"/
  printf '\ndependency_overrides:\n  semantic_zoom:\n    path: %s\n' "$PWD" >>"$tmp/pubspec.yaml"
  (cd "$tmp" && fvm flutter pub get >/dev/null && fvm flutter analyze && fvm flutter test)
  rm -rf "$tmp"
else
  echo "skipped: $DEMO_APP not found"
fi

step "Minimum Flutter ($("$FLUTTER_MIN" --version 2>/dev/null | awk 'NR==1{print $2}'))"
tmp=$(mktemp -d)
rsync -a --exclude example --exclude .fvm --exclude .dart_tool --exclude build \
  --exclude pubspec.lock --exclude .git ./ "$tmp"/
(cd "$tmp" && "$FLUTTER_MIN" pub get >/dev/null && "$FLUTTER_MIN" analyze &&
  "$FLUTTER_MIN" test --exclude-tags golden)
rm -rf "$tmp"

step "pub.dev score"
fvm dart pub global run pana --no-warning . | grep -E "^Points:"

printf '\n\033[1;32m✓ All checks passed\033[0m\n'
