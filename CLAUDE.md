# dot-weapon

What a player holds and uses. A weapon is a document (`DotWeaponDef`) that names a behaviour script by path; the arsenal runs slots, cadence, ammunition and reloads, and the behaviour decides what a use does, returning shots for dot-combat and spawns for the game.

Read the family [CLAUDE.md](../../CLAUDE.md) first.

**The distributable is `addons/dot_weapon/`.** It requires [dot-core](../dot-core) and [dot-combat](../dot-combat) (symlinked into `addons/`, gitignored). dot-net, dot-loadout, dot-inventory and dot-player are optional and never named.

## Read before

| Read | Before |
| --- | --- |
| [docs/design.md](docs/design.md) | changing anything: why a definition plus a behaviour, the four behaviour rules, ticks, the `_try_use` order, `select()`, spread and recoil, `DotShot`, the duck-typed bridges |
| [docs/history.md](docs/history.md) | the dot-combat split, and the two bugs that left rules here |

## Layout

| Path | What |
| --- | --- |
| `core/dot_weapon_def.gd` | `DotWeaponDef`: `authored_tick_rate`, slot, deploy/holster ticks, `Fire` mode, cost, reload, `behaviour_path`, `params`, `tuning` |
| `dot_weapon_api.gd` | the API level ([DotAddonApi](../dot-core/addons/dot_core/core/dot_addon_api.gd)); 2 = `authored_tick_rate` and the scaling helpers; 3 = `follow_content` and the menu listings |
| `core/` (rest) | `DotWeaponCatalogue` (code weapons plus `follow_content(index)` for weapons delivered by mounted packs, session-aware), `DotWeaponListing` (a menu row), `DotWeaponCommand` (the per-tick input), `DotWeaponContext`, `DotWeaponOutcome`, `DotWeaponSpawn`, `DotWeaponSlot`, `DotWeaponAmmo` |
| `behaviour/` | `DotWeaponBehaviour` (the extension point) and the stock `DotWeaponHitscan`, `DotWeaponProjectile`, `DotWeaponMelee`, `DotWeaponBeam`, `DotWeaponThrown` |
| `tuning/` | `DotWeaponTuning` (subclass for typed fields) and `DotWeaponBallistics` (what the gun-like behaviours read) |
| `runtime/dot_weapon_arsenal.gd` | `DotWeaponArsenal`: the state machine; `select`, `use`, `begin_reload`, snapshots |
| `core/dot_weapon_attachment.gd`, `dot_weapon_fitting.gd`, `dot_weapon_attachments.gd` | attachments: a mod (`DotWeaponAttachment`), what is fitted to one gun as ids (`DotWeaponFitting`), the catalogue with fit rules, copy-on-apply and the packed wire code (`DotWeaponAttachments`); `arsenal.fit` uses them (API 4) |
| `net/dot_weapon_net_sync.gd` | `DotWeaponNetSync`: slot, magazine, reserve specs (ammunition owner-only) |
| `math/dot_weapon_recoil.gd` | `DotWeaponRecoil` |
| `bridge/` | `DotWeaponLoadoutBridge` (dot-loadout to arsenal), `DotWeaponInventoryBridge` (bag to reserve), `DotWeaponPlayerBridge` (player to context, view-model mount) |
| `examples/weapon_selftest.tscn` | the suite; `fixtures/lightning_rod.gd` is the outside weapon it proves the extension point with |

Paths except `examples/` and `fixtures/` are in `addons/dot_weapon/`.

## Running and testing

The family's two steps ([game-dev/CLAUDE.md](../../CLAUDE.md#validating-anything)), then `timeout 180 godot --headless --path . res://examples/weapon_selftest.tscn`.

## Rules that bite

- Adding a weapon edits nothing here: a script extending `DotWeaponBehaviour`, a `DotWeaponDef` naming it by path, a catalogue row. [design](docs/design.md#the-one-idea)
- A behaviour is a pure function of the context: no clock, node, input device or random stream. [design](docs/design.md#four-rules-for-a-behaviour-and-they-all-break-quietly)
- A behaviour applies nothing; it returns a `DotWeaponOutcome`. [design](docs/design.md#four-rules-for-a-behaviour-and-they-all-break-quietly)
- Behaviour state lives in `state`, never a member, or a correction loses it. [design](docs/design.md#four-rules-for-a-behaviour-and-they-all-break-quietly)
- Check `ctx.replayed` before any sound, effect or statistic. [design](docs/design.md#four-rules-for-a-behaviour-and-they-all-break-quietly)
- Every duration on a definition is in ticks, at `authored_tick_rate` when set (0 = the running rate, unscaled); the arsenal reads them only through `ticks_for`/`charge_for`, a behaviour through `scaled_ticks`/`scaled_per_tick`. [design](docs/design.md#ticks-never-seconds)
- `DotWeaponOutcome.cooldown_ticks` is in the definition's ticks (the arsenal scales it); a `DotWeaponSpawn`'s fuse and life are in running ticks (the behaviour scales them). [design](docs/design.md#ticks-never-seconds)
- Client and server arsenals must share `tick_rate`; deadlines are absolute ticks in the snapshot. [design](docs/design.md#ticks-never-seconds)
- In `_try_use`, ask whether the weapon can pay before cancelling a reload. [design](docs/design.md#the-order-in-_try_use-is-load-bearing)
- `select()` refuses the slot a switch is already heading to; a game may send its slot every tick. [design](docs/design.md#select-refuses-the-slot-a-switch-is-already-heading-to)
- `DotSpread` stays in dot-combat; behaviours set `DotShot.spread`. [design](docs/design.md#spread-lives-in-dot-combat-not-here)
- Never name a class from dot-net, dot-loadout, dot-inventory or dot-player: duck-type it (a writer is `Variant`), or the script fails to parse where that addon is absent. [design](docs/design.md#optional-neighbours-are-duck-typed)
- `DotWeaponCatalogue.ids()` and `DotWeaponAmmo.pools()` are in text order: sort StringNames with `String(a) < String(b)`, never `sort()` (interning order, differs per process). The suite's id-order section is armed against it. [gdscript-hazards](../../docs/gdscript-hazards.md)
- Attachments apply to a deep copy of the definition, never the catalogue's row; both machines must share the attachment catalogue (the wire carries indices into it). [design](docs/design.md#attachments)
- The suite's extension-point section (`fixtures/lightning_rod.gd`) must keep passing. [design](docs/design.md#the-extension-point-is-tested)

## Consumers

game-arena and game-g2gfast use it directly. game-playground, game-zombie-zone, mg-deathrun, mg-prop-hunt, mg-smash-copter and mg-wipeout use it through zee-dot-weapons (zed-dot-weapons sits on top of zee). game-playground's prop tools (`DotPropTool` subclasses) are not weapons in this sense.
