# Fantasy Social Deduction RPG --- Game Design & Architecture

**Working title:** The Hollow Kingdom\
**Engine:** Godot 4\
**Initial format:** Purely text-based multiplayer game\
**Core concept:** A cooperative fantasy mystery game with hidden
traitors, RPG-style investigation, and AI-powered NPC dialogue and
behavior.

------------------------------------------------------------------------

## 1. Game vision

The game combines three pillars:

1.  **Social deduction:** Players cooperate to solve a mystery, while
    one or more players secretly belong to an opposing faction.
2.  **Fantasy RPG investigation:** Players have classes, abilities,
    limited daily actions, and different ways to explore, gather
    evidence, and question NPCs.
3.  **Dynamic narrative:** NPCs remember relevant interactions, have
    their own knowledge and motivations, and respond to player behavior.

The central design principle is:

> The game simulation should be deterministic and authoritative; the
> storytelling should be dynamic.

The AI can make conversations and descriptions feel alive, but it must
not decide game rules, secretly change evidence, assign guilt, or
determine victory conditions.

The first version should be entirely text-based. Locations can be
represented as menus and descriptions rather than graphical maps.
Character sheets, inventory, evidence, and conversations can all be
presented through UI panels.

## 2. Core gameplay concept

Each session takes place in a fantasy settlement or other contained
setting. Something suspicious has happened, and the players must
investigate.

Most players belong to a cooperative faction trying to uncover the
truth. One or more players are hidden traitors with secret objectives
that conflict with the group.

The scenario has an underlying truth known to the server. Players
discover fragments of that truth through investigation, NPC
conversations, magical abilities, documents, and witness accounts.

The traitors participate in the investigation like everyone else. They
can mislead the group, conceal information, pursue private objectives,
and exploit uncertainty.

### Example scenario: The Curse of Blackthorn Village

A remote village has been isolated after a series of strange events:

-   Villagers have disappeared.
-   Strange sounds have been heard near the forest.
-   The village priest has been acting suspiciously.
-   Someone has been entering the old crypt.

Possible scenario elements:

-   A hidden cult is conducting a forbidden ritual.
-   The priest is concealing information.
-   The blacksmith has supplied weapons to someone.
-   A player is secretly connected to the cult.
-   Evidence can be discovered, misinterpreted, hidden, or manipulated.

The actual truth is fixed in the authoritative scenario data for the
session. AI-generated dialogue can vary, but it cannot rewrite that
truth.

------------------------------------------------------------------------

## 3. Daily gameplay loop

The day cycle should be an investigation phase, not merely a period
where players chat and accuse one another.

Each day is divided into five stages.

### 3.1 Morning --- aftermath

Players receive a report describing important overnight events.

Examples:

-   An NPC has disappeared.
-   A location has been disturbed.
-   A new clue has appeared.
-   A protective ward has failed.
-   Villagers are spreading a new rumor.

The report should reveal what characters could reasonably know. It
should not automatically expose secret roles or private actions.

### 3.2 Investigation --- gather information

Players spend action points on activities such as:

-   Searching locations.
-   Examining objects and evidence.
-   Interrogating NPCs.
-   Using class abilities.
-   Following rumors.
-   Preparing investigation tools.

Actions may reveal clues, create new leads, or produce ambiguous
results.

### 3.3 Social --- compare discoveries

Players can:

-   Share evidence publicly.
-   Share information privately.
-   Trade items.
-   Form temporary alliances.
-   Compare timelines and alibis.
-   Challenge another player's account.
-   Keep discoveries secret.

Information sharing should be a meaningful choice. A player who
discovers something can decide whether to reveal it, share it with one
person, or conceal it.

### 3.4 Council --- accusations and voting

Players discuss the available evidence, present theories, accuse
suspects, defend themselves, and vote.

The council should use information gathered during the investigation
phase. Evidence should be useful but rarely conclusive on its own.

### 3.5 Night --- secret actions and world resolution

Players with night abilities perform secret actions. The server
validates and resolves those actions, updates the world, and prepares
the next morning.

The exact night-action rules should be defined by the role system and
scenario.

------------------------------------------------------------------------

## 4. Action points and player activities

For the first prototype, give each player **3 action points per day**.

Actions should have costs and eligibility rules. Some actions may
require a class, item, location, or phase.

