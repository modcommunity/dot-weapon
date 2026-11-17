class_name DotWeaponKnives
extends Node3D
## Thrown knives: aim with the knife in hand throws it. The server flies each on the tick, hurts the first body (rule `damage`), sticks it
## in a body it kills, bounces it off the world and returns it to whoever walks over it; clients mirror the events ([DotWeaponKnifeWire]).
## A game owns one as a child: fill the fields, call [method input] before players simulate and [method tick] after, forward [signal changed].
## Rule `charge` makes the throw a hold-and-release whose power fills over `charge_sec`; a knife whose fitted def has
## [constant PARAM_BOOMERANG] glides a closed loop back to where it left the hand (or homes on the thrower) and sticks in any enemy it hits.

# Players are duck-typed: arsenal (DotWeaponArsenal), is_alive(), muzzle_position(), controller.state.position/.velocity.

## Server: a knife was thrown, bounced, came to rest, stuck or was taken (GONE, [param victim] the taker).
signal changed(id: int, owner: int, phase: int, victim: int, at: Vector3, motion: Vector3)

enum Phase { FLY, REST, STUCK, GONE }

## The defaults of [member rules]; copy it ([code].duplicate()[/code]) for a game's own dictionary.
const DEFAULT_RULES := {
	"enabled": true, "speed": 40.0, "pickup": 1.0, "damage": 10000.0,
	"charge": false, "charge_sec": 1.0, "charge_min": 0.35,
	"boomerang_distance": 18.0, "boomerang_radius": 5.0, "boomerang_speed": 0.0,
	"boomerang_to_thrower": false, "boomerang_left": false, "boomerang_catch": 1.5,
	"boomerang_empty_hand": true,
}
## cvar suffix after the game's prefix -> the rule key it sets, and what it means.
const CVAR_SPECS := DotWeaponKnifeCvars.SPECS
## Set true in a fitted def's params (an attachment's params_set) to make that knife a boomerang.
const PARAM_BOOMERANG := "boomerang"
## How hard a homing boomerang turns toward the hand each tick (0..1).
const HOME_BLEND := 0.2
## Gravity on the throw until its first contact, then the players' own; flat enough to land where aimed.
const THROW_GRAVITY := 8.0
const GRAVITY := 22.0
## Speed kept off a bounce into the surface and along it: steel comes off hard surfaces dead.
const RESTITUTION := 0.3
const SURFACE_KEEP := 0.55
const REST_SPEED := 1.5
## Past this many bounces it settles on the next floor it touches, and past three times it stops anywhere.
const MAX_BOUNCES := 10
## One still flying this long (out of the world) goes back to its owner.
const FLIGHT_SECONDS := 10.0
const THROWER_GRACE_TICKS := 8
## More than this and the oldest goes back to its owner; so does one left lying this long.
const MAX_KNIVES := 32
const LIFETIME_SECONDS := 90.0
## How deep the tip sits in a body, and how far a client looks for the body's ragdoll part.
const EMBED := 0.07
const PART_REACH := 1.2
const SEEK_SECONDS := 0.6
const SPIN := 22.0


class Knife extends RefCounted:
	var id: int = 0
	var owner: int = 0
	var phase: int = Phase.FLY
	var victim: int = 0
	var at: Vector3 = Vector3.ZERO
	var velocity: Vector3 = Vector3.ZERO
	## Which way the blade points: along the flight, into the body, or along the floor.
	var facing: Vector3 = Vector3.FORWARD
	var age: int = 0
	var bounces: int = 0
	var holder: Node3D = null
	var part: Node3D = null
	var part_local: Transform3D = Transform3D.IDENTITY
	var seek: float = 0.0
	var spun: float = 0.0
	var bled: bool = false
	## The speed it left the hand at, and the drop state (fitting) it goes back into an arsenal with.
	var speed: float = 0.0
	var state: Dictionary = {}
	## Boomerang: no gravity while it glides; the velocity turns about turn's axis at its length (rad/s).
	var boomerang: bool = false
	var glide: bool = false
	var turn: Vector3 = Vector3.ZERO
	var origin: Vector3 = Vector3.ZERO
	## The out-circle-back path: unit forward and side, metres out, turn radius and angle, metres flown so far, total length, leg.
	var path_dir: Vector3 = Vector3.ZERO
	var path_side: Vector3 = Vector3.ZERO
	var path_out: float = 0.0
	var path_radius: float = 0.0
	var path_angle: float = PI
	var path_flown: float = 0.0
	var path_len: float = 0.0
	var leg: int = 0
	var homing: bool = false
	## Stuck in a living body: it rides at offset from the victim's feet.
	var riding: bool = false
	var offset: Vector3 = Vector3.ZERO


