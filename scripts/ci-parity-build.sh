#!/usr/bin/env bash
#
# ci-parity-build.sh — build RiffMemo and its tests with the exact Xcode that CI uses.
#
# WAS-181: CI pins an older Xcode (see DEVELOPER_DIR in .github/workflows/ios-build.yml)
# than most Macs run. A newer compiler or SDK can accept code that CI rejects: a brand-new
# iOS API, or a Swift keyword the older compiler does not know. Run this before you push
# to see CI's compile errors locally.
#
# Usage: scripts/ci-parity-build.sh
#   CI_PARITY_XCODE=/path/to/Xcode.app scripts/ci-parity-build.sh   # use a specific copy
#
# Exit codes: 0 build passed, 1 build failed, 2 the pinned Xcode is not installed.
#
# It only builds (build-for-testing). Run the tests with your normal Xcode.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
workflow="$repo_root/.github/workflows/ios-build.yml"

# The workflow is the single source of truth for the version.
version="$(sed -nE 's|.*DEVELOPER_DIR:[[:space:]]*/Applications/Xcode_([0-9.]+)\.app/Contents/Developer.*|\1|p' "$workflow" | head -n 1)"
if [[ -z "$version" ]]; then
  echo "error: could not read the pinned Xcode version from $workflow" >&2
  echo "       Expected a line like: DEVELOPER_DIR: /Applications/Xcode_16.4.app/Contents/Developer" >&2
  exit 1
fi

xcode_version_of() {
  /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$1/Contents/Info.plist" 2>/dev/null || true
}

# Find an installed Xcode with exactly that version.
xcode_app=""
if [[ -n "${CI_PARITY_XCODE:-}" ]]; then
  xcode_app="$CI_PARITY_XCODE"
else
  for candidate in /Applications/Xcode*.app "$HOME"/Applications/Xcode*.app; do
    [[ -d "$candidate" ]] || continue
    if [[ "$(xcode_version_of "$candidate")" == "$version" ]]; then
      xcode_app="$candidate"
      break
    fi
  done
fi

if [[ -z "$xcode_app" || "$(xcode_version_of "$xcode_app")" != "$version" ]]; then
  cat >&2 <<EOF
CI builds with Xcode $version, and no copy of it is installed here.

Install it once, next to your current Xcode:
  1. Download "Xcode $version" from https://developer.apple.com/download/all/
     (sign in with your Apple ID).
  2. Unzip it, rename it to Xcode_$version.app, and move it to /Applications.
     Keep your current Xcode.app; this copy is only for this check.
  3. Run this script again.

Or point at a copy somewhere else:
  CI_PARITY_XCODE=/path/to/Xcode_$version.app $0
EOF
  exit 2
fi

echo "Building with $xcode_app (Xcode $version, the version CI pins)…"

derived_data="$(mktemp -d "${TMPDIR:-/tmp}/riffmemo-ci-parity.XXXXXX")"
trap 'rm -rf "$derived_data"' EXIT

# Same flags as the "Build for testing" step in CI, plus the test targets.
if DEVELOPER_DIR="$xcode_app/Contents/Developer" xcodebuild build-for-testing \
  -project "$repo_root/RiffMemo/RiffMemo.xcodeproj" \
  -scheme RiffMemo \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$derived_data" \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  -quiet; then
  echo "CI parity build passed with Xcode $version."
else
  echo "CI parity build FAILED with Xcode $version. CI will fail the same way." >&2
  exit 1
fi
