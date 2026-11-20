#!/bin/sh
set -eu

cd "${CI_PRIMARY_REPOSITORY_PATH:?}"
flutter_sdk="$HOME/flutter"
git clone --depth 1 --branch 3.47.4 https://github.com/flutter/flutter.git "$flutter_sdk"
export PATH="$flutter_sdk/bin:$PATH"

if ! command -v pod >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew install cocoapods
fi

flutter precache --ios
flutter pub get --enforce-lockfile
# Prepare the build settings and pods for the archive that Xcode Cloud signs.
flutter build ios --config-only --release --no-codesign --no-pub \
  --build-number="${CI_BUILD_NUMBER:?}" --dart-define-from-file=ios/railway.json