### 4.1 Investigation

Players search locations and objects.

Examples:

-   Search the abandoned chapel.
-   Examine footprints.
-   Investigate a broken magical seal.
-   Search for hidden passages.
-   Inspect a suspicious weapon.

Investigation results should be based on server-side rules, scenario
data, player abilities, and relevant conditions.

### 4.2 Interrogation

Players question NPCs about events and people.

Examples:

-   Ask the blacksmith about missing weapons.
-   Question the priest about strange rituals.
-   Ask the innkeeper who visited the tavern.
-   Persuade a guard to reveal what they witnessed.

NPCs can know information but refuse to reveal it. Their responses
depend on personality, motivations, knowledge, beliefs, memories, and
relationships.

### 4.3 Magical investigation

Magic provides fantasy-specific methods of gathering information.

Examples:

-   Detect magical residue.
-   Identify cursed objects.
-   Examine enchantments.
-   Detect illusions.
-   Read ancient inscriptions.

A magical result should not automatically identify a culprit. For
example, detecting necromancy at a crime scene does not prove that the
person who performed the crime is a necromancer. The evidence may have
been planted or left by someone else.

### 4.4 Social actions

Players can interact with one another.

Examples:

-   Share evidence.
-   Trade items.
-   Compare discoveries.
-   Form alliances.
-   Challenge an alibi.
-   Ask another player to accompany them.

Private information should be routed only to authorized participants.

### 4.5 Preparation and crafting

Players can prepare limited-use investigation tools.

Examples:

-   Holy water to test for undead corruption.
-   Detection powder to reveal hidden markings.
-   Protective charms against curses.
-   Translation scrolls for ancient writing.

Keep crafting simple in the first version. Its purpose is to create
strategic choices, not a large crafting simulation.

------------------------------------------------------------------------

## 5. Classes and abilities

Classes should provide different investigative strengths. They should
not determine a player's faction.

**Class and secret role are separate systems.** A Mage can be a loyal
investigator or a hidden Cultist. A Paladin can be loyal or secretly
working against the group.

Suggested initial classes:

  -----------------------------------------------------------------------
  Class             Specialty         Example abilities Limitation
  ----------------- ----------------- ----------------- -----------------
  Paladin           Truth and         Detect            Cannot always
                    protection        supernatural      distinguish a lie
                                      corruption;       from an honest
                                      protect another   mistake
                                      player; sense     
                                      certain magical   
                                      inconsistencies   

  Rogue             Investigation and Find hidden       Less effective at
                    secrets           clues; discover   interpreting
                                      secret passages;  magical evidence
                                      investigate       
                                      suspicious        
                                      movement          

  Mage              Magic and         Examine magical   Magical traces
                    knowledge         residue; identify can be ambiguous
                                      enchanted         or misleading
                                      objects; decode   
                                      magical writing   

  Ranger            Tracking and      Follow            Tracks can be
                    observation       footprints;       obscured or
                                      identify movement deliberately
                                      patterns;         misleading
                                      recognize         
                                      creature tracks   

  Bard              Social            Gather rumors;    Rumors are not
                    intelligence      build NPC         guaranteed to be
                                      relationships;    accurate
                                      learn about       
                                      rivalries         
  -----------------------------------------------------------------------

Class abilities should create complementary information. One player
might identify the magical nature of a clue while another identifies how
it was transported.

No class should be able to solve the entire mystery alone.

------------------------------------------------------------------------

## 6. Evidence system

Evidence should be the central investigation mechanic.

Instead of relying only on statements such as "I think Player 2 is the
traitor," players should be able to present evidence and explain how it
supports a theory.

### Evidence categories

  Category      Examples
  ------------- ---------------------------------------------------------
  Physical      Footprints, weapons, broken locks, bloodstained objects
  Magical       Spell residue, curses, enchantments, ritual markings
  Testimonial   NPC witnesses, rumors, alibis
  Documentary   Letters, journals, contracts, records

### Evidence properties

Each evidence item should track:

-   Unique ID.
-   Title and description.
-   Evidence category.
-   Source location.
-   Reliability or confidence.
-   Discovering player.
-   Related players, NPCs, or events.
-   Who currently knows about it.
-   Hidden details that may be revealed by abilities.
-   Whether it has been altered, forged, or tampered with.

