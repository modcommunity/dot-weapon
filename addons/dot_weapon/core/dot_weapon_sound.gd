class_name DotWeaponSound
extends RefCounted

## The family's stock weapon sounds, read by path from dot-audio's [code]stock/weapons/[/code]
## when a game links that addon, and null when it does not.
##
## [b]By path, not by [code]DotAudioStock[/code][/b], so no weapon pack gains a dependency on
## dot-audio: a pack falls back to its own stand-in (or silence) when [method pick] is null.
## Names are the files' (dot-audio docs/weapons.md): [code]light_fire[/code],
## [code]shotgun_far[/code], [code]reload_out[/code], [code]swing_heavy[/code] and so on.

const DIR := "res://addons/dot_audio/stock/weapons/"

## Sound classes of the packs -> the stock name of their report.
const FIRE := {
	&"light": &"light_fire", &"magnum": &"magnum_fire", &"smg": &"smg_fire", &"rifle": &"rifle_fire",
	&"heavy": &"heavy_fire", &"sniper": &"sniper_fire", &"shotgun": &"shotgun_fire",
	&"minigun": &"minigun_fire", &"launcher": &"launcher_fire", &"beam": &"beam_fire",
	&"charge": &"charge_fire", &"swing": &"swing", &"bash": &"bash", &"throw": &"throw",
	&"impact": &"impact", &"reload_out": &"reload_out", &"reload_in": &"reload_in",
}

## Variant counts found on disk, kept because probing is a file lookup per variant.
static var _counts: Dictionary = {}


## How many variant files [param sound] has (0: dot-audio is not linked or has no such sound).
static func count(sound: StringName) -> int:
	if _counts.has(sound):
		return _counts[sound]
	var n := 0
	while n < 16 and ResourceLoader.exists("%s%s_%d.ogg" % [DIR, sound, n]):
		n += 1
	_counts[sound] = n
	return n


## One variant of [param sound] chosen by [param roll] (any int; a presentation caller passes
## randi()), or null.
static func pick(sound: StringName, roll: int = 0) -> AudioStream:
	var n := count(sound)
	if n == 0:
		return null
	return load("%s%s_%d.ogg" % [DIR, sound, absi(roll) % n]) as AudioStream


## The report for a pack's sound class, or null.
static func pick_class(sound_class: StringName, roll: int = 0) -> AudioStream:
	return pick(FIRE.get(sound_class, &""), roll) if FIRE.has(sound_class) else null


## The same class heard from a distance (a different recording, more air), or null.
static func pick_far(sound_class: StringName, roll: int = 0) -> AudioStream:
	var fire := String(FIRE.get(sound_class, ""))
	return pick(StringName(fire.replace("_fire", "_far")), roll) if fire.ends_with("_fire") else null
