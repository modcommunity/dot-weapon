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
	&"impact": &"impact", &"suppressed": &"suppressed_fire", &"dry": &"dry", &"equip": &"equip",
	&"casing": &"casing", &"reload_shell": &"reload_shell", &"reload_out": &"reload_out", &"reload_in": &"reload_in",
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


## Room reflections: indoors a shot is followed by the same class's distant recording, which
## carries more air than the close one; outdoors there is none. A game with its own tails
## assigns [member tail_picker] and gets asked instead.
const TAIL_DELAY := 0.06
const TAIL_GAIN_DB := -9.0

## Optional override, [code]func(sound_class: StringName, indoors: bool, roll: int) -> AudioStream[/code].
static var tail_picker: Callable = Callable()


## The reverberant tail to play [constant TAIL_DELAY] after a report, or null (outdoors, or no
## recording). [param indoors] comes from the game (dot-audio's [code]DotAmbienceRoof[/code]).
static func pick_tail(sound_class: StringName, indoors: bool, roll: int = 0) -> AudioStream:
	if tail_picker.is_valid():
		return tail_picker.call(sound_class, indoors, roll) as AudioStream
	return pick_far(sound_class, roll) if indoors else null


## Problems with the stock as a game would hear it, empty when sound. Every class in [constant FIRE]
## must resolve a stream that is not empty; with [param measure] and ffmpeg on the machine each
## variant's peak must also stay under -0.5 dBFS (not clipped) and over -40 (not silent). A game
## without dot-audio linked reports one problem and nothing else.
static func check_stock(measure: bool = true) -> PackedStringArray:
	var out := PackedStringArray()
	if count(&"light_fire") == 0:
		out.append("dot-audio stock weapons are not linked")
		return out
	var seen := {}
	for sound_class: StringName in FIRE:
		var sound: StringName = FIRE[sound_class]
		if seen.has(sound):
			continue
		seen[sound] = true
		var n := count(sound)
		if n == 0:
			out.append("%s (%s): no variants" % [sound_class, sound])
			continue
		for i in n:
			var path := "%s%s_%d.ogg" % [DIR, sound, i]
			var stream := load(path) as AudioStream
			if stream == null or stream.get_length() <= 0.02:
				out.append("%s: empty or unloadable" % path)
			elif measure:
				var peak := _peak_db(ProjectSettings.globalize_path(path))
				if peak > -0.5:
					out.append("%s: clipped (peak %.1f dBFS)" % [path, peak])
				elif peak < -40.0:
					out.append("%s: silent (peak %.1f dBFS)" % [path, peak])
	return out


## Peak in dBFS through ffmpeg's volumedetect, or -20 (a pass) when ffmpeg is not there.
static func _peak_db(file: String) -> float:
	var lines: Array = []
	var code := OS.execute("ffmpeg", ["-hide_banner", "-nostats", "-i", file, "-af", "volumedetect", "-f", "null", "-"], lines, true)
	if code != 0 or lines.is_empty():
		return -20.0
	var text := String(lines[0])
	var at := text.find("max_volume:")
	if at < 0:
		return -20.0
	return float(text.substr(at + 11).strip_edges().split(" ")[0])