Example GDScript model:

``` gdscript
class_name Evidence
extends Resource

var id: String
var title: String
var description: String

var evidence_type: String
var source_location: String

var reliability: float
var discovered_by: int

var related_players: Array[int]
var hidden_information: Dictionary
```

The exact representation can be refined during implementation. Evidence
visibility should be handled separately from the evidence's
authoritative data.

### Evidence should be incomplete

A clue should usually do one or more of the following:

-   Narrow down possible suspects.
-   Establish a timeline.
-   Confirm or contradict an alibi.
-   Reveal an NPC's secret.
-   Establish that a certain ability or item was involved.
-   Create a new lead.

Avoid making every clue directly identify the traitor.

### Example: Bloodstained ritual dagger

A ceremonial dagger is found in the crypt.

Different classes can discover different information:

-   Mage: identifies necromantic enchantments.
-   Paladin: detects a connection to a corrupted ritual.
-   Rogue: finds a hidden inscription on the handle.
-   Ranger: discovers that the dagger was carried through the forest.

Players must combine their discoveries to build a fuller picture.

------------------------------------------------------------------------

## 7. Traitor gameplay and secret objectives

Traitors should have meaningful activities during the day, not simply
wait for night.

Give traitors private objectives that encourage them to participate in
the investigation while working against the group.

Example objectives:

  -----------------------------------------------------------------------
  Objective                           Gameplay purpose
  ----------------------------------- -----------------------------------
  Mislead the investigation           Encourage suspicion toward an
                                      innocent player

  Recover forbidden evidence          Find a specific item before other
                                      players

  Protect an NPC                      Prevent the group from learning a
                                      secret

  Establish an alibi                  Create a believable account of
                                      activities

  Conceal a ritual site               Keep a location's secret
                                      undiscovered
  -----------------------------------------------------------------------

Objectives should be private and tracked by the authoritative server.

Avoid giving traitors unlimited ability to fabricate evidence. Deception
should work through choices, partial truths, selective disclosure, and
scenario-supported mechanics.

------------------------------------------------------------------------

## 8. Alibi and activity history

The server should record player activities during the day.

Example:

  Time        Player     Activity
  ----------- ---------- -------------------
  Morning     Player 1   Visited church
  Morning     Player 2   Visited tavern
  Afternoon   Player 1   Questioned priest
  Afternoon   Player 3   Visited crypt

At council, players can explain where they were and what they did.

The server knows the authoritative activity history, but other players
do not automatically see it. NPC witnesses, discovered evidence, and
other player observations may corroborate or contradict a story.

Future mechanics could include:

-   Disguises.
-   Secret passages.
-   Forged documents.
-   Misidentification by witnesses.
-   Concealed activities.
-   Magical illusions.

These are future additions, not requirements for the first prototype.

------------------------------------------------------------------------

## 9. Example day: The Missing Priest

**Scenario:** The Curse of Blackthorn Village\
**Day:** 2

The priest has disappeared. His chambers are in disarray, and villagers
report hearing strange chanting during the night.

Available investigations:

-   Search the church.
-   Question the village guard.
-   Visit the blacksmith.
-   Examine the forest trail.
-   Speak with the innkeeper.

Example player actions:

  -----------------------------------------------------------------------
  Player            Class             Action            Result
  ----------------- ----------------- ----------------- -----------------
  Player 1          Mage              Searches church   Discovers traces
                                                        of necromancy

  Player 2          Rogue             Questions guard   Learns someone
                                                        wearing a red
                                                        cloak entered the
                                                        church

  Player 3          Paladin           Examines altar    Discovers holy
                                                        protection was
                                                        deliberately
                                                        disabled

  Player 4          Ranger            Tracks outside    Finds footprints
                                      church            that disappear
                                                        near the forest

  Player 5          Bard / hidden     Visits innkeeper  Attempts to shift
                    traitor                             suspicion toward
                                                        the Mage
  -----------------------------------------------------------------------

At council, players have several pieces of incomplete information. They
must decide how reliable each source is and whether the clues support a
coherent theory.

The traitor has been active throughout the day and has a reason to
influence the discussion.

------------------------------------------------------------------------

## 10. NPC architecture

NPCs should be simulated as characters with persistent state, not merely
as dialogue trees.

