extends RefCounted
## Runs one game session: the single entry point clients (via the network
## layer, later) use to change game state. Every method validates its
## input and returns { "ok": true, ... } or { "ok": false, "error": "..." }.
## Nothing here trusts the caller.

const Enums = preload("res://core/Enums.gd")
const Config = preload("res://core/GameConfig.gd")
const GameStateScript = preload("res://core/GameState.gd")
const GamePhaseScript = preload("res://core/GamePhase.gd")
const PlayerStateScript = preload("res://core/PlayerState.gd")
const RoleSystem = preload("res://systems/RoleSystem.gd")
const VotingSystemScript = preload("res://systems/VotingSystem.gd")
const NightSystemScript = preload("res://systems/NightSystem.gd")
const ScenarioLoader = preload("res://scenarios/ScenarioLoader.gd")
const AssassinsMode = preload("res://modes/AssassinsMode.gd")
const NPCManagerScript = preload("res://npc/NPCManager.gd")

const Phase = GamePhaseScript.Phase
const Action = GamePhaseScript.Action
const TraitorAction = NightSystemScript.TraitorAction
const ABSTAIN = VotingSystemScript.ABSTAIN
## my_vote value in a player's view when they haven't voted yet.
const NO_VOTE := -2

## Public events NPCs gossip about, and how many they remember.
const TOWN_NEWS_TYPES := ["sabotage", "wrong_accusation", "traitor_unmasked"]
const TOWN_NEWS_LIMIT := 6

signal phase_changed(old_phase: int, new_phase: int)
signal game_over(winner: int, reason: String)

var state
var phase
var voting
var night
## The scenario's NPCs: what they know and think of each player.
var npcs
var rng := RandomNumberGenerator.new()
## Players needed to start. The network layer lowers this for test games.
var min_players := Config.MIN_PLAYERS


## mode: a GameMode instance. Defaults to Assassins at the Wayward Lantern.
## fixed_seed: nonzero makes role assignment repeatable (useful for tests).
func _init(mode = null, session_id := "", fixed_seed := 0) -> void:
	state = GameStateScript.new()
	phase = GamePhaseScript.new()
	voting = VotingSystemScript.new()
	night = NightSystemScript.new()

	state.mode = mode if mode != null else AssassinsMode.new()
	state.scenario = ScenarioLoader.load_scenario(state.mode.scenario_path)
	npcs = NPCManagerScript.new(state.scenario)

	if fixed_seed == 0:
		rng.randomize()
	else:
		rng.seed = fixed_seed
	state.session_id = session_id
	state.rng_seed = rng.seed
	phase.phase_changed.connect(func(o, n): phase_changed.emit(o, n))


# --- Lobby -------------------------------------------------------------------

func add_player(player_id: int, display_name: String, character_class: int) -> Dictionary:
	if phase.current != Phase.LOBBY:
		return _err("Players can only join in the lobby.")
	if state.players.has(player_id):
		return _err("Player %d is already in the game." % player_id)
	if state.players.size() >= Config.MAX_PLAYERS:
		return _err("The game is full.")
	if character_class < 0 or character_class >= Enums.CharacterClass.size():
		return _err("Unknown class.")
	state.players[player_id] = PlayerStateScript.new(player_id, display_name, character_class)
	state.log_event("player_joined", {"id": player_id, "name": display_name})
	return _ok()


func start_game() -> Dictionary:
	if phase.current != Phase.LOBBY:
		return _err("The game has already started.")
	if state.players.size() < min_players:
		return _err("Need at least %d players." % min_players)

	var traitors: Array = RoleSystem.assign_roles(state.players, rng)
	var target_npc: String = state.scenario.get("target_npc", "")
	state.log_event("roles_assigned", {"traitors": traitors}, "server")
	for pid in traitors:
		state.log_event("you_are_traitor", {
			"role": state.mode.traitor_role_label,
			"allies": traitors,
			"target_npc": target_npc,
			"target_name": state.npc_name(target_npc),
		}, [pid])

	phase.advance() # LOBBY -> MORNING
	_begin_day()
	return _ok()


# --- Phase flow --------------------------------------------------------------

## Moves to the next phase, resolving whatever the current phase needs first.
## Timers or "everyone ready" logic can call this later; for now it's manual.
func advance_phase() -> Dictionary:
	var current: int = phase.current
	if current == Phase.LOBBY:
		return _err("Use start_game() to leave the lobby.")
	if current == Phase.GAME_OVER:
		return _err("The game is over.")

	if current == Phase.SOCIAL:
		voting.reset()
		phase.advance()
	elif current == Phase.COUNCIL:
		_resolve_council()
		if state.is_over():
			return _ok({"game_over": true})
		for p in state.players.values():
			p.end_day()
		night.reset()
		phase.advance()
	elif current == Phase.NIGHT:
		_resolve_night()
		if state.is_over():
			return _ok({"game_over": true})
		phase.advance()
		_begin_day()
	else:
		phase.advance()
	return _ok({"phase": GamePhaseScript.phase_name(phase.current)})


