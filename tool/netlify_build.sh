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
flutter build web --release