## `enabled`, `speed` (m/s), `pickup` (m, 0 off) and `damage`; [method bind_cvars] ties them to cvars.
var rules: Dictionary = DEFAULT_RULES.duplicate()
## The weapon id a throw takes out of the hand, gives back, and the damage is credited to.
var weapon_id: StringName = &"knife"
var is_authority: bool = true
var draws: bool = false
var tick_rate: int = 64
var combat: DotCombatManager = null
## Callables from the game: id -> player or null, and the ids of everybody playing.
var player_for: Callable = Callable()
var player_ids: Callable = Callable()
## Client: the ragdolls to stick a knife into, and the blood layer; [method bind_view] sets them.
var ragdolls: Node = null
var blood: Node = null
var look_of: Callable = Callable()
## Server: a gliding knife's state is re-sent this often, since homing is not extrapolated (0 never).
var glide_sync_ticks: int = 8

var _knives: Dictionary = {}
var _next_id: int = 1
var _aim_held: Dictionary = {}
## Player id -> ticks the throw has been held for, while winding up.
var _charge: Dictionary = {}
var _tick: int = 0
var _throw_power: float = 1.0
var _model_box: AABB = AABB()
## The thrower excluded from a [method _sweep], reused so a flying knife does not build an array a tick.
var _exclude: Array = []
## No hitbox sets, for a knife past its first bounce (the trace only reads it).
var _no_sets: Array[DotHitboxSet] = []
## Server: thrower id -> the Boomerang knife id they wait for bare-handed (rule `boomerang_empty_hand`).
var _empty_for: Dictionary = {}


## Registers the rules as cvars named [param prefix] + [constant CVAR_SPECS] through [param add] (a
## server module's add_cvar, shaped [code](name, default, description, flags) -> cvar[/code]); each
## change lands in [param rules_dict]. Returns the cvars.
static func bind_cvars(rules_dict: Dictionary, add: Callable, prefix: String, flags: int = 0) -> Array:
	return DotWeaponKnifeCvars.bind(rules_dict, add, prefix, flags)


func count() -> int:
	return _knives.size()


func get_knife(id: int) -> Knife:
	return _knives.get(id, null)


func entries() -> Array:
	return _knives.values()


## The throw power for [param held_seconds] of winding up under [param rules_dict]: 1 without `charge`.
static func power_fraction(rules_dict: Dictionary, held_seconds: float) -> float:
	if not bool(rules_dict.get("charge", false)):
		return 1.0
	return lerpf(float(rules_dict.get("charge_min", 0.35)), 1.0, fill_fraction(rules_dict, held_seconds))


## How full the power meter is (0..1) after [param held_seconds]; full at once when `charge_sec` is 0.
static func fill_fraction(rules_dict: Dictionary, held_seconds: float) -> float:
	var sec := float(rules_dict.get("charge_sec", 1.0))
	return 1.0 if sec <= 0.0 else clampf(held_seconds / sec, 0.0, 1.0)


## Whether [param def] (a fitted def) throws as a boomerang; the param may be keyed by String or StringName.
static func is_boomerang(def: DotWeaponDef) -> bool:
	return def != null and bool(def.params.get(PARAM_BOOMERANG, def.params.get(StringName(PARAM_BOOMERANG), false)))


## Server: how full [param id]'s throw meter is (0..1), or -1 when they are not winding up.
func charge_of(id: int) -> float:
	if not _charge.has(id):
		return -1.0
	return fill_fraction(rules, float(_charge[id]) / float(tick_rate))


