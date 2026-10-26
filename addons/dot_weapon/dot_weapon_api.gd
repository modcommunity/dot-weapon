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

## 3: [method DotWeaponCatalogue.follow_content] and [method DotWeaponCatalogue.unfollow_content]
## (weapons delivered by mounted content packs, session-aware), [DotWeaponListing] with
## [method DotWeaponCatalogue.listings], [method DotWeaponCatalogue.listing] and
## [method DotWeaponCatalogue.categories], the [signal DotWeaponCatalogue.weapon_added] and
## [signal DotWeaponCatalogue.listings_changed] signals, and the optional category and icon arguments of
## [method DotWeaponCatalogue.add]. Needs dot-core API 9 ([DotContentIndex]); OLDEST stays 1.

## 4: weapon attachments: [member DotWeaponDef.mounts], [DotWeaponAttachment],
## [DotWeaponFitting], [DotWeaponAttachments], [member DotWeaponArsenal.attachments] with
## [method DotWeaponArsenal.fit] and [method DotWeaponArsenal.fitting_at], and
## [method DotWeaponNetSync.fitting_specs]. OLDEST stays 1.

## 5: [DotWeaponProfiles], weapons as `weapon` profiles (dot-core [DotProfileSet]) with upgrade children.
## Needs dot-core API with DotProfileSet; OLDEST stays 1.

## 6: [DotWeaponProfileGroup] (every pack's weapon set behind the one `weapon` kind, one runtime layer),
## the optional `layer` of [method DotWeaponProfiles.make_set] and [method DotWeaponProfiles.refresh_def].
## OLDEST stays 1.

## 7: [method DotWeaponProfiles.profile_schemas]. OLDEST stays 1.

## 8: the overlay on code-built defs in [DotWeaponProfiles]: `overlay_set`, `tune`, `file_flat`, `apply_flat`,
## `flat_of`, `to_yaml`, `profile_path`, `upgraded`. OLDEST stays 1.

## 9: spawners (`spawner/`, docs/spawners.md): [DotWeaponSpawner], [DotWeaponSpawnView], [DotWeaponSpawnPool],
## [DotWeaponSpawnSite], [DotWeaponSpawnPoint], [DotWeaponSpawnerConfig]. OLDEST stays 1.

## 10: carry weight ([DotWeaponCarry], `DotWeaponDef.weight`, `weight` profile key; arsenal `carry`, `backpack_tier`,
## `cycle_slot`, `weapons_in`, `carried_weight`, `capacity`, `enforce_limit`). Off unless a game sets `carry`. OLDEST stays 1.

const LEVEL := 10
const OLDEST := 1
