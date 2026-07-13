# ADR 0007: Standalone and clustered deployment profiles

- **Status:** Accepted
- **Date:** 2026-07-13
- **Supersedes in part:** ADR 0002 and ADR 0003, only where they require Redis or an external SQL database as specific infrastructure products
- **Preserves:** The delivery semantics, ownership model, fencing, idempotency, durability, recovery, and partition-allocation requirements of ADR 0002 through ADR 0005

## Context

Worldline must serve two very different deployment classes without splitting into separate products or weakening its correctness model.

A standalone deployment may consist of one Worldline Proxy and one or more Worldline Servers. This is the natural topology for development, homelabs, small public servers, and many ordinary SMP deployments. Requiring operators in that topology to also deploy Redis and a separate SQL server creates avoidable operational cost, additional failure modes, more credentials and network configuration, and a higher barrier to adoption.

At the same time, Worldline must preserve a credible path to future multi-proxy deployments. Multiple active proxies need shared durable state and distributed coordination semantics that a proxy-local SQLite database and process memory cannot provide by themselves.

The architecture therefore needs deployment profiles with stable Worldline-level semantics and swappable infrastructure implementations.

## Decision

### Standalone is a permanent first-class topology

Worldline MUST support a standalone topology containing exactly one active Worldline Proxy and one or more Worldline Servers without requiring any external database, cache, broker, or coordination service.

The normal standalone deployment is:

~~~text
players
   |
   v
Worldline Proxy
   - owns player-facing connections
   - holds the active coordinator role
   - owns live player-session records
   - uses embedded SQLite for durable control-plane state
   - uses process memory for reconstructible live coordination state
   |
   +--> Worldline Server A
   +--> Worldline Server B
   +--> Worldline Server N
~~~

Standalone support is not a reduced or development-only mode. It is a permanent supported deployment profile.

### Embedded SQLite is the default durable control store

In standalone mode, the Worldline Proxy MUST be able to use embedded SQLite for durable control-plane metadata, including at least:

- Materialized partition assignments.
- Sticky ownership.
- Ownership epochs and fencing state.
- Partition lifecycle state.
- Storage versions or recovery metadata when defined by later ADRs.
- Durable audit records required by the control plane.
- Durable operation journal records when retryable work requires crash recovery.

SQLite is not the primary store for ordinary chunk, entity, or point-of-interest world data. Authoritative world data continues to follow ADR 0004 and remains owner-local using Paper-native storage formats where practical.

The standalone implementation MUST preserve the transactional semantics required by ADR 0003, including atomic first materialization, unique partition identity, conditional ownership changes, monotonic ownership epochs, and crash-safe durable state transitions.

### Redis is not required for standalone operation

Standalone mode MUST NOT require Redis.

In the initial single-proxy topology, the proxy already holds the active coordinator role and owns persistent direct control connections to Worldline Servers. The following responsibilities may therefore be implemented without an external Redis deployment:

| Responsibility | Standalone mechanism |
| --- | --- |
| Server presence | Direct connection state plus heartbeats and timeout handling |
| Live partition leases | Proxy-owned in-memory state derived from durable assignments and current server liveness |
| Cached partition ownership | Proxy-local in-memory cache |
| Temporary handoff state | Proxy-local memory, persisted only where recovery semantics require it |
| Reconstructible invalidations and notifications | Direct proxy/server or server/server control messages |
| Retryable asynchronous work | Embedded durable operation journal when required |

Loss of reconstructible in-memory state may reduce availability or require resynchronization, but MUST NOT create conflicting authority, duplicate permanent state, or allow a stale owner to commit mutations.

### Persistent direct connections remain the primary control transport

The product choice change in this ADR does not change the messaging semantics of ADR 0002.

Synchronous handoff commands and acknowledgements continue to use persistent direct proxy/server control connections. Boundary projections continue to use persistent direct server/server connections as required by ADR 0004. Ordinary per-tick movement MUST NOT be routed through Redis, a database, or another centralized message broker.

Every message family still MUST define:

- Whether delivery is synchronous, retryable, or best effort.
- Ordering requirements.
- Stable operation identity or duplicate-handling rules where needed.
- The authoritative state used for recovery.

### Infrastructure abstractions must represent Worldline semantics

Core Worldline logic MUST NOT depend directly on infrastructure-specific concepts such as Redis keys, Redis channels, Redis Streams consumer groups, or SQLite statements scattered through routing and authority code.

Instead, implementation boundaries SHOULD represent Worldline concepts such as:

~~~text
PartitionDirectory
Membership
CoordinatorState
PlayerSessionStore
OperationJournal
~~~

These boundaries exist to preserve semantics across deployment profiles, not to create a universal storage framework before requirements are known.

