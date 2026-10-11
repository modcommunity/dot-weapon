extends RefCounted

## dot-weapon's API level. The rule for bumping it is on [DotAddonApi].
##
## LEVEL rises by one for anything a game could call that did not exist before. OLDEST is
## raised to LEVEL when something a game could have called is removed or changes meaning,
## because every pack built before that no longer compiles against this addon.
##
## 2: [member DotWeaponDef.authored_tick_rate] with [method DotWeaponDef.ticks_at],
## [method DotWeaponDef.per_tick_at] and [method DotWeaponDef.scales_at];
## [method DotWeaponArsenal.ticks_for] and [method DotWeaponArsenal.charge_for];
## [method DotWeaponBehaviour.scaled_ticks], [method DotWeaponBehaviour.scaled_per_tick]
## and [method DotWeaponBehaviour.running_tick_rate]. A pack whose definitions set the
## rate fails to compile on a host built before it. OLDEST stays 1: a definition that
## names no rate behaves exactly as before.

const LEVEL := 2
const OLDEST := 1