## Server, before the player simulates: the aim key's rising edge with the knife in hand throws it, or with
## `charge` starts winding up and the release throws. The button is cleared on [param fire] while it is the knife's.
func input(id: int, player, fire: DotWeaponCommand) -> void:
	if not is_authority or fire == null or player == null or player.arsenal == null:
		return
	var down := fire.is_pressed(DotWeaponCommand.BUTTON_AIM)
	var was: bool = _aim_held.get(id, false)
	_aim_held[id] = down
	var def: DotWeaponDef = player.arsenal.current_def()
	var in_hand := def != null and def.id == weapon_id
	if not bool(rules.get("enabled", true)):
		var _off := _charge.erase(id)
		return
	if _charge.has(id):
		if not in_hand or not player.is_alive():
			var _cancel := _charge.erase(id)
			return
		fire.set_button(DotWeaponCommand.BUTTON_AIM, false)
		if down:
			_charge[id] = int(_charge[id]) + 1
			return
		var held := float(_charge[id]) / float(tick_rate)
		var _done := _charge.erase(id)
		_release(id, player, def, fire, power_fraction(rules, held))
		return
	if not down or was or not in_hand:
		return
	fire.set_button(DotWeaponCommand.BUTTON_AIM, false)
	if bool(rules.get("charge", false)):
		_charge[id] = 0
		return
	_release(id, player, def, fire, 1.0)


func _release(id: int, player, def: DotWeaponDef, fire: DotWeaponCommand, power: float) -> void:
	var boomerang := is_boomerang(def)
	var state: Dictionary = player.arsenal.drop_from_slot(player.arsenal.current_slot())
	if state.is_empty():
		return
	var _id := throw(id, player.muzzle_position(), fire.aim_direction(), player.controller.state.velocity, power, boomerang, state)


## Server: a knife leaves [param from] along [param aim] at the rule's speed times [param power] plus [param carried].
## [param state] is the arsenal's drop state, put back on whoever gets it.
func throw(owner: int, from: Vector3, aim: Vector3, carried: Vector3 = Vector3.ZERO, power: float = 1.0, boomerang: bool = false, state: Dictionary = {}) -> int:
	var k := Knife.new()
	k.id = _next_id
	_next_id += 1
	k.owner = owner
	k.at = from
	_throw_power = power
	k.velocity = aim.normalized() * float(rules.get("speed", 40.0)) * power + carried
	k.facing = k.velocity.normalized()
	k.speed = k.velocity.length()
	k.state = state
	if boomerang:
		_launch_boomerang(k)
	_knives[k.id] = k
	if boomerang:
		_wait_bare_handed(k)
	_tell(k)
	if _knives.size() > MAX_KNIVES:
		var oldest: Knife = _knives[_knives.keys().min()]
		_finish(oldest, oldest.owner, true)
	return k.id


## Rule `boomerang_empty_hand`: the thrower lowers what the throw drew and waits for the catch with an empty hand.
func _wait_bare_handed(k: Knife) -> void:
	if not bool(rules.get("boomerang_empty_hand", true)) or not player_for.is_valid():
		return
	var p = player_for.call(k.owner)
	if p == null or p.arsenal == null or not p.arsenal.has_method(&"empty_hand"):
		return
	var _emptied: bool = p.arsenal.empty_hand()
	_empty_for[k.owner] = k.id


## A thrower waiting bare-handed whose Boomerang will not come back to the hand (it fell, stuck or was taken)
## gets the first weapon they carry up; a catch already put the knife in the hand, a switch of their own ends the wait.
func _end_bare_hands() -> void:
	for owner: int in _empty_for.keys():
		var k: Knife = _knives.get(_empty_for[owner], null)
		if k != null and k.phase == Phase.FLY and k.glide:
			continue
		_empty_for.erase(owner)
		var p = player_for.call(owner) if player_for.is_valid() else null
		if p == null or not p.is_alive() or p.arsenal == null or p.arsenal.current_slot() != 0:
			continue
		var carried: Array = p.arsenal.slots()
		if not carried.is_empty():
			p.arsenal.bring_to_hand(int(carried[0]))


