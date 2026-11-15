What a player holds and uses: a catalogue of weapon definitions that each name a behaviour script by path. Guns, bows, melee, thrown charges, beams, and anything your game writes that none of those describe. Adding a weapon is a script, a definition and a row in a table, never an edit to the addon.

## Install

1. Get [Godot 4.7](https://godotengine.org/download).
2. Either use [dot-bootstrap](https://github.com/gamespice-platform/bootstrap), which clones every project and links the addons, or copy `addons/dot_weapon/`, dot-core's `addons/dot_core/` and [dot-combat](https://github.com/gamespice-platform/combat)'s `addons/dot_combat/` into your project and enable dot-weapon in *Project > Project Settings > Plugins*.

It needs [dot-core](https://github.com/gamespice-platform/core) and dot-combat. [dot-loadout](https://github.com/gamespice-platform/loadout) and [dot-inventory](https://github.com/gamespice-platform/inventory) are optional.

## Use

```gdscript
var arsenal := DotWeaponArsenal.new()
arsenal.catalogue = my_catalogue
arsenal.authority = is_server
add_child(arsenal)
arsenal.setup()

arsenal.give(&"rifle")

# once a tick
var ctx := DotWeaponContext.make(player_id, tick, eye_position, aim_direction)
ctx.speed = state.horizontal_speed()
ctx.airborne = not state.is_grounded()

var outcome := arsenal.simulate_tick(command, ctx, previous_command)

for shot in outcome.shots:
    combat.resolve_shot(shot)

for spawn in outcome.spawns:
    my_projectiles.launch(spawn)
```

## A new weapon

A behaviour is a script that returns what a use produced:

```gdscript
extends "res://addons/dot_weapon/behaviour/dot_weapon_behaviour.gd"

func _use(ctx: DotWeaponContext) -> DotWeaponOutcome:
    var out := DotWeaponOutcome.of(DotWeaponOutcome.KIND_SPAWN)
    var arrow := DotWeaponSpawn.make(&"arrow", ctx.origin, ctx.direction * lerpf(
        25.0, 90.0, ctx.charge
    ), ctx.entity)
    arrow.damage = lerpf(14.0, 70.0, ctx.charge)
    arrow.gravity_scale = 1.0
    out.add_spawn(arrow)
    return out
```

A bow is a row in a table with fire mode `CHARGE`; the arsenal accumulates the draw and the behaviour reads `ctx.charge`. A crossbow is the same row with `SEMI` and a reload.

| Fire mode | When a use happens |
| --- | --- |
| `SEMI` | On the press. |
| `AUTO` | Repeatedly while held. |
| `BURST` | A count per press. |
| `CHARGE` | Builds while held, fires on release. |
| `HOLD` | Every tick the button is down (beams, physics guns). |

Durations are counted in ticks. A definition that sets `authored_tick_rate` is scaled to the rate the arsenal runs at, so a weapon written for 64 Hz behaves the same on a 128 Hz server.

## Design rules

- **The script is a path, not a `class_name`.** A dot-cloud pack mounted at runtime does not register its `class_name` globals, so naming by path is what lets downloaded content bring its own weapons.
- **A behaviour decides that a use happened, never what it hit.** It returns a `DotWeaponOutcome`; dot-combat resolves shots against the world at the tick the trigger was pulled, so a client can predict and the server decide.
- **Behaviours are pure functions of the context**: an origin and direction, a tick, an entity id. Scatter comes from a hash of shooter, tick, use index and pellet index rather than a random stream, so a predicted use matches the server's.
- **Ammunition is pooled by name.** Weapons with the same ammo type share a reserve. A pickup returns how many rounds fitted.

## Bridges

| Bridge | What it does |
| --- | --- |
| `DotWeaponPlayerBridge` | Builds a context from a dot-player: origin at the eye, direction along the view, a stable entity number, view model on the weapon mount, an arsenal from a class definition. |
| `DotWeaponLoadoutBridge` | Fills an arsenal from what dot-loadout resolved. |
| `DotWeaponInventoryBridge` | Keeps reserve ammunition matching the bag, which is the truth. |

All are duck-typed; none of those addons is imported.

```gdscript
var ctx := DotWeaponPlayerBridge.context_for(player, tick, index)
var outcome := arsenal.use(ctx)
```

## Attachments

A weapon lists its mount points. A `DotWeaponAttachment` names a mount and the numbers it scales or adds, and a `DotWeaponFitting` records what a player fitted. `arsenal.fit(slot, fitting)` gives that slot a modified copy of the definition, and `DotWeaponNetSync.fitting_specs()` replicates the choice. Both machines must share the attachment catalogue.

## Testing

Import the project once, then run `examples/weapon_selftest.tscn` headless with Godot.

## Status and licence

Part of the [Gamespice](https://gamespice.net) platform: a family of Godot addons. Written with Claude Code and maintained by `gamemann`. Every addon has headless tests, but little of this has been played by real users yet, so expect rough edges and please [open an issue](https://github.com/gamespice-platform/weapon/issues) when you hit one.

MIT licence, see [LICENSE](LICENSE). The only closed part of the [Gamespice](https://gamespice.net) platform is the web back end; you can use your own instead of Gamespice's.
