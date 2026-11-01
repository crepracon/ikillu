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

var _passed := 0
var _failed := 0


func _init() -> void:
	_test_lobby_rules()
	_test_roles_are_deterministic()
	_test_cultist_count()
	_test_phase_action_rules()
	_test_village_wins_by_exposing_cultist()
	_test_cult_wins_by_ritual()
	_test_wrong_accusation_and_no_majority()
	_test_hex_weary_lasts_one_day()
	_test_private_state_hides_roles()

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


func _new_game(player_count := 5, fixed_seed := 12345):
	var s = GameSession.new("test", fixed_seed)
	for i in range(player_count):
		s.add_player(i + 1, "Player%d" % (i + 1), i % Enums.CharacterClass.size())
	s.start_game()
	return s


func _first_cultist(s) -> int:
	return s.state.cultist_ids()[0]


func _first_villager(s) -> int:
	for p in s.state.players.values():
		if p.role == Enums.Role.VILLAGER:
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

func _test_lobby_rules() -> void:
	print("Lobby rules")
	var s = GameSession.new("lobby", 1)
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
	_check(a.state.cultist_ids() == b.state.cultist_ids(), "same seed gives same cultists")


func _test_cultist_count() -> void:
	print("Cultist count")
	_check(_new_game(5).state.cultist_ids().size() == 1, "5 players -> 1 cultist")
	_check(_new_game(7).state.cultist_ids().size() == 2, "7 players -> 2 cultists")
	_check(_new_game(10).state.cultist_ids().size() == 3, "10 players -> 3 cultists")


func _test_phase_action_rules() -> void:
	print("Phase and action point rules")
	var s = _new_game()
	var v := _first_villager(s)
	var c := _first_cultist(s)

	_check(not s.perform_action(v, GamePhase.Action.INVESTIGATE)["ok"], "can't investigate in MORNING")
	_advance_to(s, GamePhase.Phase.INVESTIGATION)
	for i in range(Config.ACTION_POINTS_PER_DAY):
		s.perform_action(v, GamePhase.Action.INVESTIGATE, "church")
	_check(s.state.players[v].action_points == 0, "action points spent")
	_check(not s.perform_action(v, GamePhase.Action.INVESTIGATE)["ok"], "can't act with 0 action points")
	_check(s.perform_action(v, GamePhase.Action.PUBLIC_CHAT)["ok"], "chat is free")
	_check(not s.cast_vote(v, c)["ok"], "can't vote outside council")

	_advance_to(s, GamePhase.Phase.COUNCIL)
	_check(not s.cast_vote(v, v)["ok"], "can't accuse yourself")
	_check(s.cast_vote(v, VotingSystem.ABSTAIN)["ok"], "can abstain")

	_advance_to(s, GamePhase.Phase.NIGHT)
	_check(not s.submit_cult_action(v, NightSystem.CultAction.ADVANCE_RITUAL)["ok"], "villager can't take cult action")
	_check(not s.submit_cult_action(c, NightSystem.CultAction.HEX, c, Enums.StatusEffect.WEARY)["ok"], "cultist can't hex self")


func _test_village_wins_by_exposing_cultist() -> void:
	print("Village wins by exposing the cultist")
	var s = _new_game(5)
	var c := _first_cultist(s)
	_advance_to(s, GamePhase.Phase.COUNCIL)
	for pid in s.state.players.keys():
		if pid != c:
			s.cast_vote(pid, c)
	s.cast_vote(c, _first_villager(s))
	s.advance_phase()
	_check(s.phase.current == GamePhase.Phase.GAME_OVER, "game is over")
	_check(s.state.winner == Enums.Faction.VILLAGE, "village wins")
	_check(s.state.players[c].exposed, "cultist marked exposed")
	_check(not s.advance_phase()["ok"], "can't advance after game over")


