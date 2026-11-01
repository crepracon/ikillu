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
| `autoload/Network.gd` | WebSocket host/join/dedicated server and the server-authoritative chat. |
| `chat/ChatScreen.gd` | The chat room UI (built in code). |
| `chat/ChatRules.gd`, `chat/RateLimiter.gd` | Name and message validation, commands, spam limits. |
| `npc/NPCManager.gd` | All NPCs in a session: finding them by name, what the AI may know, applying replies by the rules. |
| `npc/NPCState.gd` | One NPC: identity, knowledge, trust, memories, hearsay. |
| `npc/NPCConfig.gd` | Trust, memory and conversation numbers. |
| `narrative/NarrativeManager.gd` | Server-only node that calls the Claude API, with retries and scripted fallback. |
| `narrative/NarrativeRequest.gd` | Builds the prompt and the reply's JSON schema. |
| `narrative/NarrativeResponse.gd` | Checks and cleans the AI's reply. |
| `narrative/NarrativeSettings.gd` | API key, model and endpoint settings. |
| `tests/test_core_loop.gd` | Headless tests that play full games in both modes. |
| `tests/test_chat_rules.gd` | Headless tests for chat validation. |
| `tests/test_npc_dialogue.gd` | Headless tests for NPC knowledge, trust, memory, prompts and the AI client. |

## The chat room

Running the project opens the chat room: the first multiplayer piece, built on WebSockets
so it will also work from a browser export later.

**Try it on one computer:**
1. In the Godot editor, open *Debug → Customize Run Instances*, enable multiple instances, and set it to 2 (or just run the project twice).
2. In the first window, enter a name and click **Host a room**.
3. In the second window, enter a different name and click **Join** (address `127.0.0.1`, port `8910`).

**Play over a network:** the host shares their IP address, and everyone else joins it. Port
8910 needs to be reachable (port-forwarded, or use something like Tailscale or ZeroTier).

**Dedicated server:** run with no window, then everyone joins it:

```
godot --headless --path . -- --server --port=8910
```

**In the room:**
- Type to talk to everyone.
- `/w name message` whispers privately. Double-clicking a name in the list starts one.
- `/ask name question` talks to one of the townsfolk (see below). `/npcs` lists them.
- Names are letters, numbers, `-` and `_`. Duplicate names get a number added.

**How it's secured:** the server is the only authority. Clients can only ask to join or
send a message; the server checks names, caps message length, rate-limits spam, and decides
who receives what. Whispers only go to the two people involved. Player text is escaped so
nobody can inject formatting into other players' chat logs.

The code is in `autoload/Network.gd` (connections and server logic), `chat/ChatScreen.gd` (UI),
and `chat/ChatRules.gd` (validation).

## Talking to the townsfolk (AI NPCs)

NPCs answer in their own voice, powered by Claude. Each one remembers every player separately,
warms up or sours depending on how they're treated, keeps secrets until they trust you, and
passes on gossip, all inside the world of the scenario.

**Try it:** in the chat room, double-click a name under *Townsfolk*, or type
`/ask mara who has the corner suite?`. Answers are private to you, so you can share them
honestly, twist them, or keep them to yourself.

**Turn the AI on.** Only the machine running the server needs this (the host, or the dedicated
server). Players who join need nothing.

1. Get an API key from the Claude Console at [platform.claude.com](https://platform.claude.com/).
2. Set it as an environment variable, then start Godot:
   - Windows: `setx ANTHROPIC_API_KEY "sk-ant-..."`, then restart the Godot editor.
   - macOS/Linux: `export ANTHROPIC_API_KEY="sk-ant-..."` in the shell you launch Godot from.

   Or put it in `user://narrative.cfg` (in the editor: *Project → Open User Data Folder*):
   ```
   [narrative]
   api_key="sk-ant-..."
   ```
3. **Never put the key in the project folder.** Everything in `res://` ships inside exported
   games, so every player would get a copy.

Without a key, NPCs give short scripted brush-offs and everything else still works. The server
log says which mode it's in.

The default model is Claude Haiku 5.5 (`claude-haiku-5-5`), the fastest current Claude model. At
$0.10 per million input tokens and $0.50 per million output tokens (November 2026), a typical
reply costs about $0.0003. Change it with `HOLLOW_NPC_MODEL` or `model=` in `narrative.cfg`. For a
public server, `HOLLOW_NPC_API_URL` can point at a small service that holds the key itself (the
narrative backend from the design doc), so the game server never needs it.

**How it stays fair.** The design doc's rule: the AI is the storyteller, not the referee.

| | Decided by |
| --- | --- |
| What an NPC says | The AI |
| What an NPC knows | Scenario data and game code. A secret (`share_at_trust`) only enters the prompt once the player has enough trust, so nobody can trick it out early. |
| Trust | Game code. The AI only labels how the player spoke (friendly, flattery, bribe, rude, accusation, threat). `NPCConfig.DEFAULT_REACTIONS` and each NPC's `reactions` turn that into a change, at most +1 per NPC per day. |
| Who the traitors are | Never sent. NPCs can't leak roles they were never told. A test checks that a traitor's NPC context is identical to an innocent's. |
| Town news | Public events only (sabotage, council results), plus plot progress as a mood. |
| Gossip | What players claim about others becomes hearsay the NPC may repeat, with who said it, marked as unverified. |

NPCs are told not to invent evidence: they can have hunches and gossip, but never claim to have
seen something that isn't in their notes. Every reply is checked before use (fixed JSON shape,
length caps, labels from fixed lists). A reply that breaks character gets one retry, then a
scripted line.

**In a game.** `GameSession` already has the rules, ready for when the chat room is wired to it.
NPCs can be questioned during INVESTIGATION. The first message to an NPC each day costs 1 action
point and opens a conversation of 4 messages (`NPCConfig.MESSAGES_PER_CONVERSATION`, DEFAULT).
The flow is `request_npc_message()` → `npc_dialogue_context()` → `NarrativeManager.reply()` →
`record_npc_reply()`.

**Writing NPCs.** Fields in the scenario JSON:

```json
"background": "Who they are and what everyone knows about them.",
"wants": "What they're after.",
"speech": "How they talk.",
"knowledge": [
  {"text": "Shared with anyone who asks.", "share_at_trust": 0},
  {"text": "A secret.", "share_at_trust": 2, "hint": "How they act while hiding it."}
],
"reactions": {"bribe": 1, "threat": -3}
```

`notes` is for designers and never reaches the AI. The Wayward Lantern's secrets are
placeholders that cross-check each other (the grey-cloaked rider, the cellar tunnel, the
midnight guard change); rewrite them freely. Game code can add knowledge mid-game with
`NPCState.learn(text, share_at_trust, hint)`, for example to give a witness what they saw at night.

## Running the tests

From the project folder:

```
godot --headless --script res://tests/test_core_loop.gd
godot --headless --script res://tests/test_chat_rules.gd
godot --headless --script res://tests/test_npc_dialogue.gd
```

The NPC tests use a fake AI connection, so they need no API key or network.

Each prints PASS/FAIL per check and exits with code 1 if anything fails.

## Not built yet

Connecting the chat room to the game session (lobby → start game → phases), using the
location map for movement, investigation results, evidence, and night actions that leave
something for NPC witnesses to notice (so the townsfolk can hold real clues about the traitors).
