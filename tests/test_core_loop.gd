extends SceneTree
## Headless tests for the core game loop. Run from the project folder:
##   godot --headless --script res://tests/test_core_loop.gd
## Exits with code 0 if everything passes, 1 otherwise.

const GameSession = preload("res://core/GameSession.gd")
const GamePhase = preload("res://core/GamePhase.gd")
const Enums = preload("res://core/Enums.gd")
const Config = preload("res://core/GameConfig.gd")
const NightSystem = preload("res://systems/NightSystem.gd")
const VotingSystem = preload("res://systems/VotingSystem.gd")
const ScenarioLoader = preload("res://scenarios/ScenarioLoader.gd")
const AssassinsMode = preload("res://modes/AssassinsMode.gd")
const CultistsMode = preload("res://modes/CultistsMode.gd")
const EventText = preload("res://game/EventText.gd")

var _passed := 0
var _failed := 0


func _init() -> void:
	_test_scenarios_load()
	_test_default_mode_is_assassins()
	_test_lobby_rules()
	_test_roles_are_deterministic()
	_test_traitor_count()
	_test_phase_action_rules()
	_test_innocents_win_by_unmasking()
	_test_traitors_win_by_plot()
	_test_cultists_mode_plays_too()
	_test_wrong_accusation_and_no_majority()
	_test_sabotage_weary_lasts_one_day()
	_test_private_state_hides_roles()
	_test_min_players_override()
	_test_council_and_night_views()
	_test_game_over_reveals_traitors()
	_test_event_text()

	print("\n%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


# --- Helpers -----------------------------------------------------------------

func _check(condition: bool, label: String) -> void:
	if condition:
		_passed += 1
		print("  PASS  " + label)
	else:
		_failed += 1
		print("  FAIL  " + label)


func _new_game(player_count := 5, fixed_seed := 12345, mode = null):
	var s = GameSession.new(mode, "test", fixed_seed)
	for i in range(player_count):
		s.add_player(i + 1, "Player%d" % (i + 1), i % Enums.CharacterClass.size())
	s.start_game()
	return s


func _first_traitor(s) -> int:
	return s.state.traitor_ids()[0]


func _first_innocent(s) -> int:
	for p in s.state.players.values():
		if not p.is_traitor():
			return p.id
	return -1


func _advance_to(s, target_phase: int) -> void:
	var guard := 0
	while s.phase.current != target_phase and s.phase.current != GamePhase.Phase.GAME_OVER:
		s.advance_phase()
		guard += 1
		if guard > 50:
			push_error("advance_to got stuck")
			return


# --- Tests -------------------------------------------------------------------

func _test_scenarios_load() -> void:
	print("Scenario data")
	for mode in [AssassinsMode.new(), CultistsMode.new()]:
		var scenario: Dictionary = ScenarioLoader.load_scenario(mode.scenario_path)
		_check(not scenario.is_empty(), "%s scenario loads" % mode.id)
		_check(ScenarioLoader.validate(scenario).is_empty(), "%s scenario references are valid" % mode.id)
	var inn: Dictionary = ScenarioLoader.load_scenario(AssassinsMode.new().scenario_path)
	_check(inn["target_npc"] == "duchess_isolde", "inn has an assassination target")
	_check(inn["npcs"].size() >= 8, "inn has a full NPC cast")


func _test_default_mode_is_assassins() -> void:
	print("Default mode")
	var s = _new_game()
	_check(s.state.mode.id == "assassins", "default mode is assassins")
	_check(s.get_public_state()["setting"]["name"] == "The Wayward Lantern", "setting comes from scenario")


func _test_lobby_rules() -> void:
	print("Lobby rules")
	var s = GameSession.new(null, "lobby", 1)
	s.add_player(1, "A", Enums.CharacterClass.MAGE)
	_check(not s.add_player(1, "A again", Enums.CharacterClass.MAGE)["ok"], "duplicate player rejected")
	_check(not s.add_player(2, "B", 99)["ok"], "bad class rejected")
	_check(not s.start_game()["ok"], "can't start below minimum players")
	for i in range(2, Config.MIN_PLAYERS + 1):
		s.add_player(i, "P%d" % i, Enums.CharacterClass.ROGUE)
	_check(s.start_game()["ok"], "starts at minimum players")
	_check(s.phase.current == GamePhase.Phase.MORNING, "game starts in MORNING")
	_check(s.state.day == 1, "game starts on day 1")
	_check(not s.add_player(50, "Late", Enums.CharacterClass.BARD)["ok"], "can't join after start")


func _test_roles_are_deterministic() -> void:
	print("Deterministic roles")
	var a = _new_game(6, 777)
	var b = _new_game(6, 777)
	_check(a.state.traitor_ids() == b.state.traitor_ids(), "same seed gives same traitors")


func _test_traitor_count() -> void:
	print("Traitor count")
	_check(_new_game(5).state.traitor_ids().size() == 1, "5 players -> 1 traitor")
	_check(_new_game(7).state.traitor_ids().size() == 2, "7 players -> 2 traitors")
	_check(_new_game(10).state.traitor_ids().size() == 3, "10 players -> 3 traitors")


func _test_phase_action_rules() -> void:
	print("Phase and action point rules")
	var s = _new_game()
	var v := _first_innocent(s)
	var t := _first_traitor(s)

	_check(not s.perform_action(v, GamePhase.Action.INVESTIGATE)["ok"], "can't investigate in MORNING")
	_advance_to(s, GamePhase.Phase.INVESTIGATION)
	for i in range(Config.ACTION_POINTS_PER_DAY):
		s.perform_action(v, GamePhase.Action.INVESTIGATE, "stables")
	_check(s.state.players[v].action_points == 0, "action points spent")
	_check(not s.perform_action(v, GamePhase.Action.INVESTIGATE)["ok"], "can't act with 0 action points")
	_check(s.perform_action(v, GamePhase.Action.PUBLIC_CHAT)["ok"], "chat is free")
	_check(not s.cast_vote(v, t)["ok"], "can't vote outside council")

	_advance_to(s, GamePhase.Phase.COUNCIL)
	_check(not s.cast_vote(v, v)["ok"], "can't accuse yourself")
	_check(s.cast_vote(v, VotingSystem.ABSTAIN)["ok"], "can abstain")

	_advance_to(s, GamePhase.Phase.NIGHT)
	_check(not s.submit_traitor_action(v, NightSystem.TraitorAction.ADVANCE_PLOT)["ok"], "innocent can't take traitor action")
	_check(not s.submit_traitor_action(t, NightSystem.TraitorAction.SABOTAGE, t, Enums.StatusEffect.WEARY)["ok"], "traitor can't sabotage self")


func _test_innocents_win_by_unmasking() -> void:
	print("Travelers win by unmasking the assassin")
	var s = _new_game(5)
	var t := _first_traitor(s)
	_advance_to(s, GamePhase.Phase.COUNCIL)
	for pid in s.state.players.keys():
		if pid != t:
			s.cast_vote(pid, t)
	s.cast_vote(t, _first_innocent(s))
	s.advance_phase()
	_check(s.phase.current == GamePhase.Phase.GAME_OVER, "game is over")
	_check(s.state.winner == Enums.Faction.INNOCENT, "innocents win")
	_check(s.get_public_state()["winner"] == "Travelers", "winner uses mode label")
	_check(s.state.players[t].unmasked, "assassin marked unmasked")
	_check(not s.advance_phase()["ok"], "can't advance after game over")


func _test_traitors_win_by_plot() -> void:
	print("Assassins win by fulfilling the contract")
	var s = _new_game(5)
	# Nobody votes, traitors never submit, so the plot advances by default each night.
	_advance_to(s, GamePhase.Phase.GAME_OVER)
	_check(s.state.winner == Enums.Faction.TRAITOR, "traitors win")
	_check(s.state.plot_progress == s.state.mode.plot_target, "plot reached target")
	_check(s.state.day == s.state.mode.plot_target, "took %d days" % s.state.mode.plot_target)
	_check(s.get_public_state()["winner"] == "Assassins", "winner uses mode label")


func _test_cultists_mode_plays_too() -> void:
	print("Cultists variant runs on the same engine")
	var s = _new_game(5, 12345, CultistsMode.new())
	_check(s.state.mode.id == "cultists", "cultists mode selected")
	_check(s.get_public_state()["setting"]["name"] == "Blackthorn Village", "cultists setting loaded")
	var t := _first_traitor(s)
	_check(s.get_private_state(t)["me"]["role"] == "Cultist", "traitor is labelled Cultist")
	_advance_to(s, GamePhase.Phase.GAME_OVER)
	_check(s.get_public_state()["winner"] == "Cult", "cult wins the ritual race")


func _test_wrong_accusation_and_no_majority() -> void:
	print("Wrong accusations and split votes")
	var s = _new_game(5)
	var t := _first_traitor(s)
	var innocent := _first_innocent(s)

	_advance_to(s, GamePhase.Phase.COUNCIL)
	for pid in s.state.players.keys():
		if pid != innocent:
			s.cast_vote(pid, innocent)
	s.advance_phase()
	_check(s.state.plot_progress == s.state.mode.wrong_accusation_bonus, "wrong accusation advances plot")
	_check(not s.state.players[innocent].unmasked, "innocent is not removed or unmasked")
	_check(s.phase.current == GamePhase.Phase.NIGHT, "game continues to NIGHT")

	var before: int = s.state.plot_progress
	_advance_to(s, GamePhase.Phase.COUNCIL) # night adds +1 by default
	var after_night: int = s.state.plot_progress
	_check(after_night == before + s.state.mode.plot_per_advance, "night advanced plot")
	# 2 votes out of 5 is not a majority.
	var others: Array = s.state.players.keys().filter(func(pid): return pid != t)
	s.cast_vote(others[0], t)
	s.cast_vote(others[1], t)
	s.advance_phase()
	_check(not s.state.players[t].unmasked, "2/5 votes is not a majority")
	_check(s.state.plot_progress == after_night, "no accusation means no plot penalty")


func _test_sabotage_weary_lasts_one_day() -> void:
	print("Sabotage: WEARY (Drugged) costs one action point for one day")
	var s = _new_game(5)
	var t := _first_traitor(s)
	var victim := _first_innocent(s)

	_advance_to(s, GamePhase.Phase.NIGHT)
	var r: Dictionary = s.submit_traitor_action(t, NightSystem.TraitorAction.SABOTAGE, victim, Enums.StatusEffect.WEARY)
	_check(r["ok"], "assassin can sabotage a traveler")
	var plot_before: int = s.state.plot_progress
	s.advance_phase() # resolve night -> MORNING day 2
	_check(s.state.plot_progress == plot_before, "sabotage costs the traitors their plot advance")
	_check(s.state.players[victim].action_points == Config.ACTION_POINTS_PER_DAY - Config.WEARY_AP_PENALTY, "victim has reduced action points")
	_check(s.state.players[t].action_points == Config.ACTION_POINTS_PER_DAY, "others have full action points")
	_check("Drugged" in s.state.players[victim].to_public(s.state.mode)["effects"], "sabotage is publicly visible with flavor name")

	s.advance_phase() # leave day 2 MORNING first, or _advance_to stops immediately
	_advance_to(s, GamePhase.Phase.MORNING) # through council and night to day 3
	_check(s.state.day == 3, "now day 3")
	_check(s.state.players[victim].action_points == Config.ACTION_POINTS_PER_DAY, "WEARY wore off after one day")


func _test_private_state_hides_roles() -> void:
	print("Information hiding")
	var s = _new_game(7)
	var t := _first_traitor(s)
	var v := _first_innocent(s)

	var public_text := JSON.stringify(s.get_public_state())
	_check(not public_text.contains("\"role\""), "public state has no roles")
	_check(not public_text.contains("duchess_isolde"), "public state doesn't name the target")

	var innocent_view: Dictionary = s.get_private_state(v)
	_check(innocent_view["me"]["role"] == "Traveler", "innocent sees own role")
	_check(not innocent_view.has("traitor_allies"), "innocent can't see traitor allies")
	_check(not innocent_view.has("plot_target_npc"), "innocent doesn't know the target")
	var leaked := false
	for e in innocent_view["events"]:
		if e["type"] == "roles_assigned" or e["type"] == "you_are_traitor":
			leaked = true
	_check(not leaked, "innocent can't see role events")

	var traitor_view: Dictionary = s.get_private_state(t)
	_check(traitor_view["me"]["role"] == "Assassin", "traitor sees own role")
	_check(traitor_view["traitor_allies"].size() == 1, "traitor sees their ally (7 players)")
	_check(traitor_view["plot_target_npc"] == "duchess_isolde", "traitor knows the target")


func _test_min_players_override() -> void:
	print("Min players override (test games)")
	var s = GameSession.new(null, "small", 5)
	s.min_players = 2
	s.add_player(1, "A", Enums.CharacterClass.MAGE)
	s.add_player(2, "B", Enums.CharacterClass.ROGUE)
	_check(s.start_game()["ok"], "2-player test game can start when min_players is lowered")
	_check(s.state.traitor_ids().size() == 1, "still exactly one traitor")


func _test_council_and_night_views() -> void:
	print("Council and night views")
	var s = _new_game(5)
	var t := _first_traitor(s)
	var v := _first_innocent(s)

	_advance_to(s, GamePhase.Phase.COUNCIL)
	_check(s.get_private_state(v)["my_vote"] == GameSession.NO_VOTE, "no vote yet")
	s.cast_vote(v, t)
	var view: Dictionary = s.get_private_state(v)
	_check(view["my_vote"] == t, "my_vote shows my choice")
	_check(view["votes_cast"] == 1, "vote count visible")
	_check(not s.get_private_state(t).has("my_vote") or s.get_private_state(t)["my_vote"] == GameSession.NO_VOTE, "others' votes stay hidden")
	_check(not JSON.stringify(s.get_public_state()).contains("my_vote"), "public view has no individual votes")

	_advance_to(s, GamePhase.Phase.NIGHT)
	s.submit_traitor_action(t, NightSystem.TraitorAction.SABOTAGE, v, Enums.StatusEffect.WEARY)
	_check(s.get_private_state(t).has("night_plan"), "traitor sees the night plan")
	_check(s.get_private_state(t)["night_plan"]["target"] == v, "night plan shows target")
	_check(not s.get_private_state(v).has("night_plan"), "innocent can't see the night plan")
	_check(s.get_private_state(t)["plot_target_name"] == "Duchess Isolde Marrow", "traitor sees target's name")


func _test_game_over_reveals_traitors() -> void:
	print("Game over reveals traitors")
	var s = _new_game(5)
	_check(not s.get_public_state().has("revealed_traitors"), "traitors hidden during the game")
	_advance_to(s, GamePhase.Phase.GAME_OVER)
	_check(s.get_public_state()["revealed_traitors"] == s.state.traitor_ids(), "traitors revealed at game over")


func _test_event_text() -> void:
	print("Event narration")
	var s = _new_game(5)
	var t := _first_traitor(s)
	var v := _first_innocent(s)

	var traitor_view: Dictionary = s.get_private_state(t)
	traitor_view["my_id"] = t
	var briefing := ""
	for e in traitor_view["events"]:
		if e["type"] == "you_are_traitor":
			briefing = EventText.format_event(e, traitor_view)
	_check(briefing.contains("an Assassin"), "briefing names the role with the right article")
	_check(briefing.contains("Duchess Isolde Marrow"), "briefing names the target")
	_check(briefing.contains("/a"), "briefing explains ally chat")

	var innocent_view: Dictionary = s.get_private_state(v)
	var lines := []
	for e in innocent_view["events"]:
		var line := EventText.format_event(e, innocent_view)
		if line != "":
			lines.append(line)
	_check(lines.size() == 1 and lines[0].begins_with("Day 1 dawns over The Wayward Lantern"), "innocent only sees the dawn, no secrets")

	_advance_to(s, GamePhase.Phase.NIGHT)
	s.submit_traitor_action(t, NightSystem.TraitorAction.SABOTAGE, v, Enums.StatusEffect.WEARY)
	s.advance_phase()
	var after: Dictionary = s.get_public_state()
	var sabotage_line := ""
	for e in s.state.events_visible_to(v):
		if e["type"] == "sabotage":
			sabotage_line = EventText.format_event(e, after)
	_check(sabotage_line.contains("wakes up drugged"), "sabotage is narrated with the flavor name")
	_check(EventText.phase_text("COUNCIL") != "", "phases have narration")
	_check(EventText.with_article("Cultist") == "a Cultist", "a/an for consonants")