## A boomerang reaches `boomerang_distance` metres from the throw point along the throw (its farthest point), going straight
## out and then circling through a turn of radius `boomerang_radius` and flying the tangent straight back to
## [member Knife.origin], where it was thrown from. A radius over the distance flies one full circle of that radius.
## The turn leaves the circle on the line through the origin, so the way back is as long as the way out.
## The position is a function of the metres flown, so two servers agree bit for bit and it ends on the origin exactly.
## The thrower's own velocity is not added: it would move the origin the path closes on.
func _launch_boomerang(k: Knife) -> void:
	k.boomerang = true
	k.glide = true
	k.origin = k.at
	var aim := k.velocity.normalized()
	var set_speed := float(rules.get("boomerang_speed", 0.0))
	var speed := set_speed if set_speed > 0.0 else float(rules.get("speed", 40.0)) * _throw_power
	k.velocity = aim * speed
	k.speed = speed
	var out := float(rules.get("boomerang_distance", 18.0))
	if out <= 0.0 or speed <= 0.0:
		return
	var right := aim.cross(Vector3.UP)
	if right.length() < 0.01:
		right = Vector3.RIGHT
	k.path_dir = aim
	k.path_side = right.normalized() * (-1.0 if bool(rules.get("boomerang_left", false)) else 1.0)
	k.path_radius = maxf(0.0, float(rules.get("boomerang_radius", 5.0)))
	k.path_out = maxf(0.0, out - k.path_radius)
	k.path_angle = PI + 2.0 * atan2(k.path_radius, k.path_out)
	k.path_len = 2.0 * k.path_out + k.path_radius * k.path_angle
	k.leg = 0
	k.turn = Vector3.ZERO


## Where the boomerang is after [param s] metres of its path, and the unit direction it points there.
func _path_point(k: Knife, s: float) -> Array:
	var out := k.path_out
	var r := k.path_radius
	var d := k.path_dir
	var side := k.path_side
	var arc := r * k.path_angle
	if s <= out:
		return [k.origin + d * s, d]
	if r <= 0.0:
		return [k.origin + d * out - d * (s - out), -d]
	var centre := k.origin + d * out + side * r
	if s <= out + arc:
		var phi := (s - out) / r
		return [centre + (d * sin(phi) - side * cos(phi)) * r, d * cos(phi) + side * sin(phi)]
	var back := d * cos(k.path_angle) + side * sin(k.path_angle)
	var start := centre + (d * sin(k.path_angle) - side * cos(k.path_angle)) * r
	return [start + back * (s - out - arc), back]


## Which leg [param s] metres in: 0 straight out, 1 the turn, 2 straight back.
func _path_leg(k: Knife, s: float) -> int:
	if s < k.path_out:
		return 0
	return 1 if s < k.path_out + k.path_radius * k.path_angle else 2


## The velocity turn of leg [param leg]: about the turn's axis while circling, none on the straights.
func _leg_turn(k: Knife, leg: int) -> Vector3:
	if leg != 1 or k.path_radius <= 0.0:
		return Vector3.ZERO
	return k.path_dir.cross(k.path_side) * (k.speed / k.path_radius)


## Whether knife [param id] is gliding (no gravity), and the turn it glides with: for the wire.
func glides(id: int) -> bool:
	var k: Knife = _knives.get(id, null)
	return k != null and k.glide


func turn_of(id: int) -> Vector3:
	var k: Knife = _knives.get(id, null)
	return k.turn if k != null and k.glide else Vector3.ZERO


## Server, every tick after the players moved.
func tick(current_tick: int, delta: float) -> void:
	if not is_authority:
		return
	_tick = current_tick
	for k: Knife in _knives.values():
		k.age += 1
		if k.phase == Phase.FLY:
			_fly(k, delta)
		if k.phase == Phase.GONE:
			continue
		if k.phase == Phase.FLY and k.glide and glide_sync_ticks > 0 and k.age % glide_sync_ticks == 0:
			_tell(k)
		if k.riding:
			_ride(k)
		var limit := FLIGHT_SECONDS if k.phase == Phase.FLY else LIFETIME_SECONDS
		if k.age >= int(limit * tick_rate):
			_finish(k, k.owner, true)
			continue
		_offer(k)
	if not _empty_for.is_empty():
		_end_bare_hands()


