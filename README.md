# Continuity

Continuity is a Minecraft server software suite designed for one purpose: bringing distributed systems to Minecraft servers.

It allows a single survival world to be distributed across multiple backend servers while presenting players with one continuous world.

## How it works

A traditional Minecraft server can become constrained by its main game tick as its player count and active world area grow. Continuity distributes that workload across two components:

- **Continuity Proxy** — a fork of Velocity that accepts player connections and routes each player to a backend according to their current position in the world.
- **Continuity Server** — a fork of Paper that runs an authoritative partition of the world.

When a player moves into a partition owned by another Continuity Server, the proxy transfers the player to that server seamlessly. The transfer should not display a loading screen, require a reconnect, or otherwise reveal the backend change to the client.

## Infrastructure requirements

Each Continuity Server requires:

- **Redis** for temporary state and pub/sub messaging.
- **SQL database** for permanent state.

## Status

Continuity is in early development.
