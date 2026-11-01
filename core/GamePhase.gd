extends RefCounted
## Phase state machine. Owns the current phase and which actions each
## phase allows. It does not resolve anything; GameSession does that.

signal phase_changed(old_phase: int, new_phase: int)

enum Phase { LOBBY, MORNING, INVESTIGATION, SOCIAL, COUNCIL, NIGHT, GAME_OVER }

enum Action {
	MOVE,
	INVESTIGATE,
	TALK_TO_NPC,
	PUBLIC_CHAT,
	PRIVATE_CHAT,
	SHARE_EVIDENCE,
	VOTE,
	TRAITOR_ACTION,
}

## The day loop. NIGHT wraps back to MORNING.
const NEXT := {
	Phase.LOBBY: Phase.MORNING,
	Phase.MORNING: Phase.INVESTIGATION,
	Phase.INVESTIGATION: Phase.SOCIAL,
	Phase.SOCIAL: Phase.COUNCIL,
	Phase.COUNCIL: Phase.NIGHT,
	Phase.NIGHT: Phase.MORNING,
}

const ALLOWED := {
	Phase.LOBBY: [Action.PUBLIC_CHAT],
	Phase.MORNING: [Action.PUBLIC_CHAT, Action.PRIVATE_CHAT],
	Phase.INVESTIGATION: [
		Action.MOVE, Action.INVESTIGATE, Action.TALK_TO_NPC,
		Action.PUBLIC_CHAT, Action.PRIVATE_CHAT,
	],
	Phase.SOCIAL: [Action.PUBLIC_CHAT, Action.PRIVATE_CHAT, Action.SHARE_EVIDENCE],
	Phase.COUNCIL: [Action.PUBLIC_CHAT, Action.VOTE],
	Phase.NIGHT: [Action.TRAITOR_ACTION],
	Phase.GAME_OVER: [Action.PUBLIC_CHAT],
}

## Actions that cost action points.
const AP_COST := {
	Action.MOVE: 1,
	Action.INVESTIGATE: 1,
	Action.TALK_TO_NPC: 1,
}

var current: int = Phase.LOBBY


func advance() -> int:
	if current == Phase.GAME_OVER:
		return current
	_set_phase(NEXT[current])
	return current


func end_game() -> void:
	_set_phase(Phase.GAME_OVER)


func is_allowed(action: int) -> bool:
	return action in ALLOWED.get(current, [])


func ap_cost(action: int) -> int:
	return AP_COST.get(action, 0)


static func phase_name(p: int) -> String:
	return Phase.keys()[p]


static func action_name(a: int) -> String:
	return Action.keys()[a]


func _set_phase(new_phase: int) -> void:
	var old := current
	current = new_phase
	phase_changed.emit(old, new_phase)