func _fly(k: Knife, delta: float) -> void:
	var step := Vector3.ZERO
	var arrived := false
	if k.glide and k.path_len > 0.0 and not k.homing:
		var flown := minf(k.path_flown + k.speed * delta, k.path_len)
		arrived = flown >= k.path_len
		var here := _path_point(k, flown)
		k.path_flown = flown
		k.velocity = (here[1] as Vector3) * k.speed
		step = (k.origin if arrived else here[0] as Vector3) - k.at
		var leg := _path_leg(k, flown)
		if leg != k.leg:
			k.leg = leg
			k.turn = _leg_turn(k, leg)
			if leg == 2 and bool(rules.get("boomerang_to_thrower", false)):
				k.homing = true
				k.path_len = 0.0
				arrived = false
			_tell(k)
	else:
		if k.glide:
			if k.homing and not _home(k, delta):
				return
			if k.turn != Vector3.ZERO:
				k.velocity = k.velocity.rotated(k.turn.normalized(), k.turn.length() * delta)
		else:
			k.velocity.y -= (THROW_GRAVITY if k.bounces == 0 else GRAVITY) * delta
		step = k.velocity * delta
	var hit := _sweep(k, step)
	if hit == null:
		k.at += step
		if k.velocity.length() > 0.5:
			k.facing = k.velocity.normalized()
		if k.boomerang and k.glide and k.leg == 2 and _catch(k):
			return
		if arrived:
			k.at = k.origin
			_drop_out(k)
		return
	if not hit.blocked and _kill(k, hit):
		return
	k.glide = false
	k.turn = Vector3.ZERO
	_bounce(k, hit)
	_tell(k)


## Gliding ends: it falls from where it is and can no longer hurt anyone.
func _drop_out(k: Knife) -> void:
	k.glide = false
	k.homing = false
	k.turn = Vector3.ZERO
	k.velocity = Vector3.ZERO
	k.bounces = maxi(k.bounces, 1)
	_tell(k)


## Steers toward the thrower's hand, which catches it within the pickup reach; false when it was caught or dropped.
func _home(k: Knife, delta: float) -> bool:
	var p = player_for.call(k.owner) if player_for.is_valid() else null
	if p == null or not p.is_alive() or p.arsenal == null or p.arsenal.carries(weapon_id):
		_drop_out(k)
		return false
	var to: Vector3 = p.muzzle_position() - k.at
	if to.length() <= float(rules.get("pickup", 1.0)) + k.speed * delta:
		_finish(k, k.owner, true)
		return false
	k.velocity = k.velocity.lerp(to.normalized() * k.speed, HOME_BLEND).normalized() * k.speed
	return true


## Server: a knife in a living body follows it; when the body dies it stays where it was, and clients find the ragdoll.
func _ride(k: Knife) -> void:
	var p = player_for.call(k.victim) if player_for.is_valid() else null
	if p == null or not p.is_alive():
		k.riding = false
		_tell(k)
		return
	k.at = p.controller.state.position + k.offset


## The first enemy the blade meets dies, and the knife stays in them; a boomerang stays in a survivor too.
func _kill(k: Knife, hit: DotHitbox.Hit) -> bool:
	if combat == null or not combat.is_authority or hit.entity == null:
		return false
	var victim := combat.entity_id_of(hit.entity)
	var health := combat.health_of(victim) if victim != 0 else null
	if victim == k.owner or health == null or not health.alive:
		return false
	var damage := DotDamage.make(k.owner, victim, float(rules.get("damage", 10000.0)), combat.damage_type(&"strike"))
	damage.tick = _tick
	damage.point = hit.point
	damage.direction = k.velocity.normalized()
	damage.weapon_id = weapon_id
	damage.context = {"why": &"knife_throw"}
	var _applied := combat.apply_damage(damage)
	if damage.refused or (health.alive and not k.boomerang):
		return false
	k.facing = k.velocity.normalized()
	k.phase = Phase.STUCK
	k.victim = victim
	k.at = hit.point
	k.velocity = Vector3.ZERO
	k.glide = false
	k.turn = Vector3.ZERO
	var p = player_for.call(victim) if health.alive and player_for.is_valid() else null
	if p != null:
		k.riding = true
		k.offset = hit.point - (p.controller.state.position as Vector3)
	_tell(k)
	return true