Each NPC has five major components:

1.  **Identity:** Name, background, occupation, personality, beliefs.
2.  **Memory:** Relevant events and conversations the NPC remembers.
3.  **Knowledge:** Facts the NPC knows and beliefs the NPC holds.
4.  **Relationships:** Trust, fear, loyalty, resentment, and other
    attitudes toward players.
5.  **Motivations:** Goals, secrets, fears, and current priorities.

### Facts versus beliefs

This distinction is important.

Example:

-   Fact: The player showed Aldric a magical dagger.
-   Belief: Aldric suspects the player belongs to the cult.

NPCs can be mistaken. Their beliefs should not automatically become
objective facts.

### NPC memory types

  Type           Example
  -------------- --------------------------------------
  Event          Player threatened the blacksmith
  Observation    Player carried a suspicious artifact
  Conversation   Player asked about the crypt
  Relationship   NPC trusts the player more
  Discovery      NPC learned the mayor is corrupt

Not every interaction needs to become permanent memory. Store important
events and use summaries to keep context manageable.

### Example NPC: Aldric, the blacksmith

-   Personality: Suspicious, stubborn, protective.
-   Motivation: Protect his daughter.
-   Secret: Supplies weapons to the cult.
-   Fear: Being exposed.
-   Knowledge: Knows about the crypt.
-   Relationships: Vary by player.

Possible reactions:

  Player action            Potential response
  ------------------------ ----------------------------
  Bribes him               Becomes more cooperative
  Threatens him            Becomes hostile
  Shows cult evidence      Becomes nervous
  Befriends his daughter   Begins trusting the player
  Accuses him publicly     May flee or retaliate
  Discovers his secret     Dialogue changes

NPC reactions should be grounded in authoritative state. AI generates
the dialogue, while game code decides whether a relationship changes or
an NPC takes an action.

------------------------------------------------------------------------

## 11. AI narrative architecture

Use a separate backend service for AI requests. Do not expose an AI API
key in the Godot client.

Suggested initial backend:

-   Python.
-   FastAPI.
-   An LLM API.
-   Structured JSON request and response schemas.

Suggested backend layout:

``` text
narrative_service/
├── main.py
├── api/
│   ├── dialogue.py
│   ├── events.py
│   └── memory.py
├── engine/
│   ├── prompt_builder.py
│   ├── context_manager.py
│   ├── response_parser.py
│   ├── memory_manager.py
│   └── npc_decision_engine.py
├── models/
│   ├── npc.py
│   ├── dialogue.py
│   └── narrative_event.py
└── database/
    ├── models.py
    └── repository.py
```

### Dialogue request flow

1.  Player sends a message to the Godot server.
2.  Server validates phase, location, permissions, and NPC availability.
3.  Server gathers relevant NPC state and permitted context.
4.  Server sends a request to the narrative backend.
5.  Backend constructs a prompt and calls the AI model.
6.  Backend validates the response schema.
7.  Godot server validates the response against game permissions.
8.  Server delivers dialogue to authorized players.
9.  Approved memory updates are saved.

### Example AI context

``` json
{
  "npc": {
    "name": "Aldric",
    "personality": "Suspicious and stubborn",
    "emotion": "Nervous"
  },
  "player": {
    "relationship": "Distrusted",
    "known_actions": [
      "Asked about the crypt",
      "Threatened the village guard"
    ]
  },
  "npc_knowledge": [
    "The cult has been buying weapons",
    "Someone visited the crypt"
  ],
  "player_message": "Did you sell weapons to anyone recently?"
}
```

Only include information the NPC is permitted to use. Do not give every
NPC access to the full scenario secrets.

### Example structured response

``` json
{
  "dialogue": "I haven't seen anyone near the crypt.",
  "emotion": "nervous",
  "suggested_memory": {
    "type": "conversation",
    "summary": "Player asked about the crypt"
  },
  "behavior": "avoid_eye_contact"
}
```

The `behavior` field is descriptive, not an executable command.
Server-side code decides whether any behavior change is allowed.

### Use AI for

-   Contextual NPC dialogue.
-   Personality-driven responses.
-   Narrative descriptions.
-   Rumors and conversational hooks.
-   Summarizing important memories.
-   Describing outcomes already determined by game logic.

