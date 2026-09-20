This is the **weapon** asset for TMC's **Dot** collection. It adds what a player holds and uses, as a catalogue of documents that name a behaviour script by path: guns, bows, melee, thrown charges, beams, and anything a game writes that none of those describe.

This collection of assets provides modular building blocks for creating games and applications within the TMC ecosystem, ensuring consistency and interoperability across all `dot-*` assets. This includes core functionality, networking, authentication, cloud integration, and more.

**These assets are COMPLETELY OPEN SOURCE**. You are free to use, modify, and distribute them under the terms of the MIT license. The only thing not open source is the back-end web infrastructure. So if you opt into using your own authentication backend instead of integrating with TMC, you will need to build and integrate your own back-end infrastructure.

## From Maintainer & WARNING
This asset, along with all the others, was built initially with **Claude Code** and will continue to be maintained and extended using it. This is because I (`gamemann`) cannot build the entire TMC platform alone (I wish I could lol).

**Please treat this as partially tested.** Every asset has its own headless test suite and those suites pass, but very little of this has been in front of real players yet. Expect rough edges, and please report anything you run into.

I intend on reviewing code, testing, and editing documentation regularly. If you're interested in helping out, please let me know!

## Nothing here should ever require a fork

A game adds a weapon by writing a script, pointing a definition at its path, and adding a row to a table. It does not subclass the arsenal, it does not edit an enum in this addon, and it does not need this addon to have anticipated what it is building.

That is the whole design, and the thing it replaces is the reason it exists. A weapon used to be one resource carrying every field any weapon might want: pellets, spread bloom, projectile gravity, splash radius. That describes nine kinds of gun very well and cannot describe a bow at all, because a bow's damage comes from how long it was drawn and there is no field for that. Adding one means editing the addon, and a game that edits an addon to add a weapon has a fork rather than a dependency.

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

## A bow is a row in a table, not a class

The definition says the fire mode is `CHARGE` and the arsenal accumulates the draw. The behaviour reads `ctx.charge` and decides what it is worth. There is no bow class, no draw field on the definition, and no branch anywhere in the arsenal that knows a bow exists. A crossbow is the same row with `SEMI` and a reload, and a railgun is the same row with a different behaviour.

Five fire modes cover the state machine, and they are about *when* a use happens rather than what it does: `SEMI` fires on the press, `AUTO` repeats while held, `BURST` fires a count per press, `CHARGE` builds while held and fires on release, and `HOLD` runs every tick the button is down. A beam and a physics gun are both `HOLD`; that they do entirely different things is the behaviour's half.

## It bridges to dot-player without depending on it

`DotWeaponPlayerBridge` is the fourth duck-typed bridge in this addon, beside the ones to dot-loadout and dot-inventory, and it removes the twenty lines every game wrote by hand:

```gdscript
var ctx := DotWeaponPlayerBridge.context_for(player, tick, index)
var outcome := arsenal.use(ctx)
```

The origin is the **eye**, not the body — a shot fired from a capsule's origin comes out of the player's knees. The direction is where the **view** is pointing, not where the body faces — a shot aimed along the body comes out sideways whenever the player is looking anywhere but straight ahead. Both are bugs that present as bad hit registration, which is where they get debugged.

It also converts a player key into the stable `entity` number dot-weapon puts on the wire, attaches a view model to a character's weapon mount when there is one, and fills an arsenal from a dot-player-class definition. None of dot-player, dot-player-char or dot-player-class is named anywhere in it.

## The script is a path, never a `class_name`

A game delivered as a dot-cloud content pack is mounted at runtime, and **a mounted pack's `class_name` globals are not registered in the host**. A weapon named by class could therefore only ever ship inside the build. Naming it by path is what lets downloaded content bring its own weapons, and it is the same rule dot-props names a prop's script by.

## It decides that a use happened. It never decides what it hit

A behaviour returns a `DotWeaponOutcome` and applies nothing. dot-combat resolves the shots against a world rewound to the tick the trigger was pulled on, and the game spawns the spawns. The split is what lets the owning client predict a use and the server resolve it authoritatively from the same inputs, and collapsing it gives you a client that decides who dies.

## Everything is a pure function of the context

A behaviour is handed an origin and a direction, not a camera; a tick, not a clock; an entity id, not a node. The same weapon then runs on a predicting client, on a resolving server, in a reconciliation replay, for a bot with no viewport and in a headless suite.

That matters most for anything that scatters. A predicted use is simulated at least twice and once more for every replay after a correction, so anything drawing from a random stream produces a different pattern each time. The client sees pellets go one way, the server resolves them going another, nothing errors, and the report you get is that hit registration "feels bad". Scatter comes from a hash of the shooter, the tick, the use index and the pellet index instead.

## Ammunition is pooled by name

Two weapons declaring the same ammo type draw from one reserve, which is what lets a pistol and a carbine share a box of rounds and one quiver serve two bows. A weapon that wants a private reserve declares a type nobody else uses and gets the per-weapon behaviour back with no special case. A pickup returns how many rounds actually fitted, because a caller that assumed it all went in creates ammunition.

## Using it

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

## Loadouts and bags

`DotWeaponLoadoutBridge` fills an arsenal from what [dot-loadout](https://github.com/modcommunity/dot-loadout) resolved, and `DotWeaponInventoryBridge` keeps reserve ammunition agreeing with what [dot-inventory](https://github.com/modcommunity/dot-inventory) says is in the bag. Neither is a dependency and neither is named in the code: both are duck-typed, so this addon installs and runs without either.

The bag is the truth and the arsenal is a view of it. The other direction creates ammunition, because a player who drops a magazine, reloads and picks it back up then has more rounds than they started with.

## Installing

Copy `addons/dot_weapon/`, [`dot-core`](https://github.com/modcommunity/dot-core)'s `addons/dot_core/` and [`dot-combat`](https://github.com/modcommunity/dot-combat)'s `addons/dot_combat/` into your project and enable dot-weapon in **Project → Project Settings → Plugins**.

## Dependencies

[dot-core](https://github.com/modcommunity/dot-core) and [dot-combat](https://github.com/modcommunity/dot-combat). Nothing else. dot-loadout and dot-inventory are both optional and both reached without being named.

## Licence

MIT. See [LICENSE](LICENSE).
