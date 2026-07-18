# M5 Commit, Splice, and Activation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete vertical-slice milestone M5 with one fenced player-authority commit, a transfer-scoped invisible backend splice, exact activation of the M4 staged player, ordered replay, and stale-source cleanup.

**Architecture:** The proxy live-session record remains the atomic authority and gains a monotonically increasing route generation used to fence every backend connection. Paper protocol v4 adds explicit source/destination commit, attach, activate, cleanup, and retirement lifecycles; the prepared M4 player remains inert until main-thread activation. All blocking control work runs off Netty/Paper main threads, while connection and player mutations return to their owning event loops.

**Tech Stack:** Java 25, Velocity 3.6 fork, Paper 26.2 fork, Netty, JUnit 5, Gradle, Bash harness scripts.

**Normative references:** `docs/decisions/0005-player-handoff-state-machine.md`, `docs/vertical-slice-roadmap.md`, `docs/superpowers/specs/2026-07-18-m5-commit-splice-activation-design.md`.

---

## File Map

### Proxy submodule

- Create `proxy/src/main/java/com/velocitypowered/proxy/worldline/BackendSessionBinding.java` — immutable client/server/epoch/route binding.
- Create `proxy/src/main/java/com/velocitypowered/proxy/worldline/WorldlineResumeContext.java` — validated M5 destination resume identity and handshake encoding.
- Create `proxy/src/main/java/com/velocitypowered/proxy/worldline/HandoffReplayBuffer.java` — bounded ordered replay entries and one-shot draining.
- Create `proxy/src/test/java/com/velocitypowered/proxy/worldline/BackendSessionBindingTest.java`.
- Create `proxy/src/test/java/com/velocitypowered/proxy/worldline/WorldlineResumeContextTest.java`.
- Create `proxy/src/test/java/com/velocitypowered/proxy/worldline/HandoffReplayBufferTest.java`.
- Modify `proxy/src/main/java/com/velocitypowered/proxy/worldline/ControlEnvelope.java` — add client connection ID and route generation.
- Modify `proxy/src/main/java/com/velocitypowered/proxy/worldline/LivePlayerSession.java` — store route generation.
- Modify `proxy/src/main/java/com/velocitypowered/proxy/worldline/LivePlayerSessionStore.java` — increment generation at commit and retire terminal transfers.
- Modify `proxy/src/main/java/com/velocitypowered/proxy/worldline/HandoffControlPlane.java` — protocol v4 commit barrier and lifecycle commands.
- Modify `proxy/src/main/java/com/velocitypowered/proxy/worldline/WorldlineControlTransport.java` — v4 framing and explicit response validation.
- Modify `proxy/src/main/java/com/velocitypowered/proxy/connection/backend/VelocityServerConnection.java` — immutable binding/resume context and v4 handshake marker.
- Modify `proxy/src/main/java/com/velocitypowered/proxy/connection/backend/BackendPlaySessionHandler.java` — source/destination gameplay-output fence.
- Modify `proxy/src/main/java/com/velocitypowered/proxy/connection/backend/TransitionSessionHandler.java` — invisible M5 route installation and readiness handling.
- Modify `proxy/src/main/java/com/velocitypowered/proxy/connection/client/ConnectedPlayer.java` — internal transfer-scoped connection request.
- Modify `proxy/src/main/java/com/velocitypowered/proxy/connection/client/ClientPlaySessionHandler.java` — commit coordinator, deadline, replay, and phase-aware disconnect.
- Modify existing Worldline tests for protocol v4 fields and lifecycle behavior.

### Server submodule

- Create `paper-server/src/main/java/io/papermc/paper/worldline/WorldlineResumeContext.java` — bounded parser for the v4 handshake marker.
- Create `paper-server/src/main/java/io/papermc/paper/worldline/WorldlineTransferLifecycle.java` — explicit destination/source state machines and tombstones.
- Create corresponding tests under `paper-server/src/test/java/io/papermc/paper/worldline/` and include them from `WorldlineTestSuite`.
- Modify `paper-server/src/main/java/io/papermc/paper/worldline/WorldlineControlServer.java` — protocol v4 commands, lifecycle ownership, attachment, activation, retirement, cleanup, and trace logging.
- Modify `paper-server/patches/sources/net/minecraft/server/players/PlayerList.java.patch` — adopt/attach the prepared player, activate it without visible login/join duplication, and clean stale source state without saving.
- Modify `paper-server/patches/sources/net/minecraft/server/level/ServerPlayer.java.patch` — committed-away/save-suppression and transfer instrumentation flags.
- Modify `paper-server/patches/sources/net/minecraft/server/network/ServerGamePacketListenerImpl.java.patch` — connection attachment and first replay sequence instrumentation.
- Modify `paper-server/src/test/java/org/bukkit/support/suite/WorldlineTestSuite.java`.