### Use ordinary game code for

-   Movement and location access.
-   Inventory.
-   Damage and status.
-   Voting.
-   Role abilities.
-   Relationship calculations.
-   Win conditions.
-   Evidence creation and discovery.
-   Random outcomes.

This keeps the game fair, predictable, cheaper to operate, and easier to
test.

------------------------------------------------------------------------

## 12. Location and exploration system

Locations should be data-driven objects. In the text-only version, each
location can be a menu with a description, available NPCs, searchable
objects, and actions.

Example locations:

  Location         Possible interactions
  ---------------- -----------------------------------
  Village Square   Talk to villagers, observe events
  Tavern           Gather rumors, meet travelers
  Blacksmith       Talk to Aldric, inspect weapons
  Church           Investigate, speak to priest
  Crypt            Search for evidence, explore

A location should define:

-   ID and display name.
-   Description.
-   Connected locations.
-   NPCs currently present.
-   Discoverable objects.
-   Available actions.
-   Hidden clues.
-   Environmental conditions.
-   Active events.

Example location data:

``` json
{
  "id": "village_tavern",
  "name": "The Rusty Griffin",
  "description": "A crowded tavern filled with nervous villagers.",
  "connections": [
    "village_square",
    "blacksmith"
  ],
  "npc_ids": [
    "innkeeper_mara",
    "traveler_edwin"
  ],
  "discoveries": [
    "bloodstained_letter"
  ],
  "events": []
}
```

Locations can change during the session:

-   The tavern catches fire.
-   The blacksmith closes after being accused.
-   The priest disappears from the church.
-   Guards begin patrolling the square.
-   A hidden crypt entrance is discovered.

The server determines the change; AI can generate the descriptive text.

------------------------------------------------------------------------

## 13. Scenario architecture

Scenarios should be data-driven and assembled from reusable components
rather than implemented as separate sets of scripts.

A scenario definition should include:

  Component            Purpose
  -------------------- ----------------------------------
  Setting              Village, castle, dungeon, etc.
  Main mystery         Central conflict
  Hidden truth         What actually happened
  Factions             Competing allegiances
  Secret roles         Player identities and objectives
  NPC cast             Characters, knowledge, secrets
  Evidence             Discoverable clues
  Events               Conditions that trigger changes
  Victory conditions   How each faction wins

### Two scenario layers

**Layer 1 --- Authoritative scenario data**

Contains the actual truth, role assignments, secrets, clues, rules, and
victory conditions.

**Layer 2 --- Narrative interpretation**

Contains generated descriptions, rumors, conversations, and
storytelling.

AI can vary the narrative presentation, but it cannot alter the
underlying mystery or invent authoritative evidence.

------------------------------------------------------------------------

## 14. Godot architecture

Use Godot 4 and its high-level multiplayer API. For the first
multiplayer implementation, ENet is a reasonable choice.

The game server should be authoritative. Clients request actions; the
server validates and resolves them.

### Proposed project structure

``` text
res://
├── autoload/
│   ├── NetworkManager.gd
│   ├── GameManager.gd
│   ├── StateManager.gd
│   ├── EventBus.gd
│   └── APIManager.gd
├── core/
│   ├── GameSession.gd
│   ├── GamePhase.gd
│   ├── GameState.gd
│   ├── PlayerState.gd
│   └── ActionResolver.gd
├── multiplayer/
│   ├── LobbyManager.gd
│   ├── PlayerSynchronizer.gd
│   ├── ChatManager.gd
│   └── PermissionManager.gd
├── systems/
│   ├── RoleSystem.gd
│   ├── VotingSystem.gd
│   ├── ActionSystem.gd
│   ├── InvestigationSystem.gd
│   ├── EvidenceSystem.gd
│   ├── InventorySystem.gd
│   ├── QuestSystem.gd
│   ├── RelationshipSystem.gd
│   └── EventSystem.gd
├── world/
│   ├── WorldManager.gd
│   ├── LocationManager.gd
│   ├── LocationState.gd
│   └── WorldEvent.gd
├── npc/
│   ├── NPCManager.gd
│   ├── NPCState.gd
│   ├── NPCMemory.gd
│   ├── NPCPersonality.gd
│   ├── NPCRelationship.gd
│   └── NPCDialogueManager.gd
├── narrative/
│   ├── NarrativeManager.gd
│   ├── NarrativeContext.gd
│   ├── NarrativeRequest.gd
│   └── NarrativeResponse.gd
├── scenarios/
│   ├── ScenarioManager.gd
│   ├── ScenarioDefinition.gd
│   └── ScenarioLoader.gd
├── ui/
│   ├── MainMenu.tscn
│   ├── Lobby.tscn
│   ├── GameScreen.tscn
│   ├── LocationPanel.tscn
│   ├── ChatPanel.tscn
│   ├── CharacterPanel.tscn
│   ├── InventoryPanel.tscn
│   ├── NPCInteractionPanel.tscn
│   ├── EvidencePanel.tscn
│   └── VotingPanel.tscn
└── data/
    ├── roles/
    ├── items/
    ├── npcs/
    ├── locations/
    └── scenarios/
```

