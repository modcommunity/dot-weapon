# dot-weapon design

Why the addon is shaped the way it is. The one-line rules are in [CLAUDE.md](../CLAUDE.md).

## The one idea

**A weapon is a document that names a behaviour script by path.**

`DotWeaponDef` carries only what the arsenal's state machine needs: a slot, deploy and holster times, what counts as a use, what a use costs, and how it is reloaded. It says nothing about what a use *does*. That belongs to the `DotWeaponBehaviour` at `behaviour_path`.

Everything else follows from that line. A bow works because `Fire.CHARGE` accumulates draw and the behaviour decides what the draw is worth; the definition needs no `draw_strength` field, so adding a bow edits no file in this addon.

## Why it is not one fat resource

dot-combat's old `weapons/` folder was exactly that: a `DotWeapon` with `pellets`, `spread_bloom`, `projectile_gravity`, `splash_radius` and thirty more fields. It described the guns game-arena shipped very well, and it could not describe a bow. A bow's damage comes from how long it was drawn, there was no field for that, and adding one means editing the addon. A game that has to edit an addon to add a weapon has a fork rather than a dependency, and the whole point of this family is that nothing should require one.

Typed tuning is still available without a fat resource: `DotWeaponTuning` is a resource a game subclasses with its own `@export`s, and `DotWeaponBallistics` is the shipped one most of the stock behaviours read. `DotWeaponDef.params` (an untyped dictionary) exists for weapons delivered inside a content pack, which cannot register a `class_name`; a field present in both wins from `tuning`.

## The three objects

| | |
| --- | --- |
| `DotWeaponContext` | What a behaviour is told about one use, and nothing it could cheat with. An origin and a direction, not a camera. A tick, not a clock. An entity id, not a node. |
| `DotWeaponBehaviour` | What a use does. Overridable hooks (`_use`, `_release`, `_tick`, `_can_use`, `_deploy`, `_holster`, `_reloaded`, `_setup`), each defaulting to nothing, so a behaviour that only shoots overrides exactly one. |
| `DotWeaponOutcome` | What the use produced. `DotShot`s for dot-combat to resolve, `DotWeaponSpawn`s for the game to put in the world, and free-form events for anything else. |

## Four rules for a behaviour, and they all break quietly

**1. Be a pure function of the context.** A predicted use is simulated at least twice and once more per reconciliation replay. A behaviour that reads a wall clock, a node, an input device or a random stream gives a different answer on each run, nothing errors, and the symptom is "hit registration feels bad".

**2. Apply nothing.** Return an outcome. A behaviour that reached into a `DotHealth` is a client deciding who dies.

**3. Keep state in `state`, not in a member.** The arsenal serialises `state` across the wire and restores it on a correction. A field written on the behaviour survives neither, and a bow whose draw is in a member silently un-draws itself on the first correction.

**4. Check `ctx.replayed` before anything visible.** The simulation must re-run; a sound, an effect and a statistic must not.

## Ticks, never seconds

Every duration on a definition is in ticks. A weapon measured in seconds fires at two different rates on a 64 Hz server and a 128 Hz one, which is two different games. A game that tunes in rounds per minute converts once, in its own content file.

`DotWeaponArsenal.tick_rate` (default 64) is documented as being for callers that think in seconds, but nothing in the addon reads it, and nothing scales a definition by the server's tick rate. A pack authored at 64 Hz (zee-dot-weapons) therefore fires at a different real-time rate on a 128 Hz server. That is open, not settled: see the open item in [CLAUDE.md](../CLAUDE.md#open-items).

## The order in `_try_use` is load-bearing

**Ask whether the weapon can pay BEFORE cancelling a reload.** Using a weapon cancels a reload, which is what every shooter does; but in the other order a held trigger on an empty weapon cancels the reload it started on the previous cadence tick, every time the cadence comes round, so the reload restarts for ever and the magazine never refills. The story is in [history](history.md#the-reload-that-restarted-for-ever).

## `select()` refuses the slot a switch is already heading to

`DotWeaponCommand.slot` says "zero means no change", and a networked game naturally carries the slot it wants on every tick anyway, because that is what survives a lost packet. During a switch the old slot is still current, so a `select()` that only refused the current slot restarted the holster on every repeat and the switch never finished. See [history](history.md#a-slot-asked-for-every-tick-never-arrived).

## Spread lives in dot-combat, not here

Behaviours set `DotShot.spread`; dot-combat's `DotShot.scatter()` turns it into pellet directions with `DotSpread`. Moving `DotSpread` alongside the weapons would have put the same integer hash in two addons, which is the duplication this family guards hardest against. Scatter is a property of a shot, and a shot is dot-combat's.

`DotWeaponRecoil` does live here, because recoil is weapon feel rather than hit resolution. `kick()` takes floats rather than a weapon, which is what lets a behaviour compute a kick from the charge it was held at.

## `DotShot` describes itself

The split from dot-combat was possible because `DotShot` stopped pointing at a weapon. The resolver used to read `shot.weapon.damage`, `shot.weapon.max_range` and `shot.weapon.delivery`, which made "what dot-combat can resolve" the same question as "what that one resource can describe". It now carries the numbers the resolver needs, so a trap, a turret or an environmental hazard can produce one with no weapon anywhere near it.

`DotCombatNetSync` carries health; `DotWeaponNetSync` carries the slot, magazine and reserve. A game using both concatenates the two spec lists. Ammunition is owner-only, because exact counts are information an opponent should not have.

## Optional neighbours are duck-typed

dot-net, dot-loadout, dot-inventory and dot-player are not dependencies, and no script here names one of their classes: a script that mentions a `class_name` the project does not have fails to parse and takes every script referencing it down with it. So `DotWeaponCommand.write()` takes its writer as `Variant`, `DotWeaponNetSync` only describes specs and leaves the bridge to the host game, and the three bridges are duck-typed:

- `DotWeaponLoadoutBridge` fills an arsenal from a resolved dot-loadout (`[slot, item]` pairs); it is the item-to-weapon table every game that adopted both had written by hand.
- `DotWeaponInventoryBridge` keeps reserve ammunition and a bag agreeing. The bag is the truth and the arsenal is a view of it; the other direction creates ammunition.
- `DotWeaponPlayerBridge` fills a `DotWeaponContext` from a player (eye origin, camera direction, stable entity number, a view-model mount).

## The extension point is tested

`fixtures/lightning_rod.gd` is a weapon this addon knows nothing about, written the way a game would write one. It chains to several targets, costs more the further it chains, sets its own cadence and refuses to fire indoors, and none of those ideas appear anywhere in the addon. If a refactor ever breaks the extension point, the suite's "extension point" section is what says so.
