extends "res://modes/GameMode.gd"
## Variant mode from the original design doc: a hidden cult works to complete
## a forbidden ritual in Blackthorn Village.


func _init() -> void:
	id = "cultists"
	display_name = "The Curse of Blackthorn Village"
	description = "A hidden cult works toward a forbidden ritual. Expose the cultists before the last bell tolls."
	scenario_path = "res://data/scenarios/blackthorn_village.json"

	innocent_faction_label = "Villagers"
	traitor_faction_label = "Cult"
	innocent_role_label = "Investigator"
	traitor_role_label = "Cultist"

	plot_label = "Ritual"
	advance_action_label = "Advance the ritual"
	sabotage_action_label = "Hex an investigator"
	effect_labels = {
		Enums.StatusEffect.WEARY: "Cursed fatigue",
		Enums.StatusEffect.MUDDLED: "Clouded mind",
	}

	traitor_win_text = "The ritual is complete. Blackthorn falls under the curse."
	innocent_win_text = "Every cultist has been exposed. The ritual is broken."