# --- Player actions ----------------------------------------------------------

## Generic daytime action. Checks phase and action points, then spends them.
## Investigation/NPC systems will hook in here later to produce results.
func perform_action(player_id: int, action: int, target := "") -> Dictionary:
	var p = state.players.get(player_id)
	if p == null:
		return _err("Unknown player.")
	if action == Action.VOTE or action == Action.TRAITOR_ACTION:
		return _err("Use cast_vote() or submit_traitor_action() for that.")
	if not phase.is_allowed(action):
		return _err("%s isn't allowed during %s." % [
			GamePhaseScript.action_name(action), GamePhaseScript.phase_name(phase.current)])
	var cost: int = phase.ap_cost(action)
	if p.action_points < cost:
		return _err("Not enough action points.")
	p.action_points -= cost
	state.log_event("action", {
		"player": player_id,
		"action": GamePhaseScript.action_name(action),
		"target": target,
	}, "server")
	return _ok({"action_points_left": p.action_points})


func cast_vote(voter_id: int, target_id: int) -> Dictionary:
	var voter = state.players.get(voter_id)
	if voter == null:
		return _err("Unknown player.")
	if not phase.is_allowed(Action.VOTE):
		return _err("Voting only happens at council.")
	if voter.unmasked:
		return _err("Unmasked %s can't vote." % state.mode.traitor_faction_label.to_lower())
	if target_id != ABSTAIN:
		if not state.players.has(target_id):
			return _err("Unknown target.")
		if target_id == voter_id:
			return _err("You can't accuse yourself.")
		if state.players[target_id].unmasked:
			return _err("That player has already been unmasked.")
	voting.cast(voter_id, target_id)
	return _ok()


func submit_traitor_action(player_id: int, action: int, target_id := -1, effect := -1) -> Dictionary:
	var p = state.players.get(player_id)
	if p == null:
		return _err("Unknown player.")
	if not phase.is_allowed(Action.TRAITOR_ACTION):
		return _err("That can only be done at night.")
	if not p.is_active_traitor():
		return _err("Only active %s can do that." % state.mode.traitor_faction_label.to_lower())
	if action == TraitorAction.SABOTAGE:
		if not state.players.has(target_id):
			return _err("Unknown sabotage target.")
		if target_id == player_id:
			return _err("You can't sabotage yourself.")
		if effect < 0 or effect >= Enums.StatusEffect.size():
			return _err("Unknown effect.")
	elif action != TraitorAction.ADVANCE_PLOT:
		return _err("Unknown action.")
	night.submit(player_id, action, target_id, effect)
	return _ok()


# --- Talking to NPCs ---------------------------------------------------------
# The flow for one message (the network layer does the async AI call between
# steps 2 and 3):
#   1. request_npc_message()   checks the rules and spends action points
#   2. npc_dialogue_context()  gathers what the AI may know
#   3. record_npc_reply()      applies the validated reply by the rules

## Checks whether a player may send an NPC a message right now. The first
## message to an NPC each day opens a conversation, which costs TALK_TO_NPC's
## action points and allows NPCConfig.MESSAGES_PER_CONVERSATION messages.
## When movement exists, this should also require being at the NPC's location.
func request_npc_message(player_id: int, npc_id: String) -> Dictionary:
	if not state.players.has(player_id):
		return _err("Unknown player.")
	if not npcs.has_npc(npc_id):
		return _err("Nobody by that name is here.")
	if not phase.is_allowed(Action.TALK_TO_NPC):
		return _err("The townsfolk can only be questioned during the investigation phase.")
	var key := str(player_id)
	var opened := false
	if not npcs.has_open_conversation(key, npc_id):
		var spent: Dictionary = perform_action(player_id, Action.TALK_TO_NPC, npc_id)
		if not spent["ok"]:
			return spent
		npcs.open_conversation(key, npc_id)
		opened = true
	var left: int = npcs.use_message(key, npc_id)
	return _ok({"opened": opened, "messages_left": left, "action_points_left": state.players[player_id].action_points})


## Everything the AI may know for this NPC's reply to this player. Built only
## from public state plus the NPC's own knowledge, so no reply can reveal a
## role, a night action, or the traitors' target.
func npc_dialogue_context(player_id: int, npc_id: String) -> Dictionary:
	var p = state.players.get(player_id)
	if p == null or not npcs.has_npc(npc_id):
		return {}
	var pub: Dictionary = p.to_public(state.mode)
	var player := {
		"name": pub["name"],
		"class": String(pub["class"]).capitalize(),
		"effects": pub["effects"],
		"unmasked": pub["unmasked"],
		"unmasked_as": state.mode.traitor_faction_label if pub["unmasked"] else "",
	}
	var tension := -1.0
	if state.mode.plot_progress_public and state.mode.plot_target > 0:
		tension = clampf(float(state.plot_progress) / state.mode.plot_target, 0.0, 1.0)
	var town := {
		"day": state.day,
		"tension": tension,
		"news": _town_news(),
		"innocent_label": state.mode.innocent_faction_label,
		"traitor_label": state.mode.traitor_faction_label,
	}
	return npcs.dialogue_context(npc_id, str(player_id), player, town)


