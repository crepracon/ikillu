extends RefCounted
## The cult's night action. The cult acts as a team and takes ONE action per
## night, whichever any active cultist submitted last. If nobody submits,
## the ritual advances by default.

const Enums = preload("res://core/Enums.gd")
const Config = preload("res://core/GameConfig.gd")

enum CultAction { ADVANCE_RITUAL, HEX }

var pending := {}


func reset() -> void:
	pending = {}


func submit(cultist_id: int, action: int, target_id := -1, effect := -1) -> void:
	pending = {
		"by": cultist_id,
		"action": action,
		"target": target_id,
		"effect": effect,
	}


## Applies tonight's action to the state and returns a summary of what happened.
func resolve(state) -> Dictionary:
	var action: int = pending.get("action", CultAction.ADVANCE_RITUAL)

	if action == CultAction.HEX:
		var target_id: int = pending["target"]
		var effect: int = pending["effect"]
		var target = state.players[target_id]
		target.add_effect(effect, Config.HEX_DURATION_DAYS)
		state.log_event("hex", {
			"target": target_id,
			"effect": Enums.effect_name(effect),
		}, "public")
		state.log_event("hex_cast", {
			"by": pending["by"],
			"target": target_id,
			"effect": Enums.effect_name(effect),
		}, state.cultist_ids())
		return {"action": "HEX", "target": target_id, "effect": effect}

	state.ritual_progress += Config.RITUAL_PER_ADVANCE
	state.log_event("ritual_advanced", {
		"progress": state.ritual_progress,
		"target": Config.RITUAL_TARGET,
	}, "public" if Config.RITUAL_PROGRESS_PUBLIC else state.cultist_ids())
	return {"action": "ADVANCE_RITUAL", "progress": state.ritual_progress}
