# DCS Mission Maker

A web app that generates ready-to-fly multiplayer `.miz` missions for DCS World from a map, a mission type and the aircraft the group wants to fly.

## Language

**Mission**:
One generated `.miz` file together with its saved settings, briefing and kneeboards.
_Avoid_: Scenario, map, file

**Mission Type**:
The kind of tasking a Mission is built around (CAP, CAS, SEAD/DEAD, Precision Strike, Anti-Ship, CSAR, Training Range).
_Avoid_: Mode, scenario type

**Training Range**:
A Mission Type for open-ended practice on a dedicated server, where players choose what enemy forces exist while the Mission is running instead of the generator fixing them in advance. With nothing spawned it is an empty sky for free flying.
_Avoid_: Free Flight, training mission, sandbox

### Training Range

**Range Guide**:
The briefing material for a Training Range: one section and kneeboard page per Range Area saying what it is for, what can be spawned there and how, and where its Practice Targets are.
_Avoid_: Range briefing, area card

**Range Session**:
The stretch of play between two Mission Reloads; Debrief results and bomb and strafe scores cover one Range Session and start fresh with the next.
_Avoid_: Round, run, server session

**Default Roster**:
The curated set of popular player aircraft a Training Range starts with, two 2-ship flights per type (one hot start, one cold start), which the user can edit before generating.
_Avoid_: Preset, loadout, all-aircraft list

**Flight Role**:
The kind of practice a player flight in a Training Range is set up and loaded for (e.g. SEAD, CAS, Air-to-Air), shown in its slot name; the two flights of a type in the Default Roster usually have different roles.
_Avoid_: Tasking, mission, loadout

**Range Area**:
A named, fixed zone in a Training Range set aside for one kind of practice (SEAD/DEAD, CAS, Strike, Air-to-Air, Anti-Ship, Helicopter), where forces can be spawned from the F10 menu. SEAD and DEAD share one area: the targets are the same and only the pilot's intent differs. A WWII or Korea Training Range has its own set of areas and Spawn Roles for that era, with Flak / Ground Attack in place of SEAD/DEAD and no JTAC.
_Avoid_: Range, zone, box

**Practice Target**:
A permanent target that doesn't shoot back, present in a Range Area from mission start (e.g. bombing circle, strafe pit, target vehicles, target buildings), which comes back on its own after being destroyed. It is not a Spawnable.
_Avoid_: Dummy, inert target, static target

**Spawnable**:
One entry in the spawn menu that places a single group of enemy units or statics (e.g. an SA-6 site, an armour column, a fighter pair, a building target).
_Avoid_: Package (a DCS package is a set of cooperating flights), template, preset

**Spawn Role**:
A generic category of Spawnable (e.g. Medium SAM, SHORAD, Armour Column, Fighter Pair) that offers a default system matched to the Mission's era plus specific systems from any era from Vietnam to Modern; each Range Area offers only the roles that suit its kind of practice.
_Avoid_: Category, type, class

**Leash**:
The rule that spawned enemy aircraft only engage targets in or near their own Range Area (or, for a Marker Spawn, near their marker) and return to it instead of chasing beyond it.
_Avoid_: Tether, boundary

**Repeating Spawn**:
A Spawnable that spawns again a short time after it is destroyed, until an Area Clear; the alternative to spawning once. Offered for enemy aircraft and for ground columns in the CAS and Helicopter areas, never for air defences.
_Avoid_: Respawn, infinite, loop

**Area Difficulty**:
The Easy / Normal / Hard level a Range Area currently applies to everything spawned in it afterwards; set in the builder, changeable in game from the F10 menu. On Hard, air defences spawned in the SEAD/DEAD area work together as one integrated network; on Easy and Normal each stands alone.
_Avoid_: Skill, level, mission difficulty

**Marker Spawn**:
Spawning one of the Spawn Role systems at an F10 map marker whose text is a spawn command, anywhere on the map, outside any Range Area. Only Range Admins may do it; it defaults to Normal difficulty and counts only against the server-wide caps.
_Avoid_: Free spawn, custom spawn

**Range Admin**:
Whoever is seated in the Range Control flight; the only player who may use Marker Spawn, Range Reset and Mission Reload.
_Avoid_: Game Master, moderator, server admin

**Range Control**:
A dedicated friendly player flight of a few common types whose seats carry the Range Admin menu; anyone may take a seat unless the server hook is installed, in which case a password is required first.
_Avoid_: Admin slot, Game Master slot

**Area Clear**:
Removing everything spawned in one Range Area and restoring its Practice Targets; any player may do it.
_Avoid_: Reset, despawn

**Range Reset**:
Removing everything spawned across the whole Training Range while players stay in their aircraft; only Range Admins may do it.
_Avoid_: Restart, clear all

**Mission Reload**:
Loading the Mission again from scratch so every player returns to slot selection; done by a Range Admin or automatically on a schedule when the server is empty.
_Avoid_: Restart, reboot