### Root repository

- Modify `harness/run-slice.sh`, `harness/run-one.sh`, and `harness/worldline.toml` for M5 protocol/timeout flags and remove the global splice target from normal M5 mode.
- Create `harness/assert-m5-trace.sh` to validate the successful-path trace invariants.
- Modify `harness/README.md` and `docs/vertical-slice-roadmap.md` only according to demonstrated verification status.
- Update `proxy` and `server` submodule pointers.

---

### Task 0: Record the verified M4 foundation

**Files:** root `proxy` and `server` gitlinks, this plan.

- [ ] Confirm proxy points at `41a3df14` or its exact reviewed M4 descendant and server points at `bb03baf80` or its exact reviewed M4 descendant.
- [ ] Record the already-run baseline evidence: proxy Worldline tests pass; Paper `applyPatches`, `WorldlineTestSuite`, and compile pass.
- [ ] Commit the two advanced gitlinks and reviewed implementation plan in the root before editing M5 production code: `chore: advance submodules to M4`.

### Task 1: Protocol-v4 identity and proxy live-session fencing

**Files:** proxy `ControlEnvelope.java`, `LivePlayerSession.java`, `LivePlayerSessionStore.java`, their existing tests.

- [ ] Add failing tests that require `clientConnectionId` and `routeGeneration` in every envelope/session and require `commit()` to increment both player epoch and route generation exactly once.
- [ ] Run:

  ```sh
  cd proxy && ./gradlew :velocity-proxy:test --tests 'com.velocitypowered.proxy.worldline.LivePlayerSessionStoreTest' --tests 'com.velocitypowered.proxy.worldline.HandoffControlPlaneTest'
  ```

  Expected: compile/test failure because the v4 fields and generation assertions do not exist.

- [ ] Add the two fields, set initial generation to `0`, increment generation atomically with authority commit, and preserve generation during phase-only transitions and idempotent retry.
- [ ] Change `HandoffControlPlane.PROTOCOL_VERSION` to `4`; update all envelope construction and framing tests.
- [ ] Re-run the focused tests and the complete proxy Worldline suite; expect success.
- [ ] Commit in `proxy`: `feat: add M5 session and route fencing`.

### Task 2: Server lifecycle registry and protocol-v4 commands

**Files:** server `WorldlineTransferLifecycle.java`, `WorldlineControlServer.java`, new lifecycle tests, `WorldlineTestSuite.java`.

- [ ] Write failing pure lifecycle tests for destination transitions:

  ```text
  PREPARED -> SNAPSHOT_STAGED -> COMMITTED -> CONNECTION_ATTACHED -> ACTIVE -> CLEANED
  COMMITTED|CONNECTION_ATTACHED|ACTIVE -> RETIRED
  ```

  and source transitions `FROZEN(n) -> COMMITTED_AWAY(n+1) -> CLEANED(n+1)`.
- [ ] Cover duplicate same-transfer commands, stale transfer/epoch rejection, abort rejection after commit, destination retirement from all post-commit states, and bounded tombstone results.
- [ ] Run `cd server && ./gradlew :paper-server:test --tests 'org.bukkit.support.suite.WorldlineTestSuite'`; expect assertion/compile failure for missing lifecycle.
- [ ] Implement a synchronized or concurrent-map registry whose conditional transitions return typed `APPLIED`, `ALREADY_APPLIED`, `REJECTED_MISMATCH`, or `MISSING` outcomes without touching Minecraft objects.
- [ ] Replace protocol-v3 fall-through acknowledgements with explicit v4 handlers for `COMMIT_DESTINATION`, `COMMIT_SOURCE`, `ACTIVATE_DESTINATION`, `CLEAN_SOURCE`, and `RETIRE_DESTINATION`.
- [ ] Make the server reject v3 before command dispatch and echo all v4 fence fields.
- [ ] Re-run the Paper Worldline suite; expect success.
- [ ] Commit in `server`: `feat: add M5 transfer lifecycle protocol`.

### Task 3: Transfer-scoped resume context on both sides

