extends RefCounted
## The authoritative state for one game session. Never send this object to
## clients directly; use get_public_state() / get_private_state().

const Enums = preload("res://core/Enums.gd")
const Config = preload("res://core/GameConfig.gd")

const NO_WINNER := -1

var session_id := ""
var rng_seed := 0
var day := 0
## int player_id -> PlayerState
var players := {}
var ritual_progress := 0
var winner: int = NO_WINNER
var win_reason := ""
## Each entry: { day, type, visibility, data }.
## visibility is "public", "server", or an Array of player ids.
var event_log := []


func log_event(type: String, data: Dictionary, visibility = "public") -> void:
	event_log.append({
		"day": day,
		"type": type,
		"visibility": visibility,
		"data": data,
	})


func cultist_ids() -> Array:
	var ids := []
	for p in players.values():
		if p.role == Enums.Role.CULTIST:
			ids.append(p.id)
	return ids


func active_cultist_ids() -> Array:
	var ids := []
	for p in players.values():
		if p.is_active_cultist():
			ids.append(p.id)
	return ids


func is_over() -> bool:
	return winner != NO_WINNER


func events_visible_to(player_id: int) -> Array:
	var visible := []
	for e in event_log:
		var v = e["visibility"]
		if typeof(v) == TYPE_STRING and v == "public":
			visible.append(e)
		elif typeof(v) == TYPE_ARRAY and player_id in v:
			visible.append(e)
	return visible


func get_public_state() -> Dictionary:
	var public_players := []
	for p in players.values():
		public_players.append(p.to_public())
	var data := {
		"session_id": session_id,
		"day": day,
		"players": public_players,
		"winner": Enums.faction_name(winner) if is_over() else null,
		"win_reason": win_reason,
	}
	if Config.RITUAL_PROGRESS_PUBLIC:
		data["ritual_progress"] = ritual_progress
		data["ritual_target"] = Config.RITUAL_TARGET
	return data


func get_private_state(player_id: int) -> Dictionary:
	var data := get_public_state()
	if not players.has(player_id):
		return data
	var me = players[player_id]
	data["me"] = me.to_private()
	data["events"] = events_visible_to(player_id)
	if me.role == Enums.Role.CULTIST:
		data["cult_allies"] = cultist_ids().filter(func(pid): return pid != player_id)
		data["ritual_progress"] = ritual_progress
		data["ritual_target"] = Config.RITUAL_TARGET
	return data