This is a proposed organization, not a requirement to create every file
immediately. Keep systems modular, but avoid building empty abstractions
before they are needed.

### Core state

A central `GameState` should represent the authoritative session state.

Suggested categories:

-   Session: ID, seed, phase, round.
-   Players: public state, private state, location, action points,
    inventory.
-   Roles: secret identity, abilities, objectives.
-   World: locations, conditions, active events.
-   NPCs: knowledge, memories, relationships.
-   Quests: objectives and progress.
-   Evidence: discoveries and visibility.
-   Voting: accusations and votes.

Example:

``` gdscript
class_name GameState

var session_id: String
var current_round: int = 1
var current_phase: String = "exploration"

var players: Dictionary = {}
var npcs: Dictionary = {}
var locations: Dictionary = {}
var quests: Dictionary = {}

var discovered_clues: Array = []
var active_events: Array = []
var votes: Dictionary = {}

var world_seed: int
```

### Public and private state

Never broadcast the full game state to all clients.

Provide separate serialization functions:

``` gdscript
func get_public_player_state(player_id: int) -> Dictionary:
    # Return only information visible to everyone.
    pass

func get_private_player_state(player_id: int) -> Dictionary:
    # Return information visible only to that player.
    pass
```

Secret roles, private objectives, private conversations, and hidden
evidence must be filtered on the server.

------------------------------------------------------------------------

## 15. Phase state machine

Use a state machine to control valid actions.

Suggested phases:

1.  Lobby.
2.  Morning / aftermath.
3.  Exploration.
4.  Council.
5.  Night.
6.  World resolution.
7.  Game over.

Each phase defines which actions are allowed.

  Action               Exploration   Council        Night
  ------------------ ------------- --------- ------------
  Move locations               Yes        No      Limited
  Talk to NPCs                 Yes        No      Limited
  Investigate                  Yes        No   Role-based
  Public chat                  Yes       Yes           No
  Vote                          No       Yes           No
  Secret abilities              No        No          Yes

Exact timings and whether phases are timer-based or player-ready-based
can be decided during prototyping.

------------------------------------------------------------------------

## 16. Action resolution and event-driven design

All player actions should go through a central server-side action
pipeline.

Example: a player investigates the crypt.

1.  Client sends an investigation request.
2.  Server checks phase, location, permissions, and action points.
3.  Server checks whether the crypt can be investigated.
4.  Server calculates the outcome.
5.  Server updates authoritative state.
6.  Narrative service generates a description of the result if needed.
7.  Server sends the appropriate result to the relevant players.

Suggested action model:

``` gdscript
class_name PlayerAction

var player_id: int
var action_type: String
var target_id: String
var parameters: Dictionary
var action_id: String
```

Suggested `ActionDefinition` resource:

``` gdscript
class_name ActionDefinition
extends Resource

@export var action_id: String
@export var display_name: String
@export var description: String

@export var action_cost: int = 1
@export var allowed_phases: Array[String]

@export var required_class: String = ""
@export var target_type: String = ""
```

All action costs, permissions, and outcomes must be validated by the
server. Do not trust client-provided results.

### Event-driven architecture

When an important action occurs, create an event.

Example:

``` gdscript
{
    "type": "player_threatened_npc",
    "player_id": 2,
    "npc_id": "aldric_blacksmith",
    "location_id": "blacksmith",
    "round": 3
}
```