## Applies a validated reply (see narrative/NarrativeResponse.gd): the NPC
## remembers the exchange, and trust changes by the rules. The conversation
## goes in the event log for that player only.
func record_npc_reply(player_id: int, npc_id: String, player_text: String, reply: Dictionary) -> Dictionary:
	var p = state.players.get(player_id)
	if p == null or not npcs.has_npc(npc_id):
		return _err("Unknown player or NPC.")
	var result: Dictionary = npcs.apply_reply(npc_id, str(player_id), p.display_name, player_text, reply)
	state.log_event("npc_conversation", {
		"npc": npc_id,
		"player": player_id,
		"said": player_text,
		"action": reply.get("action", ""),
		"reply": reply.get("dialogue", ""),
	}, [player_id])
	state.log_event("npc_trust", {
		"npc": npc_id,
		"player": player_id,
		"approach": reply.get("approach", "neutral"),
		"change": result["trust_change"],
		"trust": result["trust"],
	}, "server")
	return _ok(result)


# --- Views -------------------------------------------------------------------

func get_public_state() -> Dictionary:
	var data: Dictionary = state.get_public_state()
	data["phase"] = GamePhaseScript.phase_name(phase.current)
	if phase.current == Phase.COUNCIL:
		# How many have voted, but never who voted for whom.
		data["votes_cast"] = voting.votes.size()
	return data


func get_private_state(player_id: int) -> Dictionary:
	var data: Dictionary = state.get_private_state(player_id)
	data["phase"] = GamePhaseScript.phase_name(phase.current)
	if phase.current == Phase.COUNCIL:
		data["votes_cast"] = voting.votes.size()
		data["my_vote"] = voting.votes.get(player_id, NO_VOTE)
	var me = state.players.get(player_id)
	if phase.current == Phase.NIGHT and me != null and me.is_traitor():
		# Traitors see tonight's plan so allies can coordinate.
		data["night_plan"] = night.pending.duplicate()
	return data


# --- Internals ---------------------------------------------------------------

func _begin_day() -> void:
	state.day += 1
	for p in state.players.values():
		p.start_new_day()
	npcs.start_day(state.day)
	state.log_event("day_started", {"day": state.day})


## Public events the townsfolk would have heard about, newest last.
## Only "public" entries from the event log; nothing private can leak in.
func _town_news() -> Array:
	var news := []
	for e in state.event_log:
		var v = e["visibility"]
		if typeof(v) != TYPE_STRING or v != "public" or not e["type"] in TOWN_NEWS_TYPES:
			continue
		var who_id = e["data"].get("target", e["data"].get("player", -1))
		var who = state.players.get(who_id)
		news.append({
			"day": e["day"],
			"type": e["type"],
			"player": who.display_name if who != null else "someone",
			"effect": e["data"].get("effect", ""),
		})
	return news.slice(maxi(news.size() - TOWN_NEWS_LIMIT, 0))


func _resolve_council() -> void:
	var eligible := 0
	for p in state.players.values():
		if not p.unmasked:
			eligible += 1
	var result: Dictionary = voting.tally(eligible)
	var accused: int = result["accused"]

	if accused == VotingSystemScript.NO_ACCUSATION:
		state.log_event("no_accusation", {"counts": result["counts"]})
		return

	var target = state.players[accused]
	if target.is_traitor():
		target.unmasked = true
		state.log_event("traitor_unmasked", {
			"player": accused,
			"role": state.mode.traitor_role_label,
			"counts": result["counts"],
		})
		if state.active_traitor_ids().is_empty():
			_end_game(Enums.Faction.INNOCENT, state.mode.innocent_win_text)
	else:
		state.plot_progress += state.mode.wrong_accusation_bonus
		state.log_event("wrong_accusation", {
			"player": accused,
			"counts": result["counts"],
			"plot_progress": state.plot_progress,
		})
		_check_plot()


func _resolve_night() -> void:
	night.resolve(state)
	_check_plot()


func _check_plot() -> void:
	if state.plot_progress >= state.mode.plot_target:
		_end_game(Enums.Faction.TRAITOR, state.mode.traitor_win_text)


func _end_game(winner: int, reason: String) -> void:
	state.winner = winner
	state.win_reason = reason
	state.log_event("game_over", {"winner": state.mode.faction_label(winner), "reason": reason})
	phase.end_game()
	game_over.emit(winner, reason)


func _ok(data := {}) -> Dictionary:
	var result := {"ok": true}
	result.merge(data)
	return result


func _err(message: String) -> Dictionary:
	return {"ok": false, "error": message}
