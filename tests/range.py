"""Training Range checks: catalogue, area placement, templates vs config, legacy setups.

Run inside the image:  python -m tests.range
The Lua runtime has its own tests: lua5.1 tests/lua/test_training_range.lua
"""
import io
import re
import sys
import zipfile

from app import range_catalog as rc
from app.generator import MissionRequest, generate_full
from app.generator.range import MIN_SEPARATION_M, place_areas
from app.theaters import THEATERS

fails = []


def check(cond, what):
    if not cond:
        fails.append(what)
        print("FAIL", what)


def build(req):
    out = generate_full(MissionRequest.from_json(req))
    z = zipfile.ZipFile(io.BytesIO(out["data"]))
    config = next(z.read(n).decode() for n in z.namelist() if n.endswith("dmm_range_config.lua"))
    return out, z.read("mission").decode(), config


# 1. Every F10 menu level fits, every listed system exists, every era has defaults.
check(rc.check_menus() == [], f"menus: {rc.check_menus()}")
for (era, side), defaults in rc.ERA_DEFAULTS.items():
    roles = rc.roles_for(era)
    for rid, sid in defaults.items():
        check(rid in roles and sid in roles[rid].systems[side], f"default {era}/{side} {rid}={sid}")

# 2. Placement: on every map and era group, areas are apart and Anti-Ship only with sea.
for key, t in THEATERS.items():
    terrain = t.terrain_cls()
    for era in ("modern", "ww2"):
        layout = place_areas(t, terrain, t.default_blue, t.default_red, era)
        ids = [p.area.id for p in layout.areas]
        check(("antiship" in ids) == bool(t.red_sea), f"{key} {era}: antiship only with sea")
        check(layout.heli_base in t.blue_bases, f"{key}: helicopter base is friendly")
        ground = [p for p in layout.areas if p.area.placement in ("ground", "heli")]
        for i, a in enumerate(ground):
            for b in ground[i + 1:]:
                d = a.pos.distance_to_point(b.pos)
                # Small maps (Marianas) may run out of separate spots; report, don't hide.
                if d < MIN_SEPARATION_M:
                    print(f"note: {key} {era}: {a.area.id} and {b.area.id} only {d / 1000:.0f} km apart")

# 2b. Hand-picked maps (the ones the group flies most): areas well apart, helicopters close.
for key in ("caucasus", "marianas"):
    t = THEATERS[key]
    terrain = t.terrain_cls()
    for home in t.blue_bases:
        layout = place_areas(t, terrain, home, t.default_red, "modern")
        check(layout.heli_base == t.range_heli_base, f"{key}: hand-picked helicopter base")
        heli = layout.get("heli").pos.distance_to_point(terrain.airports[layout.heli_base].position)
        check(heli / 1852 <= 15, f"{key}: Helicopter area {heli / 1852:.0f} nm from its base")
        ground = [p for p in layout.areas if p.area.placement in ("ground", "heli")]
        for i, a in enumerate(ground):
            for b in ground[i + 1:]:
                check(a.pos.distance_to_point(b.pos) >= MIN_SEPARATION_M,
                      f"{key}: {a.area.id} and {b.area.id} apart")
        check(not any(p.moved for p in layout.areas), f"{key}: hand-picked areas aren't 'moved'")