Relevant systems can respond:

-   RelationshipSystem updates trust.
-   NPCMemory records the incident.
-   NPC behavior logic considers possible reactions.
-   NarrativeManager generates dialogue.
-   EventSystem checks scenario triggers.

This avoids hardcoding every possible interaction between every system.

------------------------------------------------------------------------

## 17. Multiplayer security

The server is the authority. Clients request actions but never decide
whether those actions succeed.

Security requirements:

1.  Secret roles exist only in authoritative server state.
2.  Clients receive only information they are permitted to see.
3.  Private conversations are routed only to their participants.
4.  AI prompts contain only permitted information.
5.  AI output cannot directly execute game actions.
6.  Voting and role abilities are validated server-side.
7.  Random outcomes are generated server-side.
8.  Important state changes are recorded in an event log.
9.  Validate request sizes, action IDs, rate limits, and duplicate
    submissions.
10. Reconnection must not expose hidden information.

Example RPC shape:

``` gdscript
@rpc("any_peer", "reliable")
func request_investigation(location_id: String) -> void:
    if not multiplayer.is_server():
        return

    var player_id = multiplayer.get_remote_sender_id()

    if not action_resolver.can_investigate(
        player_id,
        location_id
    ):
        return

    action_resolver.resolve_investigation(
        player_id,
        location_id
    )
```

This is illustrative. Production code should validate all parameters and
use a robust action result/error system.

------------------------------------------------------------------------

## 18. Persistence and technology choices

Suggested stack:

  Component                   Technology
  --------------------------- -----------------------------------------
  Game client                 Godot 4
  Game server                 Godot headless dedicated server
  Multiplayer                 ENet / Godot high-level multiplayer API
  AI backend                  Python + FastAPI
  AI integration              LLM API
  Initial local persistence   JSON or SQLite
  Later production database   PostgreSQL
  Backend communication       HTTPS
  Deployment                  Linux server / Docker

During a session, keep authoritative state in server memory and save
important changes periodically and after significant events.

NPC memories should be scoped to the correct game session. Do not carry
memories into unrelated games unless a future persistent-campaign
feature explicitly requires it.

------------------------------------------------------------------------

## 19. MVP scope

Do not build every system at once. The first playable version should be
small enough to test the central loop.

### Proposed first scenario: The Last Bell of Blackthorn

  Element             Initial scope
  ----------------- ---------------
  Players                         5
  NPCs                            4
  Locations                       5
  Classes                         5
  Factions                        2
  Central mystery                 1

NPCs:

-   Aldric: blacksmith with a connection to the cult.
-   Mara: innkeeper who collects village rumors.
-   Father Rowan: priest hiding something in the church.
-   Edwin: traveler who witnessed something near the crypt.

Locations:

-   Village Square.
-   Tavern.
-   Blacksmith.
-   Church.
-   Crypt.

The first version should include:

-   Multiplayer lobby.
-   Secret role assignment.
-   Day and night phases.
-   Three action points per player per day.
-   Location selection through text menus.
-   Basic investigation actions.
-   Evidence discovery and sharing.
-   Basic NPC dialogue.
-   Council discussion and voting.
-   Win conditions.

Start with scripted NPC responses and deterministic investigation
results. Add AI-generated dialogue after the underlying game loop works.

------------------------------------------------------------------------

## 20. Development roadmap

### Milestone 1 --- Multiplayer foundation

-   Godot multiplayer lobby.
-   Server-authoritative session.
-   Player joining and leaving.
-   Basic chat.
-   Player state synchronization.

**Deliverable:** Players can join the same session and communicate.

### Milestone 2 --- Social deduction

-   Secret role assignment.
-   Player factions.
-   Exploration, council, and night phases.
-   Voting.
-   Victory conditions.

**Deliverable:** A complete Werewolf-style game without RPG complexity.

### Milestone 3 --- Text RPG exploration

-   Location system.
-   Movement between locations.
-   Character sheets.
-   Action points.
-   Basic inventory.
-   Investigation actions.
-   Evidence discovery.

**Deliverable:** Players can explore and investigate a fantasy setting.

### Milestone 4 --- NPC simulation

-   NPC definitions.
-   Personality.
-   Knowledge and beliefs.
-   Memory.
-   Relationships.
-   Scripted dialogue interaction.