func _bounce(k: Knife, hit: DotHitbox.Hit) -> void:
	var normal := hit.normal
	if normal.length_squared() < 0.0001:
		normal = -k.velocity.normalized()
	k.at = hit.point + normal * 0.03
	var into := k.velocity.dot(normal)
	var along := k.velocity - normal * into
	k.velocity = along * SURFACE_KEEP - normal * into * RESTITUTION
	k.bounces += 1
	var on_floor := normal.y > 0.7 and (k.velocity.length() < REST_SPEED or k.bounces >= MAX_BOUNCES)
	if on_floor or k.bounces >= MAX_BOUNCES * 3:
		var flat := Vector3(k.facing.x, 0.0, k.facing.z)
		k.facing = flat.normalized() if flat.length() > 0.01 else Vector3.FORWARD
		k.velocity = Vector3.ZERO
		k.phase = Phase.REST


## One tick of flight against the world and, before its first bounce, every body but the thrower's.
func _sweep(k: Knife, step: Vector3) -> DotHitbox.Hit:
	if combat == null or combat.trace == null or step.length() <= 0.0:
		return null
	var sets: Array[DotHitboxSet] = combat.hitbox_sets() if k.bounces == 0 and is_authority else _no_sets
	var thrower := combat.hitboxes_of(k.owner)
	_exclude.clear()
	if thrower != null:
		_exclude.append(thrower)
	combat.trace.exclude = _exclude
	var hit := combat.trace.ray(k.at, step.normalized(), step.length(), sets)
	_exclude.clear()
	return hit if hit != null and hit.ok() else null


## Somebody alive without a knife within the pickup reach of one lying still takes it.
func _offer(k: Knife) -> void:
	var reach := float(rules.get("pickup", 1.0))
	if reach <= 0.0 or k.phase == Phase.FLY or not player_ids.is_valid():
		return
	for id: int in player_ids.call():
		var p = player_for.call(id)
		if p == null or not p.is_alive() or p.arsenal == null or p.arsenal.carries(weapon_id):
			continue
		if k.riding and id == k.victim:
			continue
		var feet: Vector3 = p.controller.state.position
		var close := Vector3(feet.x, clampf(k.at.y, feet.y, feet.y + 1.8), feet.z)
		if close.distance_to(k.at) <= reach and _give_back(p, k):
			_finish(k, id, false)
			return


## A Boomerang on its way back (the return leg) is caught when it passes within `boomerang_catch` metres of its
## thrower's hand, the thrower alive with no knife: back in the hand, not dropped at the throw point.
## False when it flies on (no catch rule, the thrower dead, away or already holding one).
func _catch(k: Knife) -> bool:
	var reach := float(rules.get("boomerang_catch", 0.0))
	if reach <= 0.0 or not player_for.is_valid():
		return false
	var p = player_for.call(k.owner)
	if p == null or not p.is_alive() or p.arsenal == null or p.arsenal.carries(weapon_id):
		return false
	if (p.muzzle_position() as Vector3).distance_to(k.at) > reach:
		return false
	_finish(k, k.owner, true)
	return true


## Takes [param k] out of the world; [param returning] gives it to [param to] when alive and without one.
func _finish(k: Knife, to: int, returning: bool) -> void:
	if returning and player_for.is_valid():
		var p = player_for.call(to)
		if p != null and p.is_alive() and p.arsenal != null and not p.arsenal.carries(weapon_id):
			var _given := _give_back(p, k)
	k.phase = Phase.GONE
	k.victim = to
	_tell(k)
	_drop_view(k)
	var _gone := _knives.erase(k.id)


## Gives the knife to [param p] with what was fitted to it when it left the hand.
func _give_back(p, k: Knife) -> bool:
	var given: DotResult = p.arsenal.give(weapon_id, true)
	if given.ok and k.state.has("fit"):
		p.arsenal.apply_dropped(k.state)
	return given.ok


func _tell(k: Knife) -> void:
	changed.emit(k.id, k.owner, k.phase, k.victim, k.at, k.velocity if k.phase == Phase.FLY else k.facing)


