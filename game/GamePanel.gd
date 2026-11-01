extends PanelContainer
## Game status and controls, shown above the chat log. Rebuilt from the
## latest view every time the server sends one.

const EventText = preload("res://game/EventText.gd")
const NightSystem = preload("res://systems/NightSystem.gd")
const VotingSystem = preload("res://systems/VotingSystem.gd")
const Enums = preload("res://core/Enums.gd")

const NO_VOTE := -2
## OptionButton treats id -1 as "use the index", so Abstain gets id 0 in the
## dropdown (peer ids are never 0) and is translated back when voting.
const ABSTAIN_ITEM := 0

var _status: Label
var _role: Label
var _controls: HBoxContainer
var _leader_controls: HBoxContainer

## Remembered picks, so a refresh (e.g. someone else votes) doesn't reset them.
var _picked_vote := ABSTAIN_ITEM
var _picked_night_action := 0
var _picked_victim := -1
var _last_phase := ""


func _ready() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	add_child(box)

	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 16)
	box.add_child(_status)

	_role = Label.new()
	_role.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_role)

	_controls = HBoxContainer.new()
	_controls.add_theme_constant_override("separation", 8)
	box.add_child(_controls)

	_leader_controls = HBoxContainer.new()
	_leader_controls.add_theme_constant_override("separation", 8)
	box.add_child(_leader_controls)

	Game.state_changed.connect(_render)
	_render(Game.state)


func _render(view: Dictionary) -> void:
	_clear(_controls)
	_clear(_leader_controls)
	_status.text = ""
	_role.text = ""
	if view.is_empty():
		return

	var phase: String = view.get("phase", "")
	if phase != _last_phase:
		_last_phase = phase
		_picked_vote = ABSTAIN_ITEM
		_picked_night_action = 0
		_picked_victim = -1

	if view.get("in_game", false):
		_render_game(view)
	else:
		_render_lobby(view)


# --- Lobby -------------------------------------------------------------------------

func _render_lobby(view: Dictionary) -> void:
	var count: int = view.get("player_count", 0)
	var need: int = view.get("min_players", 0)
	_status.text = "Lobby  ·  %d in the room" % count

	if view.get("is_leader", false):
		_role.text = "You're the room leader. Start the game when everyone's here."
		var start := _button("Start game", func(): Game.request_start())
		if count < need:
			start.disabled = true
			start.text = "Start game (need %d players)" % need
		_controls.add_child(start)
	else:
		_role.text = "Waiting for %s to start the game." % view.get("leader_name", "the leader")


# --- In game -----------------------------------------------------------------------

func _render_game(view: Dictionary) -> void:
	var me: Dictionary = view.get("me", {})
	var mode: Dictionary = view.get("mode", {})
	var phase: String = view.get("phase", "")

	# Status line
	var parts := ["Day %d" % view.get("day", 0), phase.capitalize()]
	if view.has("plot_progress"):
		parts.append("%s %d/%d" % [mode.get("plot", "Plot"), view["plot_progress"], view.get("plot_target", 0)])
	if not me.is_empty():
		parts.append("%s, %d AP" % [String(me.get("class", "")).capitalize(), me.get("action_points", 0)])
		for effect in me.get("effects", []):
			parts.append(effect)
	_status.text = "  ·  ".join(parts)

	# Role line
	if me.is_empty():
		_role.text = "You're watching this game."
	elif me.get("is_traitor", false):
		var allies := []
		for pid in view.get("traitor_allies", []):
			allies.append(EventText.player_name(view, pid))
		_role.text = "You are %s. Target: %s. Allies: %s. Use /a to talk to them privately." % [
			EventText.with_article(me.get("role", "")),
			view.get("plot_target_name", "?"),
			"none" if allies.is_empty() else ", ".join(allies)]
		if me.get("unmasked", false):
			_role.text += " You've been unmasked, so you can't vote or act at night."
	else:
		_role.text = "You are %s. Unmask the %s before the %s is complete." % [
			EventText.with_article(me.get("role", "")),
			String(mode.get("traitor_faction", "traitors")).to_lower(),
			String(mode.get("plot", "plot")).to_lower()]

	# Phase controls
	if phase == "GAME_OVER":
		_render_game_over(view)
	elif phase == "COUNCIL" and not me.is_empty() and not me.get("unmasked", false):
		_render_vote(view)
	elif phase == "NIGHT":
		if me.get("is_traitor", false) and not me.get("unmasked", false):
			_render_night(view)
		else:
			_controls.add_child(_label("You're asleep. Let's hope you wake up well rested."))

	# Leader controls
	if view.get("is_leader", false):
		if phase == "GAME_OVER":
			_leader_controls.add_child(_button("Back to lobby", func(): Game.request_end()))
		else:
			_leader_controls.add_child(_button("Next phase  ▶", func(): Game.request_advance()))
			_leader_controls.add_child(_button("End game", func(): Game.request_end()))
	elif phase != "GAME_OVER":
		_leader_controls.add_child(_label("%s moves the game to the next phase." % view.get("leader_name", "The leader")))


