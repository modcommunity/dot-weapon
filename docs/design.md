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

Ticks, but ticks at which rate? A pack is written once and runs on servers at 64, 128 or 60 Hz. `DotWeaponDef.authored_tick_rate` says which rate a row's counts were written at, and `DotWeaponArsenal.tick_rate` says which rate the simulation runs at; the arsenal scales every duration it reads (deploy, holster, use and burst interval, charge, reload, reload start, and an outcome's `cooldown_ticks`) through `ticks_for`, and a charge through `charge_for`. zee-dot-weapons and zed-dot-weapons set 64, so their weapons fire, reload and deploy in the same wall-clock time at 128 Hz as at 64.

Decisions, each with the alternative that was wrong:

- **Zero means unscaled, and it is the default.** Every row written before the field existed (game-g2gfast's own, written at 128 for a 128 Hz game) behaves exactly as before. A default of 64 would have halved g2gfast's cadence.
- **The rate is per definition, not per arsenal.** One arsenal can carry a game's own rows next to a pack's, written at different rates.
- **Scaled at read time, not by copying the definition on equip.** The catalogue's rows are shared, read-only objects (arena hands one catalogue to every player); a scaled copy per arsenal would be one more object per weapon per player and a second source of truth. Reading through `ticks_for` keeps the numbers integers, so a client and a server at one rate reach the same deadline.
- **Rounded, never to zero.** 4 ticks at 64 Hz is 3.75 at 60 and becomes 4; 1 tick at 64 Hz at 20 Hz is still 1, because 0 means "every tick" on an interval.
- **What leaves a behaviour is in running ticks.** A spawn's fuse and life go to the game, which counts in its own ticks, so the stock behaviours scale them (`scaled_ticks`); bloom recovery, applied once a tick, is scaled per tick (`scaled_per_tick`); a beam's ramp is compared with the arsenal's held count and is scaled too. An outcome's `cooldown_ticks` is the exception: it stands in for the definition's interval and goes back to the arsenal, which scales it, so a behaviour never converts it.
- **Both ends must agree on `tick_rate`.** Deadlines are absolute ticks and travel in the snapshot as ticks; a client predicting at another rate than its server predicts a different reload end. A game sets it from the rate its world runs at, which both ends already share.

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

## Attachments

A scope, a suppressor or a longer magazine is logic every game needs (which mount, which gun, what it changes, what a watcher must see), so it lives here and not in a weapons pack (which would be copied per pack) or in dot-loadout (which says what a player brought, not how a weapon's numbers change). A pack supplies the attachment rows and the models for the sockets named by each mount.

A `DotWeaponDef` lists its `mounts`; a `DotWeaponAttachment` names one mount, which weapons or tags it fits, and numbers to scale and add on the definition or its tuning (an unknown field is an error, not a silent skip). A `DotWeaponFitting` is ids only (mount to attachment id), so a content-less server validates, stores and replicates it against its `DotWeaponAttachments` catalogue.

**Applying copies.** `DotWeaponAttachments.apply` deep-duplicates the definition (tuning included) and mutates the copy; the catalogue's row is shared by every carrier and mutating it would fit everybody's rifle. An empty fitting returns the shared definition itself. `DotWeaponArsenal.fit` swaps the slot's definition for the copy and clamps the magazine.

**The wire is a packed index.** `encode` writes, per mount in text order, the 1-based position of the attachment among `choices_for(def)[mount]` (0 is none) in just enough bits; `FITTED_BITS` is 16 and a weapon needing more does not replicate its fitting. That makes **both machines share the same attachment catalogue**, as they share the weapon catalogue: differing catalogues decode the same bits into different attachments.

`DotWeaponNetSync.fitting_specs()` is separate from `specs()` because games register `specs()` on carriers that have no `net_fitted` property; adding a spec there would break their registration. `pull` and `push` touch `net_fitted` only when the object has it.

## Carry weight

`DotWeaponCarry` is one object a game shares between its arsenals (`arsenal.carry`); null or `enabled = false` is the old behaviour: no limit, one weapon per slot. Weight is `DotWeaponDef.weight` times `multiplier` times every modifier's factor; the limit is `base_limit` plus the backpack tier's bonus, scaled and shifted by the modifiers. A modifier is just a named source the game sets and clears (`set_modifier(&"box_x", weight_factor, limit_factor, limit_add)`), so no game-specific concept lives here.

`give` is refused with `CODE_QUOTA` when it would put the carrier over the limit (a swap for a lighter weapon is always allowed). A slot holds `slot_capacity` weapons: the one in hand and a shelf behind it; `cycle_slot` rotates them, and the snapshot carries the shelf and `backpack_tier`. Going over after a limit change is the game's choice: `speed_scale()` slows (SLOW) or `enforce_limit()` returns the ids it dropped (DROP); the arsenal never deletes in SLOW mode.
