#!/usr/bin/env bash
# Live M4 freeze-stage-abort check. Keep the named player connected on server-a.
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "usage: $0 <player-uuid> [player-name]" >&2
    exit 2
fi

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
player_name="${2:-WorldlineDemo}"

cd "$repo_root/proxy"
./gradlew -q :velocity-proxy:runM4FreezeStageAbort \
    -PworldlinePlayerUuid="$1" -PworldlinePlayerName="$player_name"
