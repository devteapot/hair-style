#!/bin/sh
set -eu
if [ -z "${DEVELOPER_DIR:-}" ]; then
  for candidate in /Applications/Xcode.app/Contents/Developer /Applications/Xcode-Beta.app/Contents/Developer; do
    if [ -d "$candidate" ]; then
      export DEVELOPER_DIR="$candidate"
      break
    fi
  done
fi
exec "$@"
