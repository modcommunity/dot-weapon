class_name DotWeaponAccuracyClass
extends RefCounted

## Per-class defaults for the accuracy and recoil fields of [DotWeaponBallistics] left at -1, so every
## weapon has a distinct feel without a profile naming each number. A weapon's own value always wins.

## Durations here are seconds (converted at the running tick rate); multipliers are plain factors.
## spread_hip is degrees added at the hip; spread_flinch degrees added by a hit, shed over [constant FLINCH_SEC].
const PRESETS := {
	"": {
		"spread_aim": 1.0, "spread_hip": 0.0, "spread_sprint": 1.0, "spread_slide": 1.0, "settle": 0.0,
		"spread_flinch": 0.0, "bloom_delay": 0.05, "bloom_crouch": 1.0,
		"recoil_aim": 1.0, "recoil_crouch": 1.0, "recoil_move": 1.0,
	},
	"rifle": {
		"spread_aim": 0.6, "spread_hip": 0.0, "spread_sprint": 1.3, "spread_slide": 1.3, "settle": 0.25,
		"spread_flinch": 0.8, "bloom_delay": 0.12, "bloom_crouch": 0.7,
		"recoil_aim": 0.75, "recoil_crouch": 0.8, "recoil_move": 1.15,
	},
	"smg": {
		"spread_aim": 0.7, "spread_hip": 0.0, "spread_sprint": 1.15, "spread_slide": 1.15, "settle": 0.15,
		"spread_flinch": 0.6, "bloom_delay": 0.1, "bloom_crouch": 0.8,
		"recoil_aim": 0.8, "recoil_crouch": 0.85, "recoil_move": 1.1,
	},
	"lmg": {
		"spread_aim": 0.55, "spread_hip": 0.6, "spread_sprint": 1.6, "spread_slide": 1.6, "settle": 0.5,
		"spread_flinch": 1.0, "bloom_delay": 0.25, "bloom_crouch": 0.45,
		"recoil_aim": 0.7, "recoil_crouch": 0.55, "recoil_move": 1.4,
	},
	"sniper": {
		"spread_aim": 0.0, "spread_hip": 2.5, "spread_sprint": 2.0, "spread_slide": 2.0, "settle": 0.45,
		"spread_flinch": 2.0, "bloom_delay": 0.2, "bloom_crouch": 0.7,
		"recoil_aim": 0.8, "recoil_crouch": 0.8, "recoil_move": 1.3,
	},
	"shotgun": {
		"spread_aim": 0.85, "spread_hip": 0.0, "spread_sprint": 1.1, "spread_slide": 1.1, "settle": 0.1,
		"spread_flinch": 0.5, "bloom_delay": 0.15, "bloom_crouch": 1.0,
		"recoil_aim": 0.9, "recoil_crouch": 0.9, "recoil_move": 1.0,
	},
	"pistol": {
		"spread_aim": 0.75, "spread_hip": 0.0, "spread_sprint": 1.1, "spread_slide": 1.2, "settle": 0.12,
		"spread_flinch": 0.6, "bloom_delay": 0.1, "bloom_crouch": 0.8,
		"recoil_aim": 0.85, "recoil_crouch": 0.9, "recoil_move": 1.1,
	},
}

const FLINCH_SEC := 0.4

## Tag to class, checked before the id.
const TAGS := {
	&"sniper": "sniper", &"scoped": "sniper", &"lmg": "lmg", &"smg": "smg", &"shotgun": "shotgun",
	&"pistol": "pistol", &"sidearm": "pistol", &"secondary": "pistol", &"rifle": "rifle", &"ar": "rifle",
}

## Words in a weapon id, in priority order ("machine_pistol" is an smg before it is a pistol).
const WORDS := [
	["sniper", "sniper"], ["marksman", "sniper"], ["lmg", "lmg"], ["minigun", "lmg"], ["machine_gun", "lmg"],
	["machine_pistol", "smg"], ["smg", "smg"], ["shotgun", "shotgun"], ["pistol", "pistol"],
	["revolver", "pistol"], ["derringer", "pistol"], ["rifle", "rifle"], ["carbine", "rifle"], ["bullpup", "rifle"],
]


## The class of a weapon: [param explicit] when set (an unknown name, such as "none", is the neutral row),
## else its tags, else words in its id, else "".
static func resolve(explicit: String, tags: Array, id: StringName) -> String:
	if explicit != "":
		return explicit if PRESETS.has(explicit) else ""
	for tag: Variant in tags:
		var key := StringName(str(tag))
		if TAGS.has(key):
			return String(TAGS[key])
	var text := String(id).to_lower()
	for pair: Array in WORDS:
		if text.contains(String(pair[0])):
			return String(pair[1])
	return ""


## The preset [param key] for [param klass] (the neutral row for an unknown class).
static func preset(klass: String, key: String) -> float:
	var row: Dictionary = PRESETS.get(klass, PRESETS[""])
	return float(row.get(key, (PRESETS[""] as Dictionary).get(key, 0.0)))
