# Worldline

Worldline is a Minecraft server software suite designed for one purpose: bringing distributed systems to Minecraft servers.

It allows a single survival world to be distributed across multiple backend servers while presenting players with one continuous world.

## How it works

A traditional Minecraft server can become constrained by its main game tick as its player count and active world area grow. Worldline distributes that workload across two components:

- **Worldline Proxy** — a fork of Velocity that accepts player connections and routes each player to a backend according to their current position in the world.
- **Worldline Server** — a fork of Paper that runs an authoritative partition of the world.

When a player attempts to cross into a partition owned by another Worldline Server, the proxy transfers player authority to that server seamlessly. The source does not authoritatively apply movement inside the remote-owned partition before the handoff commits. The transfer should not display a loading screen, require a reconnect, or otherwise reveal the backend change to the client.

## Deployment profiles

The standard standalone deployment requires only one **Worldline Proxy** and one or more **Worldline Servers**. It uses embedded SQLite for durable control-plane metadata and does not require Redis, an external SQL server, or a broker.

Future clustered deployments with multiple active proxies may use shared durable storage and distributed coordination backends, but those backends are intentionally not fixed yet. Standalone SQLite and zero-Redis operation remains a permanent first-class deployment profile.

Authoritative world data is stored owner-locally and replicated according to the accepted storage decisions in `docs/decisions/0004-owner-local-storage-and-boundary-visibility.md`; the control-plane database is not the primary blob store for ordinary chunk, entity, or point-of-interest data.

## Documentation

Worldline's architecture and accepted design decisions live in [docs](docs/README.md). These documents are normative: implementation changes that conflict with an accepted decision must first supersede that decision.

## Status

Worldline is in early development.