**Files:** proxy/server `WorldlineResumeContext.java`, `VelocityServerConnection.java`, parser/encoding tests.

- [ ] Write failing round-trip tests for a marker containing protocol, transfer UUID, player UUID, client-connection UUID, source server, destination server, source/destination partition IDs and epochs, source epoch, committed epoch, player-state version, route generation, and prior entity ID.
- [ ] Add rejection tests for missing delimiters, wrong protocol, invalid/oversized UUID text, negative epochs/generation, trailing data, and markers longer than the chosen bound.
- [ ] Run both new focused test classes; verify failure for missing types.
- [ ] Implement immutable validated records and deterministic encoding/parsing. Attachment validates every field against the committed control record and login UUID; it never infers identity or authority from the current server name or login state. The proxy passes context directly into `VelocityServerConnection`; remove M5 authority decisions based on `worldline.splice-target`.
- [ ] Append a marker only for an explicit resume context; Paper still requires `worldline.resume=true` and matching committed lifecycle state.
- [ ] Re-run tests and commit separately in each submodule with `feat: add transfer-scoped M5 resume context`.

### Task 4: Adopt and attach the staged Paper player without activation

**Files:** server `WorldlineControlServer.java`, `PlayerList.java.patch`, `ServerGamePacketListenerImpl.java.patch`, server tests.

- [ ] Add failing control-server tests proving that resume attachment:
  - consumes only the matching committed preparation;
  - returns the exact M4 prepared `ServerPlayer` identity;
  - rejects UUID/transfer/client/epoch/generation mismatch;
  - cannot consume twice;
  - leaves lifecycle at `CONNECTION_ATTACHED`.
- [ ] Add a test hook/state snapshot proving attachment does not register, tick, track, persist, fire join/quit events, or emit gameplay output.
- [ ] Run the Paper Worldline suite and verify the new failures.
- [ ] After the initial `applyPatches`, edit the generated source at `paper-server/src/minecraft/java/net/minecraft/server/players/PlayerList.java` and related generated Minecraft sources; do not hand-edit patch hunks as the primary workflow.
- [ ] Refactor the Worldline branch of `PlayerList.placeNewPlayer` so it binds the inbound play listener to the prepared player, emits the login packet only as the proxy-consumed readiness marker, stores the connection/listener/cookie in the preparation, and returns before normal player registration.
- [ ] Keep listener flushing suspended and mark gameplay output suppressed until activation.
- [ ] Run `./gradlew fixupSourcePatches`, then `./gradlew rebuildPatches`; inspect the generated patch diffs, then run `./gradlew applyPatches` again to prove the patch stack reapplies.
- [ ] Re-run the Paper suite and compile task; expect success.
- [ ] Commit in `server`: `feat: attach staged M5 destination player`.

### Task 5: Atomic destination activation and retirement

**Files:** server `WorldlineControlServer.java`, `PlayerList.java.patch`, `ServerPlayer.java.patch`, tests.

- [ ] Add failing tests that `ACTIVATE_DESTINATION` is rejected before attachment and that a successful main-thread activation registers the exact prepared player before acknowledging.
- [ ] Add tests that no snapshot field changes between staging, attachment, and activation, and that retirement releases connection, player registration/tracking, prepared player, and chunk ticket exactly once.
- [ ] Edit generated Paper/Minecraft sources, then implement a dedicated `PlayerList.worldlineActivatePlayer(...)` path that performs the minimum Paper registration/tracking/menu/notification setup needed for a live player while suppressing duplicate client login/respawn/configuration packets and physical-node join announcements.
- [ ] Resume listener flushing only after activation state has committed on the Paper main thread.
- [ ] Implement `worldlineRetirePlayer(...)` for committed/attached/active destination cleanup without saving stale/partial state or firing duplicate logical events.
- [ ] Run `./gradlew fixupSourcePatches`, then `./gradlew rebuildPatches`; inspect patch diffs, re-run `./gradlew applyPatches`, run the Paper suite and `:paper-server:compileJava`, and commit `feat: activate and retire M5 destinations`.

### Task 6: Source committed-away fencing and cleanup

**Files:** server `WorldlineControlServer.java`, `PlayerList.java.patch`, `ServerPlayer.java.patch`, tests.

