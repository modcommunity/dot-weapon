# dot-weapon history

Bug stories worth keeping because the bug could come back. The rules they left are in [CLAUDE.md](../CLAUDE.md) and [design.md](design.md).

## Split out of dot-combat

dot-combat lost `weapons/` entirely. `DotWeapon`, `DotArsenal`, `DotWeaponState`, `DotRecoil` and `DotCombatCommand` are gone; `DotSpread` moved to dot-combat's `core/`; `DotShot` stayed and stopped pointing at a weapon. A name from that list in a game or doc is a leftover.

## The reload that restarted for ever

The order "cancel the reload, then ask whether the weapon can pay" was shipped and looked correct. A held trigger on an empty weapon then cancelled the reload it had started on the previous cadence tick, every time the cadence came round, so the weapon simply stopped working. Nothing errored; the only symptom was that arena's bots scored a fraction of their usual kills. Every reload test released the trigger first, which is why nothing caught it; `_test_reloading` now holds it.

## A slot asked for every tick never arrived

Fixed 2026-10-08. mg-deathrun, mg-wipeout and mg-smash-copter all sent the wanted slot on every tick, on both the server and the client's view rig. `select()` refused only a slot already current, and during a switch the old slot still is, so every repeat restarted the holster with a deadline one tick later and the switch never finished: the old weapon stayed in hand for good and nothing could be fired. It surfaced as a render of a runner holding the spade they were given first, under "You were handed a marksman". `weapon_selftest`'s "carrying and switching" now asks for slot 2 forty ticks running and expects it to arrive.
