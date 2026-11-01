extends RefCounted
## Authoritative per-player data. Lives only on the server.

const Enums = preload("res://core/Enums.gd")
const Config = preload("res://core/GameConfig.gd")

var id: int
var display_name: String
var character_class: int
var role: int = Enums.Role.INNOCENT
## True once the innocents have correctly unmasked this player as a traitor.
## Unmasked traitors stay in the game but lose their vote and night actions.
var unmasked := false
var action_points := 0
## StatusEffect -> days remaining.
var status_effects := {}


func _init(p_id: int, p_name: String, p_class: int) -> void:
	id = p_id
	display_name = p_name
	character_class = p_class


func faction() -> int:
	return Enums.Faction.TRAITOR if role == Enums.Role.TRAITOR else Enums.Faction.INNOCENT


func is_traitor() -> bool:
	return role == Enums.Role.TRAITOR


func is_active_traitor() -> bool:
	return is_traitor() and not unmasked


func has_effect(effect: int) -> bool:
	return status_effects.get(effect, 0) > 0


func add_effect(effect: int, days: int) -> void:
	status_effects[effect] = maxi(status_effects.get(effect, 0), days)


## Called at the start of each day.
func start_new_day() -> void:
	var ap := Config.ACTION_POINTS_PER_DAY
	if has_effect(Enums.StatusEffect.WEARY):
		ap -= Config.WEARY_AP_PENALTY
	action_points = maxi(ap, Config.MIN_ACTION_POINTS)


## Called when the day ends. Counts down effects and removes expired ones.
func end_day() -> void:
	for effect in status_effects.keys():
		status_effects[effect] -= 1
		if status_effects[effect] <= 0:
			status_effects.erase(effect)


## What every player is allowed to see about this player.
func to_public(mode) -> Dictionary:
	var effects := []
	for effect in status_effects.keys():
		effects.append(mode.effect_label(effect))
	return {
		"id": id,
		"name": display_name,
		"class": Enums.class_label(character_class),
		"unmasked": unmasked,
		"effects": effects,
	}


## What only this player is allowed to see about themselves.
func to_private(mode) -> Dictionary:
	var data := to_public(mode)
	data["role"] = mode.role_label(role)
	data["faction"] = mode.faction_label(faction())
	data["is_traitor"] = is_traitor()
	data["action_points"] = action_points
	return data
