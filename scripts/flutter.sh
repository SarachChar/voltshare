#!/usr/bin/env zsh
# Wraps `flutter` and injects git commit info as dart-defines.
# Usage:
#   ./scripts/flutter.sh run
#   ./scripts/flutter.sh build apk
#   ./scripts/flutter.sh build ipa
set -euo pipefail

cd "$(dirname "$0")/.."

GIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo 0)
GIT_SHA=$(git rev-parse --short HEAD 2>/dev/null || echo dev)

exec flutter "$@" \
  --dart-define=GIT_COUNT="$GIT_COUNT" \
  --dart-define=GIT_SHA="$GIT_SHA"