## Client: one knife event from the server. [param motion] is the velocity in flight, else the blade's facing;
## [param glide] and [param turn] are [method glides] and [method turn_of] on the server.
func mirror(id: int, owner: int, phase: int, victim: int, at: Vector3, motion: Vector3, glide: bool = false, turn: Vector3 = Vector3.ZERO) -> void:
	if is_authority:
		return
	var k: Knife = _knives.get(id, null)
	if phase == Phase.GONE:
		if k != null:
			_drop_view(k)
			var _gone := _knives.erase(id)
		return
	if k == null:
		k = Knife.new()
		k.id = id
		_knives[id] = k
	var was := k.phase
	k.owner = owner
	k.phase = phase
	k.victim = victim
	k.at = at
	k.velocity = motion if phase == Phase.FLY else Vector3.ZERO
	k.glide = glide and phase == Phase.FLY
	k.turn = turn if k.glide else Vector3.ZERO
	if motion.length() > 0.01:
		k.facing = motion.normalized()
	if phase == Phase.FLY and k.bounces == 0 and was == Phase.FLY and k.age > 0 and not glide:
		k.bounces = 1
	if phase != Phase.STUCK:
		return
	var rider = _rider(victim)
	if was != Phase.STUCK or k.holder == null or (k.riding and rider == null):
		k.seek = SEEK_SECONDS
		k.part = null
	k.riding = rider != null
	if k.riding:
		k.offset = at - (rider.controller.state.position as Vector3)


## The living player [param id], or null.
func _rider(id: int):
	var p = player_for.call(id) if player_for.is_valid() and id != 0 else null
	return p if p != null and p.is_alive() else null


## Client: flies the mirrors between events, against the world only; the server's next event corrects it.
func _physics_process(delta: float) -> void:
	if is_authority:
		return
	for k: Knife in _knives.values():
		if k.phase != Phase.FLY:
			continue
		k.age += 1
		if not k.glide:
			k.velocity.y -= (THROW_GRAVITY if k.bounces == 0 else GRAVITY) * delta
		elif k.turn != Vector3.ZERO:
			k.velocity = k.velocity.rotated(k.turn.normalized(), k.turn.length() * delta)
		var step := k.velocity * delta
		var hit := _sweep(k, step)
		if hit == null:
			k.at += step
		else:
			k.glide = false
			_bounce(k, hit)


## Client: where the ragdolls and the blood are. Cheap; called every frame.
func bind_view(ragdoll_layer: Node, blood_layer: Node) -> void:
	ragdolls = ragdoll_layer
	blood = blood_layer


func _process(delta: float) -> void:
	if not draws:
		return
	for k: Knife in _knives.values():
		_draw(k, delta)


func _draw(k: Knife, delta: float) -> void:
	if k.holder == null:
		k.holder = _make_holder()
	var model: Node3D = k.holder.get_child(0)
	if k.phase == Phase.STUCK:
		_draw_stuck(k, model, delta)
		return
	var face := k.facing if k.facing.length() > 0.01 else Vector3.FORWARD
	k.holder.global_transform = Transform3D(_basis_along(face), k.at)
	var c := _model_box.get_center()
	if k.phase == Phase.FLY:
		## Tumbling end over end about its own centre.
		k.spun += SPIN * delta
		model.transform = Transform3D(Basis(Vector3.RIGHT, -k.spun), Vector3.ZERO) * Transform3D(Basis.IDENTITY, -c)
	else:
		## Flat on its side, a hair over the floor.
		var lie := Basis(Vector3.FORWARD, PI * 0.5)
		model.transform = Transform3D(lie, Vector3(0.0, _model_box.size.x * 0.5 + 0.005, 0.0)) * Transform3D(Basis.IDENTITY, -c)


