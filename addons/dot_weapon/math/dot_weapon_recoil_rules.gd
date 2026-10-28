class_name DotWeaponRecoilRules
extends DotWeaponCvarRules

## Per-weapon recoil pattern as server cvars (`sv_recoil_*`, replicated), shared by every game.
##
## The pattern is a pure function of the shot's index in a burst and the weapon's seed, so the server's
## bullet and the client's view kick agree with no extra data on the wire. Off by default: a weapon then
## keeps its flat alternating kick. [member punch] splits each kick between the view and the bullet.
##
## [codeblock]
## world.recoil_rules.bind_cvars(add_cvar, DotConVar.FLAG_NOTIFY | DotConVar.FLAG_REPLICATED)  # server
## game.recoil_rules.follow_cvars(link)                                                        # client
## arsenal.recoil_rules = rules  # every arsenal, both sides
## [/codeblock]

const _N := &"recoil_n"
const _TICK := &"recoil_tick"
const _ACC_X := &"recoil_ax"
const _ACC_Y := &"recoil_ay"

## property: [default, min, max, description]
const FIELDS := {
	&"enabled": [0.0, 0.0, 1.0, "1 turns on per-weapon recoil patterns"],
	&"scale": [1.0, 0.0, 10.0, "Master multiplier on every weapon's recoil"],
	&"vertical": [1.0, 0.0, 10.0, "Multiplier on the upward kick"],
	&"horizontal": [1.0, 0.0, 10.0, "Multiplier on the sideways drift"],
	&"recovery": [1.0, 0.0, 20.0, "Multiplier on how fast recoil settles after the trigger is released"],
	&"punch": [1.0, 0.0, 1.0, "Share of each kick that turns the view; the rest offsets the bullet only"],
	&"build": [1.0, 0.0, 10.0, "Multiplier on how much sustained fire builds the kick"],
	&"reset": [0.4, 0.05, 5.0, "Seconds without a shot after which the pattern starts over"],
	&"mult_aim": [0.6, 0.0, 10.0, "Recoil multiplier while aiming down sights"],
	&"mult_crouch": [0.8, 0.0, 10.0, "Recoil multiplier while crouched"],
	&"mult_move": [1.25, 0.0, 10.0, "Recoil multiplier while moving (above sv_spread_walk_speed)"],
	&"mult_air": [1.5, 0.0, 10.0, "Recoil multiplier in the air"],
}

var enabled: bool = false
var scale: float = 1.0
var vertical: float = 1.0
var horizontal: float = 1.0
var recovery: float = 1.0
var punch: float = 1.0
var build: float = 1.0
var reset: float = 0.4
var mult_aim: float = 0.6
var mult_crouch: float = 0.8
var mult_move: float = 1.25
var mult_air: float = 1.5


## The rules an arsenal carries, or null when absent or off.
static func of(arsenal: Object) -> DotWeaponRecoilRules:
	var rules := arsenal.get("recoil_rules") as DotWeaponRecoilRules if arsenal != null else null
	return rules if rules != null and rules.enabled else null


## Sideways drift for shot [param index] of a burst, in -1..1, a pure function of the seed. A third of it
## is a steady lean to the seed's side, so a long burst walks one way instead of cancelling out.
static func drift(seed_value: int, index: int) -> float:
	var h := ((seed_value * 73856093) ^ ((index + 1) * 19349663)) & 0x7fffffff
	var noise := float(h % 2001) / 1000.0 - 1.0
	var lean := 1.0 if ((seed_value >> 3) & 1) == 0 else -1.0
	return clampf(noise * 0.67 + lean * 0.33, -1.0, 1.0)


## A weapon's seed from its tuning, else from its id (stable across processes, unlike `hash`).
static func seed_for(b: DotWeaponBallistics, id: StringName) -> int:
	if b != null and b.recoil_seed != 0:
		return b.recoil_seed
	var h := 17
	for c in String(id).to_utf8_buffer():
		h = (h * 31 + c) & 0x7fffffff
	return h


## Posture multiplier for this context.
func posture(ctx: DotWeaponContext, walk_speed: float = 0.5) -> float:
	var f := scale
	if ctx.aiming:
		f *= mult_aim
	if ctx.crouched:
		f *= mult_crouch
	if ctx.airborne:
		f *= mult_air
	elif ctx.speed >= walk_speed:
		f *= mult_move
	return f


## Kick for the use at [param ctx]: sets the outcome's view kick and recovery, advances the burst in
## [param state], and returns the degrees (pitch, yaw) the bullet itself is offset by.
func apply(out: DotWeaponOutcome, b: DotWeaponBallistics, state: Dictionary, ctx: DotWeaponContext, id: StringName, tick_rate: int) -> Vector2:
	var rate := float(maxi(tick_rate, 1))
	var last := int(state.get(_TICK, -1000000))
	var elapsed := maxf(float(ctx.tick - last) / rate, 0.0)
	var n := int(state.get(_N, 0)) if elapsed <= reset else 0
	var rec := b.recoil_recovery * recovery
	var acc := Vector2(float(state.get(_ACC_X, 0.0)), float(state.get(_ACC_Y, 0.0)))
	acc *= exp(-rec * elapsed)

	var grow := 1.0 + minf(b.recoil_build * build * float(n), b.recoil_build_max * build)
	var f := posture(ctx)
	var kick := Vector2(
		b.recoil_pitch * vertical * grow * f,
		b.recoil_yaw * horizontal * grow * f * drift(seed_for(b, id), n),
	)
	acc += kick

	state[_N] = n + 1
	state[_TICK] = ctx.tick
	state[_ACC_X] = acc.x
	state[_ACC_Y] = acc.y

	out.recoil = kick * punch
	out.recoil_recovery = rec
	out.recoil_signed = true
	return acc * (1.0 - punch)


## Turns [param dir] by [param offset] degrees (pitch up, yaw), about the view's own axes.
static func offset_direction(dir: Vector3, offset: Vector2) -> Vector3:
	if offset == Vector2.ZERO:
		return dir
	var right := dir.cross(Vector3.UP)
	if right.length_squared() < 0.0001:
		return dir
	right = right.normalized()
	return dir.rotated(right, deg_to_rad(offset.x)).rotated(Vector3.UP, deg_to_rad(offset.y)).normalized()


func fields() -> Dictionary:
	return FIELDS


func prefix() -> String:
	return "sv_recoil"
