extends RefCounted
## The traitors' night action. The traitors act as a team and take ONE
## action per night, whichever any active traitor submitted last. If nobody
## submits, the plot advances by default.

const Enums = preload("res://core/Enums.gd")
const Config = preload("res://core/GameConfig.gd")

enum TraitorAction { ADVANCE_PLOT, SABOTAGE }

var pending := {}


func reset() -> void:
	pending = {}


func submit(traitor_id: int, action: int, target_id := -1, effect := -1) -> void:
	pending = {
		"by": traitor_id,
		"action": action,
		"target": target_id,
		"effect": effect,
	}


## Applies tonight's action to the state and returns a summary of what happened.
func resolve(state) -> Dictionary:
	var mode = state.mode
	var action: int = pending.get("action", TraitorAction.ADVANCE_PLOT)

	if action == TraitorAction.SABOTAGE:
		var target_id: int = pending["target"]
		var effect: int = pending["effect"]
		state.players[target_id].add_effect(effect, Config.SABOTAGE_DURATION_DAYS)
		state.log_event("sabotage", {
			"target": target_id,
			"effect": mode.effect_label(effect),
		}, "public")
		state.log_event("sabotage_done", {
			"by": pending["by"],
			"target": target_id,
			"effect": mode.effect_label(effect),
		}, state.traitor_ids())
		return {"action": "SABOTAGE", "target": target_id, "effect": effect}

	state.plot_progress += mode.plot_per_advance
	state.log_event("plot_advanced", {
		"plot": mode.plot_label,
		"progress": state.plot_progress,
		"target": mode.plot_target,
	}, "public" if mode.plot_progress_public else state.traitor_ids())
	return {"action": "ADVANCE_PLOT", "progress": state.plot_progress}
