# dot-weapon

What a player holds and uses. Read `../../CLAUDE.md` first for the family-wide rules; this file is only what is specific to weapons.

## The one idea

**A weapon is a document that names a behaviour script by path.**

`DotWeaponDef` carries only what the arsenal's state machine needs: a slot, deploy and holster times, what counts as a use, what a use costs, and how it is reloaded. It says nothing about what a use *does*. That belongs to the `DotWeaponBehaviour` at `behaviour_path`.

Everything else follows from that line. A bow works because `Fire.CHARGE` accumulates draw and the behaviour decides what the draw is worth; the definition needs no `draw_strength` field, so adding a bow edits no file in this addon.

## Why it is not one fat resource

This addon replaces dot-combat's `weapons/` folder, which was exactly that: a `DotWeapon` with `pellets`, `spread_bloom`, `projectile_gravity`, `splash_radius` and thirty more fields. It described the four guns game-arena ships very well.

It could not describe a bow. A bow's damage comes from how long it was drawn, there was no field for that, and adding one means editing the addon. A game that has to edit an addon to add a weapon has a fork rather than a dependency, and the whole point of this family is that nothing should require one.

## The three objects

| | |
| --- | --- |
| `DotWeaponContext` | What a behaviour is told about one use, and nothing it could cheat with. An origin and a direction, not a camera. A tick, not a clock. An entity id, not a node. |
| `DotWeaponBehaviour` | What a use does. Four overridable hooks and a default that does nothing, so a behaviour that only shoots overrides exactly one. |
| `DotWeaponOutcome` | What the use produced. `DotShot`s for dot-combat to resolve, `DotWeaponSpawn`s for the game to put in the world, and free-form events for anything else. |

## Four rules for a behaviour, and they all break quietly

**1. Be a pure function of the context.** A predicted use is simulated at least twice and once more per reconciliation replay. A behaviour that reads a wall clock, a node, an input device or a random stream gives a different answer on each run, nothing errors, and the symptom is "hit registration feels bad".

**2. Apply nothing.** Return an outcome. A behaviour that reached into a `DotHealth` is a client deciding who dies.

**3. Keep state in `state`, not in a member.** The arsenal serialises `state` across the wire and restores it on a correction. A field written on the behaviour survives neither, and a bow whose draw is in a member silently un-draws itself on the first correction.

**4. Check `ctx.replayed` before anything visible.** The simulation must re-run; a sound, an effect and a statistic must not.

## Ticks, never seconds

Every duration on a definition is in ticks. A weapon measured in seconds fires at two different rates on a 64 Hz server and a 128 Hz one, which is two different games. A game that tunes in rounds per minute converts once, at the top of its own content file, the way `ArenaContent.rpm_ticks` does.

## The order in `_try_use` is load-bearing

**Ask whether the weapon can pay BEFORE cancelling a reload.** The other order was shipped and it looked correct: using a weapon cancels a reload, which is what every shooter does. But a held trigger on an empty weapon then cancels the reload it started on the previous cadence tick, every time the cadence comes round, so the reload restarts for ever and the magazine never refills.

Nothing errored. The weapon simply stopped working, and the only symptom was that arena's bots scored five kills in ninety seconds instead of eighteen. Every reload test in the suite released the trigger first, which is why nothing caught it; `_test_reloading` now holds it.

## Spread lives in dot-combat, not here

`DotSpread` stays in dot-combat, and behaviours here call it. It was tempting to move it alongside the weapons, and that would have put the same integer hash in two addons, which is the duplication this family guards hardest against. Scatter is a property of a shot, and a shot is dot-combat's.

`DotWeaponRecoil` does live here, because recoil is weapon feel rather than hit resolution. It takes three floats rather than a weapon, which is what lets a behaviour compute a kick from the charge it was held at.

## What moved, and what it cost

dot-combat lost `weapons/` entirely. `DotWeapon`, `DotArsenal`, `DotWeaponState`, `DotRecoil` and `DotCombatCommand` are gone; `DotSpread` moved to `core/`; `DotShot` stayed and stopped pointing at a weapon.

**`DotShot` describing itself is the change that made the split possible.** The manager used to read `shot.weapon.damage`, `shot.weapon.max_range` and `shot.weapon.delivery`, which made "what dot-combat can resolve" the same question as "what that one resource can describe". It now carries the six numbers the resolver needs, so a trap, a turret or an environmental hazard can produce one with no weapon anywhere near it.

`DotCombatNetSync` lost the slot, the magazine and the reserve to `DotWeaponNetSync`. A game using both concatenates the two spec lists; a game with health and no weapons replicates three properties instead of six.

## Consumers

game-arena and game-g2gfast both run on this. game-playground deliberately does not: its weapons are `DotPropTool` subclasses that grab, shove and remove props, they contain no damage or health reference at all, and they are not weapons in this addon's sense.

## Validating

```bash
godot --headless --path . --import
find . -name '*.gd' -not -path './.godot/*' | while read f; do
    godot --headless --path . --check-only --script "res://${f#./}"
done
timeout 180 godot --headless --path . res://examples/weapon_selftest.tscn
```

17 sections, 157 checks. The one that matters most is the last: `fixtures/lightning_rod.gd` is a weapon this addon knows nothing about, written the way a game would write one. It chains to several targets, costs more the further it chains, sets its own cadence and refuses to fire indoors, and none of those ideas appear anywhere in the addon. If a refactor ever breaks the extension point, that section is what says so.
