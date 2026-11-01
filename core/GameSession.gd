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

const Phase = GamePhaseScript.Phase
const Action = GamePhaseScript.Action
const CultAction = NightSystemScript.CultAction
const ABSTAIN = VotingSystemScript.ABSTAIN

signal phase_changed(old_phase: int, new_phase: int)
signal game_over(winner: int, reason: String)

var state
var phase
var voting
var night
var rng := RandomNumberGenerator.new()


## Pass a nonzero seed to make role assignment repeatable (useful for tests).
func _init(session_id := "", fixed_seed := 0) -> void:
	state = GameStateScript.new()
	phase = GamePhaseScript.new()
	voting = VotingSystemScript.new()
	night = NightSystemScript.new()

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
	if state.players.size() < Config.MIN_PLAYERS:
		return _err("Need at least %d players." % Config.MIN_PLAYERS)

	var cultists: Array = RoleSystem.assign_roles(state.players, rng)
	state.log_event("roles_assigned", {"cultists": cultists}, "server")
	for pid in cultists:
		state.log_event("you_are_cultist", {"allies": cultists}, [pid])

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
	if action == Action.VOTE or action == Action.CULT_ACTION:
		return _err("Use cast_vote() or submit_cult_action() for that.")
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
	if voter.exposed:
		return _err("Exposed cultists can't vote.")
	if target_id != ABSTAIN:
		if not state.players.has(target_id):
			return _err("Unknown target.")
		if target_id == voter_id:
			return _err("You can't accuse yourself.")
		if state.players[target_id].exposed:
			return _err("That player has already been exposed.")
	voting.cast(voter_id, target_id)
	return _ok()


func submit_cult_action(player_id: int, action: int, target_id := -1, effect := -1) -> Dictionary:
	var p = state.players.get(player_id)
	if p == null:
		return _err("Unknown player.")
	if not phase.is_allowed(Action.CULT_ACTION):
		return _err("Cult actions only happen at night.")
	if not p.is_active_cultist():
		return _err("Only active cultists can do that.")
	if action == CultAction.HEX:
		if not state.players.has(target_id):
			return _err("Unknown hex target.")
		if target_id == player_id:
			return _err("You can't hex yourself.")
		if effect < 0 or effect >= Enums.StatusEffect.size():
			return _err("Unknown effect.")
	elif action != CultAction.ADVANCE_RITUAL:
		return _err("Unknown cult action.")
	night.submit(player_id, action, target_id, effect)
	return _ok()


# --- Views -------------------------------------------------------------------

func get_public_state() -> Dictionary:
	var data: Dictionary = state.get_public_state()
	data["phase"] = GamePhaseScript.phase_name(phase.current)
	return data


func get_private_state(player_id: int) -> Dictionary:
	var data: Dictionary = state.get_private_state(player_id)
	data["phase"] = GamePhaseScript.phase_name(phase.current)
	return data


# --- Internals ---------------------------------------------------------------

func _begin_day() -> void:
	state.day += 1
	for p in state.players.values():
		p.start_new_day()
	state.log_event("day_started", {"day": state.day})


func _resolve_council() -> void:
	var eligible := 0
	for p in state.players.values():
		if not p.exposed:
			eligible += 1
	var result: Dictionary = voting.tally(eligible)
	var accused: int = result["accused"]

	if accused == VotingSystemScript.NO_ACCUSATION:
		state.log_event("no_accusation", {"counts": result["counts"]})
		return

	var target = state.players[accused]
	if target.role == Enums.Role.CULTIST:
		target.exposed = true
		state.log_event("cultist_exposed", {"player": accused, "counts": result["counts"]})
		if state.active_cultist_ids().is_empty():
			_end_game(Enums.Faction.VILLAGE, "Every cultist was exposed.")
	else:
		state.ritual_progress += Config.WRONG_ACCUSATION_RITUAL_BONUS
		state.log_event("wrong_accusation", {
			"player": accused,
			"counts": result["counts"],
			"ritual_progress": state.ritual_progress,
		})
		_check_ritual()


func _resolve_night() -> void:
	night.resolve(state)
	_check_ritual()


func _check_ritual() -> void:
	if state.ritual_progress >= Config.RITUAL_TARGET:
		_end_game(Enums.Faction.CULT, "The ritual was completed.")


func _end_game(winner: int, reason: String) -> void:
	state.winner = winner
	state.win_reason = reason
	state.log_event("game_over", {"winner": Enums.faction_name(winner), "reason": reason})
	phase.end_game()
	game_over.emit(winner, reason)


func _ok(data := {}) -> Dictionary:
	var result := {"ok": true}
	result.merge(data)
	return result


func _err(message: String) -> Dictionary:
	return {"ok": false, "error": message}