# 3. The full Default Roster builds, and every template the config names is in the mission.
for key in ("caucasus", "marianas", "persiangulf", "syria", "nevada", "germany"):
    t = THEATERS[key]
    req = {"theater": key, "mission_type": "range",
           "flights": rc.default_roster(t.blue_carrier is not None)}
    out, mission, config = build(req)
    templates = set(re.findall(r'"(TR_TPL [^"]+)"', config))
    check(templates, f"{key}: config names templates")
    for tpl in templates:
        check(f'["name"]="{tpl}"' in mission, f"{key}: template {tpl} in mission")
    for p in re.findall(r'name = "(TR_PT [^"]+)"', config):
        check(f'["name"]="{p}"' in mission, f"{key}: practice target {p} in mission")
    check("DMM_RANGE = {" in config and 'flags = {' in config, f"{key}: config shape")
    flights = out["brief"]["flights"]
    check(len(flights) == len(req["flights"]), f"{key}: all {len(req['flights'])} flights built")
    names = " ".join(f["name"] for f in flights)
    check(out["brief"]["range"] and len(out["brief"]["range"]) >= 5, f"{key}: Range Areas in brief")
    check(out["brief"]["objectives"] == [], f"{key}: no fixed objectives")
    possible = [e for e in out["brief"]["oob"] if e["possible"]]
    check(len(possible) >= 10, f"{key}: Threat ID lists possible spawns ({len(possible)})")
    check(" - SEAD" in mission and " - Air-to-Air" in mission, f"{key}: Flight Role in slot names")
    z = zipfile.ZipFile(io.BytesIO(out["data"]))
    types = {n.split("/")[1] for n in z.namelist() if n.startswith("KNEEBOARD/")}
    control_types = {f["type"] for f in flights if f.get("flight_role") == "control"}
    check(len(control_types) == len(rc.RANGE_CONTROL_ROSTER), f"{key}: Range Control flights built")
    for t_id in types:
        guide = [n for n in z.namelist() if f"KNEEBOARD/{t_id}/" in n and "kneeboard_range_" in n]
        extra = 1 if t_id in control_types else 0
        check(len(guide) == len(out["brief"]["range"]) + 1 + extra, f"{key}: {t_id} has the Range Guide pages")
        check(any("kneeboard_range_control" in n for n in guide) == bool(extra),
              f"{key}: Range Control page only for Range Control types")
    control = re.findall(r'"([^"]+ - Range Control)"', config)
    check(len(control) == len(rc.RANGE_CONTROL_ROSTER), f"{key}: config lists Range Control groups {control}")
    for g in control:
        check(f'["name"]="{g}"' in mission, f"{key}: Range Control group {g} in mission")
    check("reload_countdown = 60" in config and "marker = {" in config, f"{key}: config has reload and marker")
    check([k["label"] for k in out["brief"]["range_kneeboards"]][0] == "Guide", f"{key}: guide labels")
    check(any("JTAC Darknight" in s for s in out["brief"]["support"]), f"{key}: Helicopter-area JTAC")
    check(any(c["name"] == "JTAC2" and c["mhz"] == 267 for f in flights for r in f["radios"]
              for c in r["channels"]), f"{key}: JTAC2 on the radio presets")

# 4. A SEAD flight's target waypoint is the SEAD/DEAD area; a helicopter goes to Helicopter.
out, mission, config = build({"theater": "caucasus", "mission_type": "range", "flights": [
    {"aircraft": "F-16C_50", "slots": 2, "role": "sead"},
    {"aircraft": "AH-64D_BLK_II", "slots": 2}]})
areas = {a["id"]: a["pos"] for a in out["brief"]["range"]}
viper, apache = out["brief"]["flights"]
tgt = next(w for w in viper["route"] if w["kind"] == "TGT")
check(tgt["pos"] == areas["sead"], "SEAD flight routes to the SEAD/DEAD area")
tgt = next(w for w in apache["route"] if w["kind"] == "TGT")
check(tgt["pos"] == areas["heli"], "helicopter routes to the Helicopter area")

# 4b. Range Control flights fly a plain route (no Range Area), whatever the aircraft.
out, mission, config = build({"theater": "caucasus", "mission_type": "range", "flights": [
    {"aircraft": "UH-1H", "slots": 1, "role": "control"}]})
card = out["brief"]["flights"][0]
check([w["name"] for w in card["route"]][:3] == ["Join", "Range", "Return"],
      "Range Control flies a plain route, not to the Helicopter area")
check(" - Range Control" in mission, "Range Control group name")

# 5. Old "free" setups load as Training Range; dragged areas are honoured.
req = MissionRequest.from_json({"theater": "caucasus", "mission_type": "free",
                                "flights": [{"aircraft": "F-16C_50", "slots": 1}]})
check(req.mission_type == "range", "free maps to range")
moved = [42.5, 41.8]
out, _, config = build({"theater": "caucasus", "mission_type": "range",
                        "range_areas": {"cas": moved},
                        "flights": [{"aircraft": "A-10C_2", "slots": 2, "role": "cas"}]})
cas = next(a for a in out["brief"]["range"] if a["id"] == "cas")
check(abs(cas["pos"][0] - moved[0]) < 0.01 and abs(cas["pos"][1] - moved[1]) < 0.01, "dragged CAS area")

# 6. WWII ranges: own areas, no Helicopter area, no SEAD.
out, _, config = build({"theater": "normandy", "mission_type": "range",
                        "flights": [{"aircraft": "P-51D", "slots": 2, "role": "sead"}]})
ids = [a["id"] for a in out["brief"]["range"]]
check("flak" in ids and "heli" not in ids and "sead" not in ids, f"WWII areas {ids}")
tgt = next(w for w in out["brief"]["flights"][0]["route"] if w["kind"] == "TGT")
check(tgt["pos"] == next(a["pos"] for a in out["brief"]["range"] if a["id"] == "flak"),
      "WWII SEAD role goes to Flak / Ground Attack")

print(f"range: {'OK' if not fails else f'{len(fails)} failures'}")
sys.exit(1 if fails else 0)