- [ ] Write failing tests for `COMMIT_SOURCE` matching a frozen transfer, save suppression after commit-away, cleanup only from committed-away, duplicate cleanup tombstones, and rejection of old-epoch mutation/unfreeze attempts.
- [ ] Edit generated Minecraft sources to add `ServerPlayer` transfer-authority flags and make `PlayerList.save`, incremental save, disconnect removal, damage, and tick paths reject committed-away source persistence/mutation.
- [ ] Implement main-thread `worldlineCleanSourcePlayer(...)` that removes tracking/player-list state without saving epoch `n`, broadcasting a physical-node quit, or reapplying cleanup when the TCP close arrives.
- [ ] Ensure connection closure after control cleanup is transport-only.
- [ ] Run `./gradlew fixupSourcePatches`, then `./gradlew rebuildPatches`; inspect patch diffs, re-run `./gradlew applyPatches`, run Paper tests/compile, and commit `feat: clean committed-away M5 sources`.

### Task 7: Proxy backend bindings and gameplay-output gate

**Files:** proxy `BackendSessionBinding.java`, `VelocityServerConnection.java`, `BackendPlaySessionHandler.java`, `ClientPlaySessionHandler.java`, new and existing tests.

- [ ] Write failing binding predicate tests for:
  - initial source at epoch/generation 0;
  - source rejected immediately at `COMMITTED`;
  - destination rejected during `COMMITTED` and accepted only at `ACTIVE_DESTINATION`;
  - stale same-server connection after a later return;
  - obsolete client connection ID;
  - wrong transfer/route generation.
- [ ] Implement immutable binding assignment for the initial source when the live record is registered and for destination connections at construction.
- [ ] Centralize `mayForwardGameplay(binding)` in the live-session store or a small gate class; use it in generic, unknown, plugin, and explicitly handled gameplay-output paths before client writes.
- [ ] Keep readiness/login and connection-control handling in transition handlers rather than granting a generic bypass.
- [ ] Run the focused binding tests and full proxy Worldline suite; commit `feat: fence M5 backend gameplay output`.

### Task 8: Two-command commit barrier and idempotent control retries

**Files:** proxy `HandoffControlPlane.java`, `WorldlineControlTransport.java`, control tests.

- [ ] Extend fake loopback control servers and add failing tests for both command orders, one-sided application, lost destination/source acknowledgements, v3 rejection before commit, mismatched echoed route/client fields, and retry of the same transfer ID.
- [ ] Change `commit()` to atomically update the proxy live record, then send `COMMIT_DESTINATION` and `COMMIT_SOURCE`; on retry, reread/accept `ALREADY_APPLIED` locally and resend both commands with the same transfer ID. Server idempotency makes resending both safe and avoids a second ambiguous acknowledgement store.
- [ ] Return a typed barrier result that distinguishes complete, retryable incomplete, and rejected-after-commit without invoking abort. Tests prove every partial-application permutation converges when both commands are resent.
- [ ] Implement bounded retry orchestration off the Netty event loop; all completions verify client connection ID, transfer, epoch, and route generation.
- [ ] Run focused transport/control tests and commit `feat: coordinate the M5 commit barrier`.

### Task 9: Invisible destination route installation

**Files:** proxy `ConnectedPlayer.java`, `VelocityServerConnection.java`, `TransitionSessionHandler.java`, `ClientPlaySessionHandler.java`, related tests.

- [ ] Add failing tests around an injectable connection-request seam proving no destination request starts before the commit barrier and the explicit resume context reaches the new connection.
- [ ] Add transition tests proving JoinGame is consumed as readiness, no client JoinGame/Respawn/configuration packet is written, the existing source binding stays physically open until cleanup, and destination gameplay stays fenced before activation.
- [ ] Add an internal `ConnectedPlayer` method for a Worldline connection request with immutable resume context; do not expose this through the public API.
- [ ] Update `TransitionSessionHandler` to install the M5 destination connection without invoking M1's global-property path or prematurely closing/clearing the source.
- [ ] Preserve connection-scoped keepalive and teleport-confirmation ownership.
- [ ] Run proxy tests and commit `feat: install M5 destination routes invisibly`.

### Task 10: Activation, ordered replay, cleanup, and timeout coordinator

**Files:** proxy `HandoffReplayBuffer.java`, `ServerboundMovementRouter.java`, `ClientPlaySessionHandler.java`, tests.

