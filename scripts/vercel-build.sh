#!/usr/bin/env bash

set -euo pipefail

VERCEL_FLUTTER_ROOT="${HOME}/flutter"

if [[ ! -x "${VERCEL_FLUTTER_ROOT}/bin/flutter" ]]; then
  git clone \
    --depth 1 \
    --branch stable \
    https://github.com/flutter/flutter.git \
    "${VERCEL_FLUTTER_ROOT}"
fi

export PATH="${VERCEL_FLUTTER_ROOT}/bin:${PATH}"

flutter config --enable-web
flutter pub get
flutter build web --release
