extends "res://modes/GameMode.gd"
## Default mode. A storm has closed the roads and a group of travelers is
## stuck at the Wayward Lantern inn. Hidden among them are assassins with a
## contract on another guest. Nobody but the target is meant to die.


func _init() -> void:
	id = "assassins"
	display_name = "Assassins at the Wayward Lantern"
	description = "Storm-bound travelers share an inn with a hidden contract killer. Unmask the assassins before the contract is fulfilled."
	scenario_path = "res://data/scenarios/wayward_lantern.json"

	innocent_faction_label = "Travelers"
	traitor_faction_label = "Assassins"
	innocent_role_label = "Traveler"
	traitor_role_label = "Assassin"

	plot_label = "Contract"
	advance_action_label = "Advance the contract"
	sabotage_action_label = "Sabotage a traveler"
	effect_labels = {
		Enums.StatusEffect.WEARY: "Drugged",
		Enums.StatusEffect.MUDDLED: "Misled",
	}

	traitor_win_text = "The contract is fulfilled. The assassins slip away into the storm."
	innocent_win_text = "Every assassin has been unmasked. The contract dies with them."