## In the body: the tip [constant EMBED] past the hit point, following the ragdoll part nearest it.
func _draw_stuck(k: Knife, model: Node3D, delta: float) -> void:
	var c := _model_box.get_center()
	model.transform = Transform3D(Basis.IDENTITY, Vector3(-c.x, -c.y, -_model_box.position.z - EMBED))
	if k.holder.get_child_count() < 2:
		k.holder.add_child(_wound())
	if not k.bled:
		k.bled = true
		_bleed(k)
	if k.riding:
		var rider = _rider(k.victim)
		if rider != null:
			k.holder.global_transform = Transform3D(_basis_along(k.facing), (rider.controller.state.position as Vector3) + k.offset)
			return
		k.riding = false
		k.seek = SEEK_SECONDS
	if k.part != null:
		if is_instance_valid(k.part) and k.part.is_inside_tree():
			k.holder.global_transform = k.part.global_transform * k.part_local
			return
		k.part = null
	k.holder.global_transform = Transform3D(_basis_along(k.facing), k.at)
	if k.seek > 0.0:
		k.seek -= delta
		k.part = _nearest_part(k.at)
		if k.part != null:
			k.part_local = k.part.global_transform.affine_inverse() * k.holder.global_transform
			k.seek = 0.0


func _nearest_part(at: Vector3) -> Node3D:
	if ragdolls == null or not is_instance_valid(ragdolls) or not ragdolls.has_method(&"live"):
		return null
	var best: Node3D = null
	var best_d := PART_REACH
	for doll in ragdolls.call(&"live"):
		if doll == null or not is_instance_valid(doll) or not doll.has_method(&"part_nodes"):
			continue
		for part in doll.call(&"part_nodes"):
			if part is Node3D and is_instance_valid(part):
				var d: float = (part as Node3D).global_position.distance_to(at)
				if d < best_d:
					best_d = d
					best = part
	return best


func _bleed(k: Knife) -> void:
	if blood == null or not is_instance_valid(blood):
		return
	if blood.has_method(&"splat_behind"):
		var _behind: Variant = blood.call(&"splat_behind", k.at - k.facing * 0.5, k.at, 3.0, 0.8)
	if blood.has_method(&"splat_below"):
		var _pool: Variant = blood.call(&"splat_below", k.at, 3.0, 0.2, 0.7)


func _wound() -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.055
	mesh.height = 0.11
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.01, 0.01)
	mat.roughness = 0.25
	mesh.material = mat
	var wound := MeshInstance3D.new()
	wound.mesh = mesh
	wound.scale = Vector3(1.0, 1.0, 0.35)
	return wound


func _make_holder() -> Node3D:
	var model: Node3D = look_of.call(weapon_id) if look_of.is_valid() else null
	if model == null:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.02, 0.04, 0.3)
		var box := MeshInstance3D.new()
		box.mesh = mesh
		model = box
	var holder := Node3D.new()
	holder.name = "Knife"
	holder.add_child(model)
	add_child(holder)
	if _model_box.size == Vector3.ZERO:
		_model_box = _bounds(model)
	return holder


## The model's mesh extent in its own space.
static func _bounds(model: Node3D) -> AABB:
	var out: Variant = _bounds_under(model, model.global_transform.affine_inverse(), null)
	return out if out != null else AABB(Vector3(-0.01, -0.02, -0.15), Vector3(0.02, 0.04, 0.3))


## [param acc] (an AABB, or null for none yet) merged with the mesh extents of [param n] and everything under it.
static func _bounds_under(n: Node, inv: Transform3D, acc: Variant) -> Variant:
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		var mi := n as MeshInstance3D
		var box := inv * mi.global_transform * mi.mesh.get_aabb()
		acc = box if acc == null else (acc as AABB).merge(box)
	for i in n.get_child_count():
		acc = _bounds_under(n.get_child(i), inv, acc)
	return acc


## A basis whose -Z is [param forward].
static func _basis_along(forward: Vector3) -> Basis:
	var f := forward.normalized()
	var up := Vector3.UP if absf(f.dot(Vector3.UP)) < 0.98 else Vector3.RIGHT
	return Basis.looking_at(f, up)


func _drop_view(k: Knife) -> void:
	if k.holder != null and is_instance_valid(k.holder):
		k.holder.queue_free()
	k.holder = null
	k.part = null


## Everything gone at once, for a map change or a round reset; owners get theirs back on the server.
func clear() -> void:
	for k: Knife in _knives.values():
		if is_authority:
			_finish(k, k.owner, true)
		else:
			_drop_view(k)
	_knives.clear()
	_aim_held.clear()
	_charge.clear()
	_empty_for.clear()
