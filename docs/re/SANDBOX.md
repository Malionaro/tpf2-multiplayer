# Sandbox mode: its tools and what multiplayer needs from them

Build 35924. Measured on 2026-09-27 in a single-player game with the stock **Sandbox mode** mod
enabled, through the multiplayer mod's `EVAL` inject line (`mp/inject.lua`). Labels as in
[README.md](README.md).

## What Sandbox mode is

The stock mod `urbangames_sandbox_1` only sets `game.config.sandboxButton = true` in its `runFn`
(`res/config/base_config.lua` defaults it, and `industryButton`, to `false`). Everything else is the
game's own tools behind that button. [CONFIRMED, mod.lua]

| tool | engine command | multiplayer today |
|---|---|---|
| place a town (`UI::TownBuilder`, [COMMANDS.md](COMMANDS.md#ui-tools)) | `CreateTowns` (`make_cmd` `0x9dd0b0`) | **not replicated**: the town exists on the placer's game only, and the next world check reports a desync |
| demolish a town (`UI::TownBulldozerAction`) | `RemoveTown` (`0x9dd920`) | not replicated |
| town and industry controls | `SetTownInfo`, `DevelopTown`, `setSimBuildingManualDevelopment` | not replicated |
| place an industry | `BuildProposal` from the construction tool (caller `0x419f62`) | goes through the CONXP path like any construction; not yet tested with an industry |

A player's report on 2026-09-27 (two players, 0.7.0.6, a Sandbox save with 96 mods) shows the
first row in the field: one game's world gained 39 streets and 195 town buildings between two hash
stamps with no command sent (`$$ TOWN t=41556 vs b: 516 vs 711`), later the other's gained 56 and
292, and each was undone by a resync. [MEASURED, the players' logs]

## The script API

- `api.type` has `CreateTowns`, `TownInfo`, `RemoveTown`, `SetTownInfo`, `DevelopTown`,
  `Town`, `TownBuilding`, `TownBuildingParams`, `TownConnection`. [MEASURED]
- `api.type.TownInfo.new()` prints as: [MEASURED, `debugPrint`]

  ```
  name = "", position = { x = 0, y = 0 },
  initialLandUseCapacities = { 0, 0, 0 },          -- residential, commercial, industrial
  landUse2CargoNeeds = { {}, {}, {} },             -- cargo type ids per land use
  ```

  `api.type.CreateTowns.new()` is `{ towns = {} }`.
- The vectors are engine containers: `ti.landUse2CargoNeeds[2] = {27, 27, 26}` fails ("expected
  userdata, received table"); assigning the elements works (`local v = ti.landUse2CargoNeeds[2];
  v[1] = 27 ...`). [MEASURED]
- `api.cmd.sendCommand(api.cmd.make.createTowns({ti}), cb)` applies **while the game is paused**:
  the callback reports `success=true` and the town is complete at the same game time. [MEASURED]
- A town the tool placed reads back (`api.engine.getComponent(t, api.type.ComponentType.TOWN)`)
  with `initialLandUseCapacities`, `cargoNeeds` (per land use), `sizeFactor` 1.2,
  `growthTendency` 0, `customCargoNeeds` false, `developmentActive` true. The capacities start
  where the command put them and grow from there. [MEASURED]
- The game script refuses new globals ("creating globals by assignment is not allowed", from
  `res/scripts/init.lua`); `rawset(_G, name, value)` goes around it for a probe. [MEASURED]

## Town creation is deterministic

From one frozen state (a save written at speed 0, game time 765.8), the same `createTowns`
command (a town at (1500, -1500), capacities 148/136/109) produced the identical town twice, in
two loads: [MEASURED]

| | run 1 | run 2 | run 3 (no cargo needs) |
|---|---|---|---|
| town entity | 22590 | 22590 | 22590 |
| town buildings | 158 | 158 | 158 |
| digest of their positions | `3211685293` | `3211685293` | `3211685293` |
| street edges within 900 m | 42 | 42 | 42 |
| digest of their end points | `357314705` | `357314705` | `357314705` |

So a town placed from the same command at the same simulation step comes out the same on every
game: the multiplayer replay can stamp the command like any other.

## The cargo needs are the tool's choice, not the engine's

With `landUse2CargoNeeds` left empty (run 3) the town is created with **empty** needs and the same
layout. The engine does not fill them in, and they do not shape the town. The town tool placed its
town (Palm Bay) with needs `27, 27, 26` / `23, 24, 25`: the tool picks them before it sends the
command. [MEASURED]

For replication this means: capture the command the tool sends on the placing player's game and
ship that `TownInfo` whole (name, position, capacities, needs). A peer must never ask the tool, or
anything else, to choose again.

## What is still open

- The C++ layout of the `TownInfo` vector in the `CreateTowns` payload, for a capture at the
  factory `0x9dd0b0` (the same cancel-and-replay path as the other hooked factories). The values
  above are known, which makes a byte dump at the factory easy to read.
- Whether the tool's command carries the name it shows (a random town name) or lets the engine
  name the town.
- `RemoveTown`, `SetTownInfo`, `DevelopTown` and industry placement: the same questions, not yet
  measured.
