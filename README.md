# redm_hunt_redm

RedM-only scripted synced hunter encounters with no public chat feedback.

## Commands

- `/sf <id>`: sheriff hunters on horseback, ride in, dismount, then attack with firearms.
- `/nf <id>`: ~7 hostile night folk with melee/primitive weapons.
- `/is <id>`: ~16 mounted indigenous strike riders in a coordinated wave.
- `/wildlife <id>`: dangerous beast that hunts the target directly.
- `/stophunt`: manually stop active encounter (requester, target, or controller).

## Sync Model

- Server holds one authoritative active encounter state.
- Server picks one client as AI controller (closest streamed player near target).
- Controller spawns fully networked entities and drives AI.
- Net IDs are logged and broadcast for verification; all entities are marked migratable and visible on all machines.
- Cleanup triggers when target dies/disconnects, all hunters die, timeout, or manual stop.

## Install

1. Place resource in your server resources folder.
2. Add `ensure redm_hunt_redm` in your `server.cfg`.
3. Restart resource.

## Notes

- No admin gate: all players can trigger commands.
- No in-game chat, feed, or top-screen notifications are sent by this resource.
- Debug output is console-only (`[HUNTER]`).
- Tunables are in `config.lua`.
