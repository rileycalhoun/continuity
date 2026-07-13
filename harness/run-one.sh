#!/usr/bin/env bash
# Runs a single slice component (proxy, server-a, or server-b) in the foreground,
# so the three processes can live in separate terminals. Uses the same topology,
# config installation, and JVM flags as run-slice.sh.
# Build the jars first with harness/build-jars.sh.
set -euo pipefail

usage() {
    echo "usage: $0 proxy|server-a|server-b" >&2
    exit 2
}
[[ $# -eq 1 ]] || usage
component="$1"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
harness_dir="$repo_root/harness"
proxy_run_dir="$repo_root/proxy/proxy/run"
server_run_dir="$repo_root/server/run"
memory_gb="${WORLDLINE_RUN_MEMORY_GB:-2}"

case "$component" in
    proxy)    port=25565 ;;
    server-a) port=25566 ;;
    server-b) port=25567 ;;
    *) usage ;;
esac

if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
    exec 3>&- || true
    echo "error: port $port is already in use; is $component already running?" >&2
    exit 1
fi

if [[ "$component" == "proxy" ]]; then
    proxy_jar="$(ls "$repo_root"/proxy/proxy/build/libs/velocity-proxy-*-all.jar 2>/dev/null | head -1 || true)"
    [[ -n "$proxy_jar" ]] || { echo "error: proxy jar not found; build it with harness/build-jars.sh" >&2; exit 1; }

    mkdir -p "$proxy_run_dir"
    cp "$harness_dir/velocity.toml" "$proxy_run_dir/velocity.toml"
    cp "$harness_dir/forwarding.secret" "$proxy_run_dir/forwarding.secret"
    cp "$harness_dir/worldline.toml" "$proxy_run_dir/worldline.toml"
    cmp -s "$harness_dir/worldline.toml" "$proxy_run_dir/worldline.toml" || { echo "error: failed to install worldline.toml into $proxy_run_dir" >&2; exit 1; }

    echo "Starting proxy on port $port"
    cd "$proxy_run_dir"
    exec java -Xms512M -Xmx512M -Dworldline.config=worldline.toml \
        -Dworldline.splice-target=server-b -Dvelocity.packet-decode-logging=true -Dterminal.jline=false \
        -jar "$proxy_jar"
fi

server_jar="$(ls "$repo_root"/server/paper-server/build/libs/paper-bundler-*.jar 2>/dev/null | head -1 || true)"
[[ -n "$server_jar" ]] || { echo "error: server jar not found; build it with harness/build-jars.sh" >&2; exit 1; }

d="$server_run_dir/$component"
[[ -f "$d/eula.txt" ]] || { echo "error: $d is not initialized (missing eula.txt); run 'cd server && ./gradlew :paper-server:runServers' once first" >&2; exit 1; }

cp "$harness_dir/worldline.toml" "$d/worldline.toml"
cmp -s "$harness_dir/worldline.toml" "$d/worldline.toml" || { echo "error: failed to install worldline.toml into $d" >&2; exit 1; }
# The client's signed-chat session does not survive the M1 silent splice, so the slice
# runs with secure-profile enforcement off; see run-slice.sh and the harness README.
if grep -q '^enforce-secure-profile=' "$d/server.properties" 2>/dev/null; then
    sed -e 's/^enforce-secure-profile=.*/enforce-secure-profile=false/' "$d/server.properties" > "$d/server.properties.tmp"
    mv "$d/server.properties.tmp" "$d/server.properties"
else
    printf 'enforce-secure-profile=false\n' >> "$d/server.properties"
fi

resume=""
[[ "$component" == "server-b" ]] && resume=-Dworldline.resume=true

echo "Starting $component on port $port"
cd "$d"
exec java "-Xms${memory_gb}G" "-Xmx${memory_gb}G" \
    ${resume:+"$resume"} \
    -Dworldline.config=worldline.toml \
    -Dworldline.server-id="$component" \
    -Dterminal.jline=false \
    -Dnet.kyori.adventure.text.warnWhenLegacyFormattingDetected=true \
    -Dio.papermc.paper.suppress.sout.nags=true \
    -jar "$server_jar" --nogui --port "$port"
