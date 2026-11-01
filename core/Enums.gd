extends RefCounted
## Shared enums for the core game rules.
## Scripts load this with preload() instead of class_name so the headless
## test runner works without an editor import step.

enum Faction { VILLAGE, CULT }

enum Role { VILLAGER, CULTIST }

enum CharacterClass { PALADIN, ROGUE, MAGE, RANGER, BARD }

## Effects the cult can inflict at night. Nobody is ever killed or removed;
## the cult slows players down or disrupts them instead.
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