- [ ] Write failing replay tests for monotonic sequence, crossing packet first, later movement order, one-shot drain, no replay before activation, epoch/generation binding, count/time overflow, and discarded replay on post-commit failure.
- [ ] Add coordinator tests for the full successful ordering:

  ```text
  SNAPSHOT_STAGED -> local COMMIT -> commit barrier -> connect/ready ->
  ACTIVATE_DESTINATION -> replay -> CLEAN_SOURCE -> close source -> retire transfer
  ```

- [ ] Add failures at commit barrier, connection, readiness, activation, replay, cleanup, client disconnect, and an independently scheduled post-commit deadline. For every phase assert: no post-commit abort/source resurrection; replay discarded exactly once; destination `RETIRE_DESTINATION` is sent when applicable; source cleanup uses bounded attempts; the client is safely disconnected; committed/tombstone records remain recoverable; and retries/resources are bounded. Transient injected failures must converge to cleanup; a permanently unavailable source must leave explicit pending-cleanup state for later M7 recovery rather than claiming completion.
- [ ] Implement the coordinator with one active future and event-loop-only mutable state. Run blocking commands on virtual threads and schedule the overall deadline on the player's event loop.
- [ ] Generalize the movement buffer into one-shot replay entries; write them to the active destination only after activation.
- [ ] Retire the live record to the next `ACTIVE_SOURCE` steady state while retaining bounded terminal tombstones for duplicate acknowledgements.
- [ ] Run focused and full proxy tests; commit `feat: complete M5 commit activation and replay`.

### Task 11: Packet classification and trace assertions

**Files:** proxy session handlers/tests, server instrumentation, `harness/assert-m5-trace.sh`.

- [ ] Add failing proxy tests for source/destination keepalives, teleport confirmations, unsigned-chat acknowledgements, unknown packets, and unexpected configuration/respawn transitions in pre- and post-commit phases.
- [ ] Implement the design table exactly: pre-commit unsupported traffic aborts; post-commit unsupported traffic disconnects safely; no connection-sensitive packet is blindly replayed.
- [ ] Add server trace fields for source freeze/commit-away/cleanup ticks, destination attachment/activation ticks, first replay sequence/position, and rejected stale output.
- [ ] Write `assert-m5-trace.sh` to fail on dual-authority tick overlap, source authoritative position in the east partition, first destination movement sequence other than the crossing entry, or client-visible JoinGame/Respawn/configuration output.
- [ ] Test the trace parser with passing and deliberately failing fixture logs stored under a temporary test directory or generated inline by a script test mode.
- [ ] Run all focused suites and commit submodule instrumentation changes.

### Task 12: Harness, documentation, and full verification

**Files:** root harness scripts/config/README, roadmap, submodule pointers.

- [ ] Remove `-Dworldline.splice-target=server-b` from normal M5 harness startup; keep an explicit `WORLDLINE_M1_MANUAL_SPLICE=1` compatibility mode only if the manual M1 flow still works.
- [ ] Add documented M5 timeout/protocol/trace flags consistently to `run-slice.sh` and `run-one.sh`.
- [ ] Add a harness command or instructions for the M5 boundary walk and trace assertion.
- [ ] Add a deterministic live acceptance procedure that gives the player a mixed inventory and selected slot, partial health and hunger, nonzero XP, and an active potion effect; captures a canonical before-state hash at source freeze and after-state hash at destination activation; and fails on mismatch or duplicated inventory/effect state.
- [ ] Record explicit observation from an unmodified vanilla client for no disconnect/reconnect/loading screen. Automated packet traces supplement but do not replace this client-visible check.
- [ ] Run proxy full tests and checks required by that submodule.
- [ ] Run Paper `applyPatches`, Worldline suite, relevant broader checks, and jar builds.
- [ ] Run `harness/build-jars.sh`, initialize/run the slice if local run directories exist, execute prepare/freeze/stage/M5 trace checks, and record any unavailable manual-client verification explicitly.
- [ ] Run `git diff --check` in root and both submodules; inspect every diff and status.
- [ ] Perform a dedicated bug/security audit covering protocol parsing, untrusted lengths, stale/ABA bindings, thread confinement, post-commit failure, resource/tombstone bounds, log sensitivity, and denial-of-service paths. Fix every confirmed issue test-first.
- [ ] Update `docs/vertical-slice-roadmap.md` status only to the level proven by the verification evidence. Do not mark M5 complete unless the mixed-state live acceptance and vanilla-client observation have both been performed successfully.
- [ ] Commit root harness/docs/submodule pointers with `feat: complete M5 vertical slice`.
