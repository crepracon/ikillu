extends RefCounted
## Turns game events and phases into readable lines for the chat log.
## Works from a player's view only, so it can never reveal more than that
## player is allowed to know. Returns plain text (the chat escapes it).


## A readable line for one event, or "" for events players don't need to see.
static func format_event(event: Dictionary, view: Dictionary) -> String:
	var data: Dictionary = event.get("data", {})
	var mode: Dictionary = view.get("mode", {})
	var plot: String = mode.get("plot", "Plot")
	var kind: String = event.get("type", "")

	if kind == "you_are_traitor":
		var allies := []
		for pid in data.get("allies", []):
			if pid != view.get("my_id", -1):
				allies.append(player_name(view, pid))
		var ally_text := " You work alone." if allies.is_empty() else " Your allies: %s." % ", ".join(allies)
		return "You are secretly %s. Your target is %s.%s Use /a message to talk privately with your allies." % [
			with_article(data.get("role", "a traitor")), data.get("target_name", "unknown"), ally_text]

	if kind == "day_started":
		return "Day %d dawns over %s." % [data.get("day", 0), view.get("setting", {}).get("name", "the inn")]

	if kind == "plot_advanced":
		return "Something stirred in the night. %s: %d/%d." % [
			plot, data.get("progress", 0), data.get("target", 0)]

	if kind == "sabotage":
		return "%s wakes up %s." % [player_name(view, data.get("target", -1)), str(data.get("effect", "")).to_lower()]

	if kind == "traitor_unmasked":
		return "The council unmasks %s. They were %s!" % [
			player_name(view, data.get("player", -1)), with_article(data.get("role", "a traitor"))]

	if kind == "wrong_accusation":
		return "The council accuses %s, but they're innocent. The %s advances: %d/%d." % [
			player_name(view, data.get("player", -1)), plot,
			data.get("plot_progress", 0), view.get("plot_target", 0)]

	if kind == "no_accusation":
		return "The council can't agree. Nobody is accused today."

	if kind == "game_over":
		return "%s win! %s" % [data.get("winner", "Someone"), data.get("reason", "")]

	return ""


## A short line announcing a phase, or "".
static func phase_text(phase: String) -> String:
	if phase == "MORNING":
		return "Morning. Everyone gathers in the common room."
	if phase == "INVESTIGATION":
		return "Investigation. Question the townsfolk with /ask name question. Each conversation costs 1 action point."
	if phase == "SOCIAL":
		return "Social. Compare notes, make alliances, whisper with /w."
	if phase == "COUNCIL":
		return "Council. Vote to accuse someone, or abstain. It takes a majority."
	if phase == "NIGHT":
		return "Night. The inn is asleep and chat is closed until morning."
	return ""


## Display name for a player id from the view's player list.
static func player_name(view: Dictionary, player_id) -> String:
	for p in view.get("players", []):
		if p.get("id") == player_id:
			return p.get("name", "?")
	return "someone"


## "Assassin" -> "an Assassin", "Cultist" -> "a Cultist".
static func with_article(word: String) -> String:
	if word == "":
		return word
	var first := word.substr(0, 1).to_lower()
	return ("an " if first in ["a", "e", "i", "o", "u"] else "a ") + word
