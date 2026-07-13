#!/usr/bin/env bash
# Scripted M2 prepare-abort round trip over the real proxy-to-server TCP transport.
# Run the slice topology first so both Paper control endpoints are listening.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$repo_root/proxy"
./gradlew -q :velocity-proxy:runM2PrepareAbort