**Deliverable:** NPCs react consistently to player behavior.

### Milestone 5 --- AI integration

-   Python backend.
-   LLM integration.
-   Context construction.
-   Structured responses.
-   Response validation.
-   Memory summarization.

**Deliverable:** NPCs generate contextual dialogue based on game
history.

### Milestone 6 --- Dynamic scenarios

-   Scenario definitions.
-   Hidden mysteries.
-   Dynamic events.
-   Conditional clues.
-   NPC behavior changes.
-   Scenario variations.

**Deliverable:** Player actions meaningfully change how the mystery
unfolds.

### Milestone 7 --- Polish and deployment

-   Reconnection support.
-   Persistent sessions.
-   Performance optimization.
-   AI usage limits.
-   Server deployment.
-   Playtesting and balancing.

**Deliverable:** A playable game ready for broader testing.

------------------------------------------------------------------------

## 21. First vertical slice

Build one small but complete session before expanding the content.

**Target: One complete Blackthorn Village session**

-   Five players can join a lobby.
-   Server assigns secret roles.
-   Players can visit five text-based locations.
-   Players can interact with four NPCs.
-   NPCs remember important previous conversations.
-   Players can investigate and discover clues.
-   One player secretly belongs to the cult.
-   Players can discuss and vote.
-   The game can determine a winner.

Success test:

> Two playthroughs should produce noticeably different conversations,
> discoveries, and NPC reactions because players made different
> decisions.

Build placeholder UI early so each system can be tested as it is
developed. Do not wait until all backend systems are complete before
making the game playable.

------------------------------------------------------------------------

## 22. Immediate implementation order

The recommended first coding sequence is:

1.  `GameState.gd` --- establish authoritative game data.
2.  `GamePhase.gd` --- implement the phase state machine.
3.  `NetworkManager.gd` --- connect multiple players.
4.  `RoleSystem.gd` --- assign secret roles.
5.  `ActionSystem.gd` --- handle action points and valid actions.
6.  `LocationManager.gd` --- implement text-based exploration.
7.  `EvidenceSystem.gd` --- track clues and visibility.
8.  `NPCState.gd` and `NPCMemory.gd` --- implement NPC state.
9.  `VotingSystem.gd` --- implement council voting.
10. `NarrativeManager.gd` --- connect the AI backend after the core loop
    works.

Keep the architecture modular, but do not create every planned file or
abstraction before it is needed.

------------------------------------------------------------------------

## 23. Open design questions

These decisions can be made during prototyping:

-   How many traitors should there be at different player counts?
-   Should players be eliminated, imprisoned, injured, or otherwise
    removed from active play after a vote?
-   Is the council vote mandatory every day?
-   Are action points spent simultaneously or one player at a time?
-   Can players visit the same location and investigate together?
-   Can players privately message one another at any time?
-   How long should a complete session last?
-   Should scenarios have a fixed hidden truth or support controlled
    random variation?
-   How should ties in voting be resolved?
-   Can NPCs be publicly accused and punished?

Avoid adding too many systems before the basic investigation-and-council
loop has been playtested.

------------------------------------------------------------------------

## 24. Guiding design principles

1.  **Investigation before accusation.** Give players meaningful ways to
    gather information before council.
2.  **Incomplete information.** No single clue or class should solve the
    entire mystery.
3.  **Different strengths.** Classes should provide complementary
    investigative abilities.
4.  **Hidden roles independent of classes.** Any class can belong to any
    faction.
5.  **Active traitors.** Traitors should have daytime objectives and
    meaningful decisions.
6.  **Persistent NPC state.** NPCs should remember important
    interactions and distinguish facts from beliefs.
7.  **Authoritative truth.** The server owns the mystery, evidence,
    roles, and outcomes.
8.  **AI as storyteller, not referee.** AI generates dialogue and
    descriptions; code enforces rules.
9.  **Information permissions.** Players and NPCs should only receive
    information they are allowed to know.
10. **Start small.** Prove that one text-based scenario is fun before
    expanding into maps, graphics, combat, or persistent campaigns.

The intended experience is not simply Werewolf with fantasy terminology.
It is a cooperative fantasy investigation where players gather,
interpret, share, conceal, and challenge information while hidden
traitors work toward their own objectives.
