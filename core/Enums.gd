extends RefCounted
## Shared enums for the core game rules. These are mechanical and
## mode-agnostic: the active GameMode supplies the flavor names
## ("Assassin", "Cultist", "Contract", "Ritual"...).
## Scripts load this with preload() instead of class_name so the headless
## test runner works without an editor import step.

## INNOCENT: the majority trying to unmask the traitors.
## TRAITOR: the hidden minority racing to complete their plot.
enum Faction { INNOCENT, TRAITOR }

enum Role { INNOCENT, TRAITOR }

enum CharacterClass { PALADIN, ROGUE, MAGE, RANGER, BARD }

## Effects the traitors can inflict at night. Nobody is ever killed or
## removed; traitors slow players down or disrupt them instead.
## WEARY: -1 action point for the next day.
## MUDDLED: placeholder. The player's next investigation result comes back
## unreliable. Future investigation/card systems will read it.
enum StatusEffect { WEARY, MUDDLED }


static func faction_name(f: int) -> String:
	return Faction.keys()[f]


static func role_name(r: int) -> String:
	return Role.keys()[r]


static func class_label(c: int) -> String:
	return CharacterClass.keys()[c]


static func effect_name(e: int) -> String:
	return StatusEffect.keys()[e]
