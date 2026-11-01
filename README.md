# The Hollow Kingdom

A text-based fantasy social deduction RPG built in Godot 4. The original design lives in
[`fantasy_social_deduction_rpg_design.md`](fantasy_social_deduction_rpg_design.md); this README
tracks where the prototype has diverged from it.

## The default story: Assassins at the Wayward Lantern

A spring storm has washed out the bridge at Hollowmere, and a group of travelers (the players)
is stuck at the Wayward Lantern inn. One of the other guests is **Duchess Isolde Marrow**,
travelling to the capital under guard. Hidden among the travelers are **assassins** with a
contract on her life.

- **The assassins win** when the **Contract** reaches **5**: scouting, bribing, and poisoning, one night at a time.
- **The travelers win** by unmasking every assassin at council.

The town is full of NPCs to question: Mara the innkeeper, Sir Kestrel of the duchess's escort,
Pell the stable boy, Captain Holt of the town guard, Aldric the blacksmith, Wenna the baker,
and Old Tobias the gravedigger. The full cast and map are in
[`data/scenarios/wayward_lantern.json`](data/scenarios/wayward_lantern.json).

### Game modes

The traitor faction is a swappable **game mode**. The rules engine is the same for every mode,
and each mode supplies its own labels, numbers, and scenario.

| Mode | Traitors | Plot | Scenario |
| --- | --- | --- | --- |
| `AssassinsMode` (default) | Assassins | Contract | The Wayward Lantern |
| `CultistsMode` | Cultists | Ritual | Blackthorn Village (from the design doc) |

## Prototype rules

Starting defaults, meant to be tuned. Shared numbers are in `core/GameConfig.gd`; plot
numbers are on each mode, marked `DEFAULT`.

**Nobody dies or gets removed.** The only life at stake is an NPC's.

**Day loop:** Morning → Investigation → Social → Council → Night.

- Each player gets **3 action points** per day for moving, investigating, and talking to NPCs. Chat is free.
- **Council:** an accusation needs a strict majority of eligible voters. Ties or split votes mean no accusation.
  - Accuse a traitor: they're **unmasked**. They stay in the game but lose their vote and night actions.
  - Accuse an innocent: the plot gains **+1**. The innocent player is unaffected.
- **Night:** the traitors take **one** shared action:
  - **Advance the plot** (+1). This is the default if they don't choose.
  - **Sabotage a player** instead, trading tempo for disruption:
    - `WEARY` (*Drugged* in Assassins mode): -1 action point for the next day.
    - `MUDDLED` (*Misled*): placeholder for "messing with their cards"; future investigation systems will make that player's next result unreliable.
- Plot progress and sabotage are public, so everyone feels the clock.
- Only the traitors know who the target is.

**Traitor count:** 4–6 players → 1, 7–9 → 2, 10 → 3.

## Code layout

| File | What it does |
| --- | --- |
| `core/GameSession.gd` | The single entry point for changing game state. Validates every request. |
| `core/GameState.gd` | Authoritative session data, event log, public/private views. |
| `core/GamePhase.gd` | Phase state machine and which actions each phase allows. |
| `core/PlayerState.gd` | Per-player data: role, action points, status effects. |
| `core/GameConfig.gd` | Rule numbers shared by every mode. |
| `core/Enums.gd` | Factions, roles, classes, status effects (mechanical, mode-agnostic). |
| `modes/GameMode.gd` | Base class: labels, plot numbers, scenario path. |
| `modes/AssassinsMode.gd`, `modes/CultistsMode.gd` | The two modes. |
| `scenarios/ScenarioLoader.gd` | Loads and validates scenario JSON. |
| `data/scenarios/*.json` | Settings, NPC casts, and location maps. |
| `systems/RoleSystem.gd` | Seeded secret role assignment. |
| `systems/VotingSystem.gd` | Council vote tallying. |
| `systems/NightSystem.gd` | The traitors' nightly action. |
| `tests/test_core_loop.gd` | Headless tests that play full games in both modes. |

## Running the tests

From the project folder:

```
godot --headless --script res://tests/test_core_loop.gd
```

It prints PASS/FAIL per check and exits with code 1 if anything fails.

## Not built yet

Networking (planned: WebSocket, so playtests can run in a browser), lobby UI, using the
location map for movement, investigation results, evidence, NPC dialogue and memory, and the
AI narrative service.
