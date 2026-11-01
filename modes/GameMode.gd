extends RefCounted
## Base class for game modes. A mode decides who the hidden traitors are,
## what plot they're racing to finish, the flavor text for everything,
## and which scenario (setting, NPCs, locations) to load.
## The rules engine only ever sees the mechanical values; the strings are
## for UI and the narrative layer.

const Enums = preload("res://core/Enums.gd")

var id := ""
var display_name := ""
var description := ""

## Scenario data file (setting, NPC cast, locations).
var scenario_path := ""

# --- Faction and role labels -------------------------------------------------
var innocent_faction_label := ""
var traitor_faction_label := ""
var innocent_role_label := ""
var traitor_role_label := ""

# --- The plot (the traitors' win track) ---------------------------------------
## What the progress track is called, e.g. "Contract" or "Ritual".
var plot_label := ""
## Traitors win when progress reaches this. DEFAULT
var plot_target := 5
## Progress gained when traitors advance the plot at night. DEFAULT
var plot_per_advance := 1
## Progress gained when the innocents accuse an innocent player. DEFAULT
var wrong_accusation_bonus := 1
## Whether everyone can see plot progress. Visible progress creates urgency. DEFAULT
var plot_progress_public := true

# --- Night action flavor ---------------------------------------------------------
var advance_action_label := ""
var sabotage_action_label := ""
## StatusEffect -> flavor name shown to players.
var effect_labels := {}

# --- Endings ---------------------------------------------------------------------
var traitor_win_text := ""
var innocent_win_text := ""


func role_label(role: int) -> String:
	return traitor_role_label if role == Enums.Role.TRAITOR else innocent_role_label


func faction_label(faction: int) -> String:
	return traitor_faction_label if faction == Enums.Faction.TRAITOR else innocent_faction_label


func effect_label(effect: int) -> String:
	return effect_labels.get(effect, Enums.effect_name(effect))


## Labels and summary safe to show everyone. None of this reveals who is on
## which side.
func to_public() -> Dictionary:
	return {
		"id": id,
		"name": display_name,
		"description": description,
		"innocent_faction": innocent_faction_label,
		"traitor_faction": traitor_faction_label,
		"innocent_role": innocent_role_label,
		"traitor_role": traitor_role_label,
		"plot": plot_label,
		"advance_action": advance_action_label,
		"sabotage_action": sabotage_action_label,
		"effect_labels": effect_labels.duplicate(),
	}
