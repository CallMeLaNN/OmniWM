#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SWIFTLY_HOME_DIR="${SWIFTLY_HOME_DIR:-$HOME/.swiftly}"
SWIFTLY="$SWIFTLY_HOME_DIR/bin/swiftly"
SWIFT_ORG_TEAM_ID=V9AUD2URP3

if [ ! -x "$SWIFTLY" ]; then
  WORK_DIR="$(mktemp -d)"
  trap 'rm -rf "$WORK_DIR"' EXIT
  curl --fail --silent --show-error --location --output "$WORK_DIR/swiftly.pkg" \
    https://download.swift.org/swiftly/darwin/swiftly.pkg
  if ! pkgutil --check-signature "$WORK_DIR/swiftly.pkg" | grep -q "($SWIFT_ORG_TEAM_ID)"; then
    echo "swift-toolchain: swiftly.pkg is not signed by Swift.org ($SWIFT_ORG_TEAM_ID)" >&2
    exit 1
  fi
  installer -pkg "$WORK_DIR/swiftly.pkg" -target CurrentUserHomeDirectory
  "$SWIFTLY" init --assume-yes --no-modify-profile --skip-install --quiet-shell-followup
fi

cd "$ROOT_DIR"
"$SWIFTLY" install --assume-yes
if [ -n "${GITHUB_PATH:-}" ]; then
  echo "$SWIFTLY_HOME_DIR/bin" >> "$GITHUB_PATH"
fi
"$SWIFTLY_HOME_DIR/bin/swift" --version
