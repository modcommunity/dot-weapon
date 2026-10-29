class_name DotWeaponSound
extends RefCounted

## The family's stock weapon sounds, read by path from dot-audio's [code]stock/weapons/[/code], null when not linked.
## By path, not by [code]DotAudioStock[/code], so no pack gains a dependency on dot-audio; a pack falls back to its own
## stand-in when [method pick] is null. Names are the files' (dot-audio docs/weapons.md).

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

## Sound class -> the class whose reload files it uses (a silenced pistol reloads like a pistol).
const RELOAD_CLASS := {
	&"light": &"light", &"suppressed": &"light", &"magnum": &"magnum", &"smg": &"smg", &"rifle": &"rifle",
	&"heavy": &"heavy", &"sniper": &"sniper",
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


## The stock name of [param stage] (&"out" or &"in") of [param sound_class]'s reload: the class's own set, else the generic
## `reload_out`/`reload_in`, else &"reload_shell" for a shotgun (a tube is loaded round by round).
static func reload_name(sound_class: StringName, stage: StringName) -> StringName:
	if sound_class == &"shotgun":
		return &"reload_shell"
	var own := StringName("reload_%s_%s" % [stage, RELOAD_CLASS.get(sound_class, &"")])
	return own if RELOAD_CLASS.has(sound_class) and count(own) > 0 else StringName("reload_" + String(stage))


## One variant of [param sound_class]'s reload [param stage], or null when dot-audio is not linked.
static func pick_reload(sound_class: StringName, stage: StringName = &"out", roll: int = 0) -> AudioStream:
	return pick(reload_name(sound_class, stage), roll)


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


## Problems with the stock as a game would hear it, empty when sound: every [constant FIRE] class must resolve
## a stream, and with [param measure] and ffmpeg each variant's peak stays within -40..-0.5 dBFS.
## A game without dot-audio linked reports one problem.
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


## Length bounds in seconds of every fire variant per class: a rifle report under 0.15 s is a click, over 1.5 s a tail that stacks.
const BOUNDS := {
	&"light": Vector2(0.3, 1.2), &"magnum": Vector2(0.5, 1.5), &"smg": Vector2(0.15, 0.6), &"rifle": Vector2(0.15, 1.5),
	&"heavy": Vector2(0.15, 1.5), &"sniper": Vector2(0.8, 2.5), &"shotgun": Vector2(0.6, 1.6),
	&"minigun": Vector2(0.08, 0.4), &"launcher": Vector2(0.25, 1.2), &"beam": Vector2(0.15, 0.6),
	&"charge": Vector2(0.25, 0.8), &"suppressed": Vector2(0.1, 0.5), &"swing": Vector2(0.2, 1.0),
	&"bash": Vector2(0.15, 0.5), &"throw": Vector2(0.3, 1.0),
}

## Classes that are reloaded (the rest are melee, thrown or energy).
const RELOADED := [&"light", &"magnum", &"smg", &"rifle", &"heavy", &"sniper", &"shotgun", &"suppressed"]


## Problems with a pack's weapon -> sound class map ([param classes], id -> class): each id's class must be known, have fire
## variants inside [constant BOUNDS], and a gun class needs a reload and a dry click. Empty when sound or dot-audio is not linked.
static func check_classes(classes: Dictionary) -> PackedStringArray:
	var out := PackedStringArray()
	if count(&"light_fire") == 0:
		return out
	var bad := {}
	for id: StringName in classes:
		var sound_class: StringName = classes[id]
		if not FIRE.has(sound_class):
			out.append("%s: unknown sound class %s" % [id, sound_class])
			continue
		if bad.has(sound_class):
			continue
		var sound: StringName = FIRE[sound_class]
		if count(sound) == 0:
			bad[sound_class] = true
			out.append("%s: class %s has no fire files" % [id, sound_class])
			continue
		if BOUNDS.has(sound_class):
			for i in count(sound):
				var len_s := ((load("%s%s_%d.ogg" % [DIR, sound, i]) as AudioStream).get_length())
				var b: Vector2 = BOUNDS[sound_class]
				if len_s < b.x or len_s > b.y:
					bad[sound_class] = true
					out.append("%s: %s_%d is %.2f s, outside %s %.2f-%.2f" % [id, sound, i, len_s, sound_class, b.x, b.y])
		if sound_class in RELOADED:
			var reload := reload_name(sound_class, &"out")
			if count(reload) == 0 or count(reload_name(sound_class, &"in")) == 0 or count(&"dry") == 0:
				bad[sound_class] = true
				out.append("%s: class %s has no %s or dry sound" % [id, sound_class, reload])
	return out


## Problems of the stock as a whole: two different classes (or a fire and a far recording) sharing one file's bytes, and
## two classes' reload sets sharing one (the generic reload_out/in are a fallback and may overlap).
static func check_unique() -> PackedStringArray:
	var out := PackedStringArray()
	var owner := {}
	for rc: StringName in RELOAD_CLASS.values():
		for stage in [&"out", &"in"]:
			var stem := "reload_%s_%s" % [stage, rc]
			for i in count(StringName(stem)):
				var rpath := "%s%s_%d.ogg" % [DIR, stem, i]
				var rmd5 := FileAccess.get_md5(rpath)
				if owner.has(rmd5) and owner[rmd5] != stem:
					out.append("%s and %s are the same recording" % [owner[rmd5], rpath])
				owner[rmd5] = stem
	for sound_class: StringName in FIRE:
		var base := String(FIRE[sound_class]).trim_suffix("_fire")
		for stem: String in [String(FIRE[sound_class]), base + "_far"]:
			for i in count(StringName(stem)):
				var path := "%s%s_%d.ogg" % [DIR, stem, i]
				var md5 := FileAccess.get_md5(path)
				if owner.has(md5) and owner[md5] != stem:
					out.append("%s and %s are the same recording" % [owner[md5], path])
				owner[md5] = stem
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
