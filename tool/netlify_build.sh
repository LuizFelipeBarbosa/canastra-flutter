#!/usr/bin/env bash
# Builds the Flutter web app on Netlify, whose build image has no Flutter SDK.
set -euo pipefail

FLUTTER_VERSION="${FLUTTER_VERSION:-3.44.6}"
FLUTTER_ROOT="${FLUTTER_ROOT:-$HOME/flutter}"

if [ ! -x "$FLUTTER_ROOT/bin/flutter" ]; then
  echo "Fetching Flutter $FLUTTER_VERSION into $FLUTTER_ROOT"
  git clone --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$FLUTTER_ROOT"
fi

export PATH="$FLUTTER_ROOT/bin:$PATH"
git config --global --add safe.directory "$FLUTTER_ROOT"

flutter --version
flutter pub get

# Where the built app looks for the game host. Set in netlify.toml; without it
# the build would silently point at each visitor's own localhost, which looks
# like a lobby that never starts rather than an error.
if [ -z "${GAME_HOST:-}" ]; then
  echo "error: GAME_HOST is not set — online play would be dead in this build." >&2
  echo "       Set it in netlify.toml under [build.environment]." >&2
  exit 1
fi

echo "Building against host: $GAME_HOST"
flutter build web --release --dart-define=GAME_HOST="$GAME_HOST"