The project MUST avoid premature abstractions that attempt to support every possible database, broker, lease service, or consensus system before a concrete clustered topology requires them.

### Clustered multi-proxy support remains an explicit future requirement

Worldline MUST preserve a path to future deployments with two or more active proxies.

A future clustered topology may require shared implementations for:

- Durable partition directory and ownership epochs.
- Cross-proxy player-session metadata.
- Server membership.
- Coordinator leadership or serialized authority changes.
- Short-lived leases.
- Durable operation journals.
- Invalidation and resynchronization signals.

The exact clustered backends are intentionally undecided. Possible implementations include, but are not limited to:

- PostgreSQL only.
- PostgreSQL plus Redis.
- PostgreSQL plus etcd.
- Another shared transactional store and distributed coordination mechanism that satisfies Worldline's required semantics.

Redis MUST NOT be treated as the only valid future coordination backend merely because earlier ADRs selected it for the initial architecture.

A separate accepted ADR is required before implementing multi-proxy coordination or highly available coordinator leadership.

### Single-proxy SQLite and zero-Redis support must remain available

Future clustered features MUST NOT remove the standalone deployment profile.

Worldline MUST continue to support:

~~~text
1 Worldline Proxy
1+ Worldline Servers
embedded SQLite
no Redis
no external broker
no external SQL server
~~~

unless a future ADR explicitly supersedes this decision. Such a superseding decision would require a documented migration path and a compelling correctness reason, not convenience for one clustered implementation.

### Multi-proxy scaling and transparent proxy failover are separate problems

Supporting multiple active proxies does not imply that an existing vanilla Minecraft TCP session can transparently survive the failure of the proxy process that owns that connection.

A future multi-proxy architecture may provide:

- Horizontal scaling of player connections across several proxies.
- Shared cluster state.
- Cross-proxy routing and coordination.

without initially providing transparent live-session failover after proxy process loss.

These guarantees MUST be documented separately so Worldline does not claim session survivability merely because multiple proxies are running.

## Consequences

### Benefits

- The default deployment requires only Worldline Proxy and Worldline Server processes.
- Homelab and small-server operators do not need Redis or a separate database server.
- SQLite provides transactional durability without a separate service.
- The single coordinator can keep reconstructible coordination state locally without pretending it is a distributed problem.
- The architecture still preserves future multi-proxy scaling.
- Worldline-level semantics remain independent of one infrastructure vendor or product.
- Direct connections remain on latency-sensitive handoff and projection paths.

### Costs and risks

- Standalone and clustered implementations will eventually require different storage and coordination implementations.
- The project must test semantic parity across deployment profiles.
- Proxy-local SQLite makes the standalone proxy host a control-plane durability failure domain unless operators back it up.
- A future multi-proxy design still needs rigorous leader election, fencing, shared session semantics, and recovery behavior.
- An embedded durable operation journal may require implementation work that Redis Streams would otherwise provide.
- Transparent survival of a live client connection after proxy process loss remains a separate unsolved problem.

## Alternatives considered

- **Require Redis and an external SQL database for every deployment:** rejected because the initial single-proxy topology already centralizes coordination and can satisfy durable metadata requirements with embedded SQLite.
- **Use only in-memory state in standalone mode:** rejected because partition assignments, ownership epochs, and other durable control-plane metadata must survive proxy restarts.
- **Store control-plane metadata in JSON or ad hoc files:** rejected because Worldline requires atomicity, uniqueness, conditional updates, ordering, and crash-safe durable transitions.
- **Commit now to PostgreSQL plus Redis for future multi-proxy support:** rejected because the actual clustered topology, coordinator election model, shared session model, and failover guarantees are not yet defined.
- **Build a universal pluggable infrastructure framework immediately:** rejected as premature abstraction. Worldline should define narrow semantic boundaries and add implementations when concrete deployment profiles require them.
- **Drop future multi-proxy support:** rejected because Worldline's long-term scaling model should not be permanently constrained to one proxy process.

## Compliance

An implementation conforms to this decision only if:

- A single-proxy deployment can run with embedded SQLite and no Redis or external SQL server.
- Standalone mode remains a first-class supported topology.
- Durable ownership and fencing semantics survive proxy restarts.
- Reconstructible in-memory state cannot silently create split brain or duplicate permanent authority.
- Persistent direct control connections remain the primary path for synchronous handoff traffic.
- Boundary projections remain on persistent direct server/server connections.
- Infrastructure-specific products do not leak throughout core authority and routing logic.
- Future clustered implementations preserve the same ownership, fencing, idempotency, and recovery semantics.
- No implementation claims transparent live-session failover merely because multiple proxies are present.
- Any future multi-proxy coordination design is introduced through a separate accepted ADR.

