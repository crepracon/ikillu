extends RefCounted
## Rule values for talking to NPCs: trust, memory, and conversation limits.
## Lines marked DEFAULT are prototype guesses waiting on playtesting.

# --- Trust -------------------------------------------------------------------
## Trust runs from MIN_TRUST (hostile) to MAX_TRUST (confidant). Every player
## starts at 0 with every NPC: a stranger.
const MIN_TRUST := -3
const MAX_TRUST := 3
## A player can raise one NPC's trust by at most this much per day, so a
## secret takes more than one sweet-talking visit to unlock. Losing trust has
## no daily limit. DEFAULT
const MAX_TRUST_GAIN_PER_DAY := 1

## How the AI may describe the way a player spoke to an NPC. The AI only
## labels the message; game code decides what the label does to trust.
const APPROACHES := ["neutral", "friendly", "flattery", "bribe", "rude", "accusation", "threat"]

## Trust change for each approach. Each NPC can override any of these in
## scenario data under "reactions". DEFAULT
const DEFAULT_REACTIONS := {
	"neutral": 0,
	"friendly": 1,
	"flattery": 0,
	"bribe": 0,
	"rude": -1,
	"accusation": -1,
	"threat": -2,
}

## Moods the AI can report. Descriptive only; the UI or future systems can
## read them, but nothing in the rules depends on them.
const EMOTIONS := ["neutral", "friendly", "amused", "nervous", "afraid", "suspicious", "annoyed", "angry", "sad"]

# --- Conversations -----------------------------------------------------------
## In a game, opening a conversation with an NPC costs TALK_TO_NPC's action
## points and allows this many messages with that NPC for the rest of the
## day. DEFAULT
const MESSAGES_PER_CONVERSATION := 4
## The chat room has no action points, so it caps how many NPC messages each
## player can send per server session instead. Keeps API costs bounded.
const SANDBOX_MESSAGE_LIMIT := 100

# --- Memory (kept small so prompts stay short and cheap) ---------------------
const MAX_MEMORIES_PER_PLAYER := 8
const MAX_HEARSAY := 6
## Lines of today's conversation the NPC can see (both sides).
const MAX_TRANSCRIPT_LINES := 8

# --- Length caps for text the AI returns (characters) ------------------------
const MAX_DIALOGUE_LENGTH := 500
const MAX_ACTION_LENGTH := 120
const MAX_MEMORY_LENGTH := 160
const MAX_RUMOR_LENGTH := 160


static func clamp_trust(value: int) -> int:
	return clampi(value, MIN_TRUST, MAX_TRUST)
