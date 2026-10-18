#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
version=2.10.0
destination=".build/dependencies/sparkle-$version"
if [ ! -f "$destination/Sparkle.framework/Sparkle" ]; then
  mkdir -p .build/dependencies
  archive=".build/dependencies/Sparkle-$version.tar.xz"
  curl --fail --location --retry 3 "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" -o "$archive"
  echo "c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c  $archive" | shasum -a 256 -c -
  mkdir -p "$destination"
  tar -xf "$archive" -C "$destination"
fi
