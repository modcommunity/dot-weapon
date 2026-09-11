class_name DotWeaponPlayerBridge
extends RefCounted

## Fills a [DotWeaponContext] from a player, and hangs a view model on their hands.
##
## [b]dot-player is not a dependency and is not named here.[/b] Same rule as
## [DotWeaponLoadoutBridge]: a script that mentions a [code]class_name[/code] the
## project does not have fails to parse and takes every script referencing it down with
## it, so everything below is duck-typed. A "player" here is any node that answers
## [code]player_key[/code], and everything else is optional.
##
## What it removes is the twenty lines every game wrote: an origin that is the eye
## rather than the feet, a direction that is where the camera is looking rather than
## where the body is facing, a stable entity number, and a mount to parent a view model
## to. Each of those is one line and each of them is wrong in at least one game.
##
## [codeblock]
## var ctx := DotWeaponPlayerBridge.context_for(player, tick, index)
## var outcome := arsenal.use(ctx)
## [/codeblock]

const CHANNEL := "weapon.player"


## A stable, non-negative entity number for a player key.
##
## [b]Stable across machines and across a reconnect, which is what makes it usable at
## all.[/b] dot-weapon identifies the user of a weapon by an [code]int[/code] because
## that is what fits in a wire message; a player is identified by a string key
## everywhere else in the family. Something has to convert, and a counter would give
## different numbers on the server and the client for the same person.
##
## Godot's [method @GlobalScope.hash] over the key, masked to 31 bits. Collisions are
## possible in principle and have never mattered in practice: the number is only
## compared against other players' in the same session, and a session is a few dozen
## keys out of two billion.
static func entity_of(key: String) -> int:
	return hash(key) & 0x7FFFFFFF


## Builds a context from whatever the player node can answer.
##
## Origin and direction come from the active controller's eye transform when there is
## one — [b]not from the body[/b]. A shot fired from a capsule's origin comes out of the
## player's knees, and one aimed along the body's facing comes out sideways whenever the
## player is looking anywhere but straight ahead. Both are bugs that present as bad hit
## registration.
static func context_for(
	player: Node,
	tick: int,
	index: int = 0,
	charge: float = 1.0
) -> DotWeaponContext:
	var ctx := DotWeaponContext.new()
	ctx.tick = tick
	ctx.index = index
	ctx.charge = charge

	if player == null:
		return ctx

	var key := str(player.get("player_key"))
	ctx.entity = entity_of(key)

	var eye := _eye_of(player)
	ctx.origin = eye.origin
	# -Z is Godot's forward, and a basis column rather than a rotated vector so that a
	# rig with a non-uniform scale still aims where it looks.
	ctx.direction = -eye.basis.z

	var motion := _motion_of(player)
	ctx.speed = float(motion.get("speed", 0.0))
	ctx.airborne = not bool(motion.get("on_floor", true))
	ctx.crouched = bool(motion.get("crouched", false))

	return ctx


## Where a player's eyes are, falling back sensibly twice.
##
## The controller first, because in third person the viewpoint is the camera and is
## nowhere near the character's head. Then the character's own eye height, which is what
## a server with no camera has. Then the body, which is wrong and is better than
## nothing — and is the case a game should notice, so it is logged.
static func _eye_of(player: Node) -> Transform3D:
	var switch: Variant = _component(player, "DotPlayerControllerSwitch")

	if switch != null and (switch as Node).has_method("active_controller"):
		var active: Variant = (switch as Node).call("active_controller")
		if active is Node and (active as Node).has_method("eye_transform"):
			return (active as Node).call("eye_transform") as Transform3D

	var controller: Variant = _component(player, "DotPlayerController")

	if controller is Node and (controller as Node).has_method("eye_transform"):
		return (controller as Node).call("eye_transform") as Transform3D

	var character: Variant = _component(player, "DotPlayerChar")

	if character is Node and (character as Node).has_method("eye_height"):
		var feet := _body_transform(player)
		return Transform3D(
			feet.basis,
			feet.origin + Vector3.UP * float((character as Node).call("eye_height"))
		)

	DotLog.debug(
		CHANNEL,
		"no controller or character to take an eye position from; using the body",
		{"player": str(player.get("player_key"))}
	)
	return _body_transform(player)


static func _motion_of(player: Node) -> Dictionary:
	var switch: Variant = _component(player, "DotPlayerControllerSwitch")

	if switch != null and (switch as Node).has_method("active_controller"):
		var active: Variant = (switch as Node).call("active_controller")
		if active is Node and (active as Node).has_method("motion"):
			return (active as Node).call("motion") as Dictionary

	var controller: Variant = _component(player, "DotPlayerController")

	if controller is Node and (controller as Node).has_method("motion"):
		return (controller as Node).call("motion") as Dictionary

	return {}


## Parents a view model to the player's weapon mount, if their character has one.
##
## Returns whether it found somewhere to hang it. False is not an error: a server has no
## model, a 2D game has no bones, and a game that treats "nowhere to attach" as a
## failure cannot run headless.
static func attach_view_model(
	player: Node,
	view_model: Node,
	mount: StringName = &"right_hand"
) -> bool:
	if player == null or view_model == null:
		return false

	var character: Variant = _component(player, "DotPlayerChar")

	if not (character is Node) or not (character as Node).has_method("attachment"):
		return false

	var point: Variant = (character as Node).call("attachment", mount)

	if not (point is Node):
		return false

	if view_model.get_parent() != null:
		view_model.get_parent().remove_child(view_model)

	(point as Node).add_child(view_model)
	return true


## Gives an arsenal whatever a player's class says they start with.
##
## Duck-typed against dot-player-class: a class definition answers
## [code]loadout_id[/code], and a game maps that to weapons with [param mapping] — the
## same seam [DotWeaponLoadoutBridge] uses, because an id space is a game's to decide.
static func give_class_loadout(
	arsenal: DotWeaponArsenal,
	class_def: Object,
	mapping: Dictionary = {}
) -> DotResult:
	if arsenal == null:
		return DotResult.fail(DotError.CODE_INVALID, "No arsenal to fill.")

	if class_def == null:
		return DotResult.fail(DotError.CODE_INVALID, "No class to read a loadout from.")

	var loadout_id := StringName(str(class_def.get("loadout_id")))

	if loadout_id == &"":
		return DotResult.fail(
			DotError.CODE_STATE,
			"That class names no loadout.",
			"A class with no loadout_id is legal — a spectator class, or a mode where "
			+ "the game decides — so this is a state rather than a mistake."
		)

	var ids: Variant = mapping.get(String(loadout_id), null)

	if ids == null:
		return DotResult.fail(
			DotError.CODE_INVALID,
			"Nothing maps loadout '%s' to weapons." % String(loadout_id),
			"dot-weapon deliberately does not own the id space between a loadout and a "
			+ "weapon; the game supplies the table. See DotWeaponLoadoutBridge."
		)

	arsenal.clear()
	var given := 0

	for id: Variant in ids as Array:
		var res := arsenal.give(StringName(str(id)))
		if res.ok:
			given += 1

	return DotResult.success(given)


static func _component(player: Node, type_name: String) -> Object:
	if player == null or not player.has_method("component"):
		return null

	return player.call("component", StringName(type_name)) as Object


static func _body_transform(player: Node) -> Transform3D:
	if player.has_method("body"):
		var body: Variant = player.call("body")
		if body is Node3D:
			return (body as Node3D).global_transform

	if player is Node3D:
		return (player as Node3D).global_transform

	return Transform3D.IDENTITY