func _test_cult_wins_by_ritual() -> void:
	print("Cult wins by completing the ritual")
	var s = _new_game(5)
	# Nobody votes, cult never submits, so the ritual advances by default each night.
	_advance_to(s, GamePhase.Phase.GAME_OVER)
	_check(s.state.winner == Enums.Faction.CULT, "cult wins")
	_check(s.state.ritual_progress == Config.RITUAL_TARGET, "ritual reached target")
	_check(s.state.day == Config.RITUAL_TARGET, "took %d days" % Config.RITUAL_TARGET)


func _test_wrong_accusation_and_no_majority() -> void:
	print("Wrong accusations and split votes")
	var s = _new_game(5)
	var c := _first_cultist(s)
	var innocent := _first_villager(s)

	_advance_to(s, GamePhase.Phase.COUNCIL)
	for pid in s.state.players.keys():
		if pid != innocent:
			s.cast_vote(pid, innocent)
	s.advance_phase()
	_check(s.state.ritual_progress == Config.WRONG_ACCUSATION_RITUAL_BONUS, "wrong accusation advances ritual")
	_check(not s.state.players[innocent].exposed, "innocent is not removed or exposed")
	_check(s.phase.current == GamePhase.Phase.NIGHT, "game continues to NIGHT")

	var before: int = s.state.ritual_progress
	_advance_to(s, GamePhase.Phase.COUNCIL) # night adds +1 by default
	var after_night: int = s.state.ritual_progress
	_check(after_night == before + Config.RITUAL_PER_ADVANCE, "night advanced ritual")
	# 2 votes out of 5 is not a majority.
	var others: Array = s.state.players.keys().filter(func(pid): return pid != c)
	s.cast_vote(others[0], c)
	s.cast_vote(others[1], c)
	s.advance_phase()
	_check(not s.state.players[c].exposed, "2/5 votes is not a majority")
	_check(s.state.ritual_progress == after_night, "no accusation means no ritual penalty")


func _test_hex_weary_lasts_one_day() -> void:
	print("Hex: WEARY costs one action point for one day")
	var s = _new_game(5)
	var c := _first_cultist(s)
	var victim := _first_villager(s)

	_advance_to(s, GamePhase.Phase.NIGHT)
	var r: Dictionary = s.submit_cult_action(c, NightSystem.CultAction.HEX, victim, Enums.StatusEffect.WEARY)
	_check(r["ok"], "cultist can hex a villager")
	var ritual_before: int = s.state.ritual_progress
	s.advance_phase() # resolve night -> MORNING day 2
	_check(s.state.ritual_progress == ritual_before, "hexing costs the cult its ritual advance")
	_check(s.state.players[victim].action_points == Config.ACTION_POINTS_PER_DAY - Config.WEARY_AP_PENALTY, "victim has reduced action points")
	_check(s.state.players[c].action_points == Config.ACTION_POINTS_PER_DAY, "others have full action points")
	_check("WEARY" in s.state.players[victim].to_public()["effects"], "hex is publicly visible")

	s.advance_phase() # leave day 2 MORNING first, or _advance_to stops immediately
	_advance_to(s, GamePhase.Phase.MORNING) # through council and night to day 3
	_check(s.state.day == 3, "now day 3")
	_check(s.state.players[victim].action_points == Config.ACTION_POINTS_PER_DAY, "WEARY wore off after one day")


func _test_private_state_hides_roles() -> void:
	print("Information hiding")
	var s = _new_game(7)
	var c := _first_cultist(s)
	var v := _first_villager(s)

	var public_text := JSON.stringify(s.get_public_state())
	_check(not public_text.contains("CULTIST"), "public state has no roles")

	var villager_view: Dictionary = s.get_private_state(v)
	_check(villager_view["me"]["role"] == "VILLAGER", "villager sees own role")
	_check(not villager_view.has("cult_allies"), "villager can't see cult allies")
	var leaked := false
	for e in villager_view["events"]:
		if e["type"] == "roles_assigned" or e["type"] == "you_are_cultist":
			leaked = true
	_check(not leaked, "villager can't see role events")

	var cult_view: Dictionary = s.get_private_state(c)
	_check(cult_view["me"]["role"] == "CULTIST", "cultist sees own role")
	_check(cult_view["cult_allies"].size() == 1, "cultist sees their ally (7 players)")
