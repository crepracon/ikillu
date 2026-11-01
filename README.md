# The Hollow Kingdom

A text-based fantasy social deduction RPG built in Godot 4. The full design lives in
[`fantasy_social_deduction_rpg_design.md`](fantasy_social_deduction_rpg_design.md).

## Current state

The core rules skeleton, with no UI or networking yet:

| File | What it does |
| --- | --- |
| `core/GameSession.gd` | The single entry point for changing game state. Validates every request. |
| `core/GameState.gd` | Authoritative session data, event log, public/private views. |
| `core/GamePhase.gd` | Phase state machine and which actions each phase allows. |
| `core/PlayerState.gd` | Per-player data: role, action points, status effects. |
| `core/GameConfig.gd` | Every tunable number in one place. |
| `core/Enums.gd` | Factions, roles, classes, status effects. |
| `systems/RoleSystem.gd` | Seeded secret role assignment. |
| `systems/VotingSystem.gd` | Council vote tallying (strict majority). |
| `systems/NightSystem.gd` | The cult's nightly action. |
| `tests/test_core_loop.gd` | Headless tests that play full games. |

## Running the tests

From the project folder:

```
godot --headless --script res://tests/test_core_loop.gd
```

It prints PASS/FAIL per check and exits with code 1 if anything fails.

## Prototype rules

These are starting defaults. Values marked `DEFAULT` in `GameConfig.gd` are meant to be tuned.

**Nobody dies or gets removed.** The game is a race:

- **The cult wins** when the ritual reaches **5**.
- **The village wins** by exposing every cultist at council.

**Day loop:** Morning → Investigation → Social → Council → Night.

- Each player gets **3 action points** per day for moving, investigating, and talking to NPCs. Chat is free.
- **Council:** an accusation needs a strict majority of eligible voters. Ties or split votes mean no accusation.
  - Accuse a cultist: they're **exposed**. They stay in the game but lose their vote and night powers.
  - Accuse an innocent: the ritual gains **+1**. The innocent player is unaffected.
- **Night:** the cult takes **one** shared action:
  - **Advance the ritual** (+1). This is the default if they don't choose.
  - **Hex a player** instead, trading tempo for disruption:
    - `WEARY`: -1 action point for the next day.
    - `MUDDLED`: placeholder for "messing with their cards"; future investigation systems will make that player's next result unreliable.
- Ritual progress and hexes are public, so everyone feels the clock.

**Cultist count:** 4–6 players → 1, 7–9 → 2, 10 → 3.

## Not built yet

Networking (planned: WebSocket, so playtests can run in a browser), lobby UI, locations,
investigation results, evidence, NPCs, and the AI narrative service.