func _render_vote(view: Dictionary) -> void:
	var my_id: int = view.get("my_id", -1)
	var pick := OptionButton.new()
	pick.add_item("Abstain", ABSTAIN_ITEM)
	var eligible := 0
	for p in view.get("players", []):
		if p.get("unmasked", false):
			continue
		eligible += 1
		if p.get("id") != my_id:
			pick.add_item(p.get("name", "?"), p.get("id"))
	var idx := pick.get_item_index(_picked_vote)
	if idx >= 0:
		pick.select(idx)
	pick.item_selected.connect(func(i): _picked_vote = pick.get_item_id(i))
	_controls.add_child(_label("Accuse:"))
	_controls.add_child(pick)

	_controls.add_child(_button("Vote", func():
		var choice := pick.get_selected_id()
		Game.request_vote(VotingSystem.ABSTAIN if choice == ABSTAIN_ITEM else choice)
	))

	var my_vote: int = view.get("my_vote", NO_VOTE)
	var vote_text := "You haven't voted."
	if my_vote == VotingSystem.ABSTAIN:
		vote_text = "You abstained."
	elif my_vote != NO_VOTE:
		vote_text = "You voted for %s." % EventText.player_name(view, my_vote)
	_controls.add_child(_label("%s  %d/%d votes in." % [vote_text, view.get("votes_cast", 0), eligible]))


func _render_night(view: Dictionary) -> void:
	var mode: Dictionary = view.get("mode", {})
	var my_id: int = view.get("my_id", -1)
	var allies: Array = view.get("traitor_allies", [])
	var effect_labels: Dictionary = mode.get("effect_labels", {})

	# Option 0 advances the plot; option 1 + n sabotages with StatusEffect n.
	var action_pick := OptionButton.new()
	action_pick.add_item(mode.get("advance_action", "Advance the plot"), 0)
	for effect in Enums.StatusEffect.values():
		action_pick.add_item("%s (%s)" % [
			mode.get("sabotage_action", "Sabotage"), effect_labels.get(effect, Enums.effect_name(effect))], effect + 1)
	action_pick.select(clampi(_picked_night_action, 0, action_pick.item_count - 1))

	var victim_pick := OptionButton.new()
	for p in view.get("players", []):
		var pid: int = p.get("id")
		if pid != my_id and not pid in allies:
			victim_pick.add_item(p.get("name", "?"), pid)
	var victim_idx := victim_pick.get_item_index(_picked_victim)
	if victim_idx >= 0:
		victim_pick.select(victim_idx)
	victim_pick.visible = _picked_night_action != 0

	action_pick.item_selected.connect(func(i):
		_picked_night_action = i
		victim_pick.visible = i != 0
	)
	victim_pick.item_selected.connect(func(i): _picked_victim = victim_pick.get_item_id(i))

	_controls.add_child(_label("Tonight:"))
	_controls.add_child(action_pick)
	_controls.add_child(victim_pick)
	_controls.add_child(_button("Confirm", func():
		var choice := action_pick.get_selected_id()
		if choice == 0:
			Game.request_traitor_action(NightSystem.TraitorAction.ADVANCE_PLOT, -1, -1)
		elif victim_pick.item_count > 0:
			Game.request_traitor_action(NightSystem.TraitorAction.SABOTAGE,
				victim_pick.get_selected_id(), choice - 1)
	))

	var plan: Dictionary = view.get("night_plan", {})
	var plan_text := "No plan yet. If nobody chooses, the %s advances." % String(mode.get("plot", "plot")).to_lower()
	if not plan.is_empty():
		var by := EventText.player_name(view, plan.get("by", -1))
		if plan.get("action", 0) == NightSystem.TraitorAction.SABOTAGE:
			plan_text = "Plan (set by %s): %s → %s." % [by,
				effect_labels.get(plan.get("effect", 0), "sabotage"),
				EventText.player_name(view, plan.get("target", -1))]
		else:
			plan_text = "Plan (set by %s): %s." % [by, mode.get("advance_action", "advance")]
	_controls.add_child(_label(plan_text))


func _render_game_over(view: Dictionary) -> void:
	var mode: Dictionary = view.get("mode", {})
	var names := []
	for pid in view.get("revealed_traitors", []):
		names.append(EventText.player_name(view, pid))
	_controls.add_child(_label("%s win!  The %s were: %s." % [
		view.get("winner", "?"),
		String(mode.get("traitor_faction", "traitors")).to_lower(),
		", ".join(names)]))


# --- Helpers -----------------------------------------------------------------------

func _button(text: String, on_pressed: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(on_pressed)
	return b


func _label(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
