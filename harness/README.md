# Vertical-slice dev harness

Local two-node topology for the [vertical-slice roadmap](../docs/vertical-slice-roadmap.md) (M0): one Worldline Proxy on `25565`, `server-a` on `25566`, `server-b` on `25567`. Both servers run identical world files; the static partition boundary in `worldline.toml` splits the world at chunk X = 0.

Everything here is slice-only development tooling under the ADR 0005 experimental exception. The `forwarding.secret` is a local-development secret shared with each server's `config/paper-global.yml`; it protects nothing outside this harness.

## One-command boot

```sh
harness/run-slice.sh
```

Requires built jars and initialized server run directories:

```sh
harness/build-jars.sh                                   # server + proxy jars
cd server && ./gradlew :paper-server:runServers         # first-time run-dir init (accept EULA, generate world)
```

The script installs `velocity.toml`, `forwarding.secret`, and `worldline.toml` into the gitignored `proxy/proxy/run`, copies `worldline.toml` into both server run dirs, starts all three processes, waits until each port accepts connections, and tears everything down on Ctrl-C. Process output is shown live and retained in `harness/logs/`.

Connect a vanilla client to `127.0.0.1:25565`; you land on `server-a`.

For the M1 splice spike, stand still and run `/server server-b`. The proxy silently drives the
second backend connection and swaps packet routing without putting the client through configuration
or forwarding Paper's login packet. This manual path is deliberately limited to `server-a` to
`server-b`; restart the harness before repeating it.

The slice runs with `enforce-secure-profile=false` on both backends (`run-slice.sh` enforces this
at boot). The client's signed-chat session is established once per connection and is never re-sent
to a spliced-in backend, so the destination server has no profile public key for the player and
would reject chat under secure-profile enforcement. On splice the proxy also clears the client's
own remembered chat session (a player-info `INITIALIZE_CHAT` with no session), since the new
backend broadcasts the player's chat unsigned and the client would otherwise fail to validate its
own messages. The client only accepts unsigned chat when the login packet it saw advertised
`enforce-secure-profile=false`, so both halves of this workaround depend on that setting. Relaxed
chat-signing is the residual constraint anticipated by risk 1 in the
[vertical-slice roadmap](../docs/vertical-slice-roadmap.md); carrying signed-chat sessions across
a handoff needs its own design work later.

## Separate terminals

To run each process in its own terminal instead of the single-terminal boot:

```sh
harness/run-one.sh server-a   # terminal 1
harness/run-one.sh server-b   # terminal 2
harness/run-one.sh proxy      # terminal 3
```

Each invocation installs the same canonical config as `run-slice.sh`, then runs the component in
the foreground with identical flags, so logs and the server console stay in that terminal.
Start order doesn't strictly matter (the proxy retries backend connections), but starting the
servers first avoids join failures while they boot.

## World sync

```sh
harness/sync-worlds.sh
```

Copies `server-a`'s world over `server-b`'s (keeping a `world.pre-sync-backup`) so both backends serve identical terrain. Run it whenever `server-a`'s world has changed and the slice is stopped — chunk continuity across the backend splice depends on the files matching.

## Prepare-abort script

```sh
harness/run-prepare-abort.sh
```

Runs the M2 placeholder prepare→abort round trip against the proxy control skeleton. This is in-process until the experimental proxy↔server transport exists.

## Files

- `build-jars.sh` — builds the server bundler jar and the proxy shadow jar
- `run-slice.sh` — boots proxy + both servers, health-checks the ports
- `run-one.sh` — boots a single component in the foreground (for separate terminals)
- `run-prepare-abort.sh` — runs the scripted M2 prepare→abort round trip
- `sync-worlds.sh` — copies the world from server-a to server-b
- `velocity.toml` — canonical proxy config (installed into the run dir on each boot)
- `forwarding.secret` — modern-forwarding secret (local dev only)
- `worldline.toml` — static partition map; installed for proxy and servers on each boot
