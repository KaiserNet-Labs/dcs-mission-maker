"""Training Range: Range Area placement, Practice Targets, spawn templates and the Lua config.

The generator decides what *can* exist; app/lua/training_range.lua decides at run time what
does. Every Spawnable gets one late-activated template group (named "TR_TPL ...") that the
script clones into a Range Area with MOOSE SPAWN; static Spawnables and Practice Targets are
described in the config so the script can (re)create them with coalition.addStaticObject.

pydcs can't tell land from sea, so areas sit on points this app already knows are on land:
each enemy base's target area (Theater.red_bases[].inland) and the fan of secondary-objective
points around it; Anti-Ship uses the map's sea point. Users can drag any area in the builder.
"""
from dataclasses import dataclass
from pathlib import Path

from dcs import task, unittype
from dcs.drawing import Rgba
from dcs.drawing.drawings import StandardLayer
from dcs.mapping import Point

from .. import range_catalog as rc
from ..loadouts import apply_role
from ..theaters import Theater
from .common import fmt_latlon, resolve_offset

LUA_FILE = Path(__file__).resolve().parent.parent / "lua" / "training_range.lua"
TEMPLATE_PREFIX = "TR_TPL "
PRACTICE_PREFIX = "TR_PT "
SLOT_RADIUS_M = {"ground": 1500, "heli": 1500, "sea": 4000}
MIN_SEPARATION_M = 12000
IDEAL_NM = 50                      # jet areas: aim for 40-60 nm from home
FLAGS = {"range": 9032, "hook": 9030, "reload": 9031}


@dataclass
class PlacedArea:
    area: rc.Area
    pos: object                    # dcs.mapping.Point
    moved: bool = False            # the user dragged it


@dataclass
class RangeLayout:
    areas: list
    heli_base: str                 # friendly airfield closest to the Helicopter area

    def get(self, area_id):
        return next((p for p in self.areas if p.area.id == area_id), None)

    def ground_centroid(self):
        pts = [p.pos for p in self.areas if p.area.placement in ("ground", "heli")] or \
              [p.pos for p in self.areas]
        return Point(sum(p.x for p in pts) / len(pts), sum(p.y for p in pts) / len(pts),
                     pts[0]._terrain)


def _candidates(theater: Theater, terrain, preferred: str):
    """Known-land points: each enemy base's target area first, then the fan around it."""
    primary, derived = [], []
    for rb in theater.red_bases:
        ap = terrain.airports[rb.name].position
        primary.append((rb.name, resolve_offset(terrain, rb.inland)))
        dist = max(rb.spread_km, rb.inland.distance_km + 4) * 1000
        for off in (-rb.fan_deg, rb.fan_deg, 0):
            derived.append((rb.name, ap.point_from_heading(rb.inland.bearing + off, dist)))
    primary.sort(key=lambda c: c[0] != preferred)
    return primary, derived


def place_areas(theater: Theater, terrain, home_name: str, red_base_name: str, era: str,
                overrides: dict | None = None) -> RangeLayout:
    """Where each Range Area goes. overrides maps area id -> Point the user dragged."""
    overrides = overrides or {}
    home = terrain.airports[home_name].position
    red_ap = terrain.airports[red_base_name].position
    primary, derived = _candidates(theater, terrain, red_base_name)
    areas = rc.areas_for(era, bool(theater.red_sea))
    taken, placed = [], {}

    def far_enough(p):
        return all(p.distance_to_point(q) >= MIN_SEPARATION_M for q in taken)

    def take(area_id, pos):
        placed[area_id] = pos
        taken.append(pos)

    heli_base = home_name
    if any(a.placement == "heli" for a in areas):
        bases = [(b, terrain.airports[b].position) for b in theater.blue_bases]
        _name, pos, heli_base = min(
            ((rb, c, b) for rb, c in primary for b, bp in bases),
            key=lambda t: t[1].distance_to_point(terrain.airports[t[2]].position))
        take("heli", overrides.get("heli") or pos)

    def ideal(c):
        return abs(home.distance_to_point(c[1]) / 1852 - IDEAL_NM)

    ordered = [primary[0]] + sorted(primary[1:], key=ideal) + sorted(derived, key=ideal)
    for area in [a for a in areas if a.placement == "ground"]:
        if area.id in overrides:
            take(area.id, overrides[area.id])
            continue
        pick = next((c for c in ordered if far_enough(c[1])), None)
        if pick is None:   # small maps: the known spot furthest from the areas placed so far
            pick = max(ordered, key=lambda c: min(c[1].distance_to_point(q) for q in taken))
        take(area.id, pick[1])

    for area in areas:
        if area.id in placed:
            continue
        if area.id in overrides:
            take(area.id, overrides[area.id])
        elif area.placement == "sea":
            take(area.id, resolve_offset(terrain, theater.red_sea))
        elif area.placement == "air":
            mid = home.lerp(red_ap, 0.5)
            axis = home.heading_between_point(red_ap)
            left, right = mid.point_from_heading(axis - 90, 40000), mid.point_from_heading(axis + 90, 40000)
            ground = list(taken) or [mid]
            # The side further from the ground areas, so leashed fighters stay off the attack runs.
            side = max((left, right), key=lambda p: min(p.distance_to_point(g) for g in ground))
            take(area.id, side)
    return RangeLayout([PlacedArea(a, placed[a.id], a.id in overrides) for a in areas], heli_base)


# A Flight Role flies the standard route of the matching mission type to its Range Area.
ROLE_TASKING = {"aa": "cap", "sead": "sead", "cas": "cas", "strike": "strike", "antiship": "antiship"}


def flight_route(layout: RangeLayout, role: str, heli: bool):
    """(PlacedArea or None, mission type for task/loadout/route shape) for one player flight.
    Helicopters go to the Helicopter area; others to their Flight Role's area; no role (or
    no such area on this map) means a plain Join -> Range -> Return."""
    if heli and layout.get("heli"):
        return layout.get("heli"), "cas"
    area = layout.get(rc.ROLE_AREA[role]) if role in rc.ROLE_AREA else None
    if area is None and role == "sead":            # WWII/Korea: Flak / Ground Attack
        area = layout.get("flak")
    return (area, ROLE_TASKING[role]) if area else (None, "range")


# ------------------------------------------------------------------ Lua config
def to_lua(value, indent=0):
    """Python data -> a Lua table constructor (dicts, lists, str, numbers, bools, None)."""
    pad, inner = "  " * indent, "  " * (indent + 1)
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return repr(round(value, 3))
    if isinstance(value, str):
        return '"' + value.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n") + '"'
    if isinstance(value, (list, tuple)):
        if not value:
            return "{}"
        return "{\n" + ",\n".join(inner + to_lua(v, indent + 1) for v in value) + ",\n" + pad + "}"
    if isinstance(value, dict):
        if not value:
            return "{}"
        rows = []
        for k, v in value.items():
            key = k if isinstance(k, str) and k.isidentifier() else f"[{to_lua(k)}]"
            rows.append(f"{inner}{key} = {to_lua(v, indent + 1)}")
        return "{\n" + ",\n".join(rows) + ",\n" + pad + "}"
    raise TypeError(f"can't write {type(value).__name__} to Lua")


def static_info(utype):
    """type/category/shape for coalition.addStaticObject, matching what pydcs writes."""
    is_ship = issubclass(utype, unittype.ShipType)
    category = "Ships" if is_ship else (getattr(utype, "category", None) or "Vehicles")
    info = {"type": utype.id, "category": category}
    if getattr(utype, "shape_name", None):
        info["shape_name"] = utype.shape_name
    return info


def _vec2(p):
    return {"x": round(p.x, 1), "y": round(p.y, 1)}


class RangeMixin:
    """The Training Range mission type."""

    def setup_range_layout(self):
        """Called from Builder.__init__ once the era is known."""
        overrides = {}
        for key, val in (self.req.range_areas or {}).items():
            pt = self.latlng_point(val, self.home.position, 400)
            if pt is not None:
                overrides[key] = pt
        self.range_layout = place_areas(self.theater, self.terrain, self.home.name,
                                        self.red_base.name, self.era, overrides)
        self.heli_home = self.terrain.airports[self.range_layout.heli_base]
        self.heli_home.set_blue()
        self.target = self.range_layout.ground_centroid()
        self.area_difficulty = rc.DIFFICULTY_FROM_MISSION[self.req.difficulty]
        self.range_practice = {}        # area id -> [practice target config]
        self.range_templates = {}       # (system id, size) -> template group name

    # --------------------------------------------------------------- building
    def objective_range(self):
        layer = self.m.drawings.get_layer(StandardLayer.Common)
        for p in self.range_layout.areas:
            a = p.area
            self.m.triggers.add_triggerzone(p.pos, a.radius_m, False, f"TR {a.label}")
            layer.add_circle(p.pos, a.radius_m, color=Rgba(255, 170, 0, 255),
                             fill=Rgba(255, 170, 0, 30), line_thickness=4)
            layer.add_text_box(p.pos.point_from_heading(0, a.radius_m + 1500), f"RANGE {a.label}",
                               color=Rgba(255, 170, 0, 255), fill=Rgba(0, 0, 0, 120), font_size=16)
            self.range_practice[a.id] = [self.practice_target(a, kind, p.pos)
                                         for kind in a.practice]
        for sid in rc.all_systems(self.era, self.enemy_side, bool(self.theater.red_sea)):
            system = rc.SYSTEMS[sid]
            if system.kind == "static":
                continue
            sizes = {system.size}
            if system.kind == "air":
                sizes = {r.size or system.size for r in rc.roles_for(self.era).values()
                         if sid in r.systems[self.enemy_side]}
            for size in sorted(sizes):
                self.range_templates[(sid, size)] = self.spawn_template(system, size)
        self.brief.tasking.append(
            "Training Range: no fixed targets. Use F10 > Other > Training Range to spawn enemy "
            "forces into a Range Area (drawn in orange on the F10 map), change its difficulty "
            "or clear it. Practice Targets in each area don't shoot back and come back on their "
            "own a few minutes after they are destroyed.")
        for p in self.range_layout.areas:
            self.brief.tasking.append(
                f"{p.area.label} area: {fmt_latlon(p.pos)} (bulls {self.bulls(p.pos)}). "
                f"{p.area.purpose}")

    def practice_target(self, area, kind, center):
        """One Practice Target at the area centre: statics, or a radiating group template."""
        how, layout = rc.PRACTICE[kind]
        name = f"{PRACTICE_PREFIX}{area.label} {rc.PRACTICE_LABELS[kind]}"
        if how == "group":
            g = self.ground_group(name, layout, center)
            g.late_activation = True
            g.points[0].tasks.append(task.OptROE(task.OptROE.Values.WeaponHold))
            return {"kind": kind, "label": rc.PRACTICE_LABELS[kind], "template": g.name,
                    "pos": _vec2(center)}
        units = []
        for i, (utype, brg, dist) in enumerate(layout, start=1):
            pos = center.point_from_heading(brg, dist)
            uname = f"{name} {i}"
            self.m.static_group(self.red, uname, utype, pos, heading=0)
            units.append({"name": uname, **static_info(utype), **_vec2(pos), "heading": 0})
        return {"kind": kind, "label": rc.PRACTICE_LABELS[kind], "statics": units,
                "pos": _vec2(center)}

    def template_spot(self, system):
        """Where an inactive template waits: the enemy base's target area, or its sea point."""
        if system.kind == "ship":
            return resolve_offset(self.terrain, self.theater.red_sea)
        return resolve_offset(self.terrain, self.red_base.inland)

    def spawn_template(self, system, size):
        name = f"{TEMPLATE_PREFIX}{system.id}" + (f" x{size}" if system.kind == "air" else "")
        spot = self.template_spot(system)
        if system.kind == "air":
            slow = system.aircraft.helicopter or (system.aircraft.max_speed or 900) < 800
            alt, spd = (300, 200) if system.aircraft.helicopter else ((3000, 450) if slow else (6500, 800))
            g = self.m.flight_group_inflight(self.red, name, system.aircraft,
                                             self.red_airport.position.point_from_heading(0, 20000),
                                             alt, spd, maintask=task.CAP if not system.aircraft.helicopter
                                             else task.CAS, group_size=size)
            apply_role(g, "aa" if not system.aircraft.helicopter else "cas")
        elif system.kind == "ship":
            first, *rest = system.units
            g = self.m.ship_group(self.red, name, first[0], spot.point_from_heading(first[1], first[2]))
            for i, (stype, brg, dist) in enumerate(rest, start=2):
                s = self.m.ship(f"{name}-{i}", stype)
                s.position = spot.point_from_heading(brg, dist)
                g.add_unit(s)
        else:
            g = self.ground_group(name, list(system.units), spot)
        g.late_activation = True
        return g.name

    # ----------------------------------------------------------- Lua config
    def range_config(self):
        has_sea = bool(self.theater.red_sea)
        systems = {}
        for sid in rc.all_systems(self.era, self.enemy_side, has_sea):
            s = rc.SYSTEMS[sid]
            entry = {"label": s.label, "kind": s.kind, "radar": s.radar,
                     "aliases": rc.aliases(s)}
            if s.kind == "static":
                entry["statics"] = [{**static_info(t), "bearing": brg, "dist": dist}
                                    for t, brg, dist in s.units]
            else:
                entry["templates"] = {str(size): tpl for (tid, size), tpl in
                                      self.range_templates.items() if tid == sid}
            if s.kind == "air":
                entry["size"] = s.size
                entry["helicopter"] = bool(s.aircraft.helicopter)
                slow = s.aircraft.helicopter or (s.aircraft.max_speed or 900) < 800
                entry["alt"] = 300 if s.aircraft.helicopter else (3000 if slow else 6500)
                entry["speed"] = 55 if s.aircraft.helicopter else (125 if slow else 220)
            systems[sid] = entry
        areas = []
        for p in self.range_layout.areas:
            a = p.area
            ring_r = SLOT_RADIUS_M.get(a.placement)
            slots = ([_vec2(p.pos.point_from_heading(i * 360 / rc.CAPS["area"], ring_r))
                      for i in range(rc.CAPS["area"])] if ring_r else [])
            areas.append({
                "id": a.id, "label": a.label, "kind": a.placement, "center": _vec2(p.pos),
                "radius": a.radius_m, "slots": slots,
                "roles": [{"id": role.id, "label": role.label, "repeatable": role.repeatable,
                           "size": role.size, "systems": ids,
                           "default": rc.ERA_DEFAULTS[(self.era, self.enemy_side)].get(role.id)}
                          for role, ids in rc.menu_for(a, self.era, self.enemy_side)],
                "practice": self.range_practice.get(a.id, []),
            })
        return {
            "version": 1, "era": self.era, "enemy_country": "CJTF_RED",
            "player_coalition": "blue", "difficulty": self.area_difficulty,
            "caps": dict(rc.CAPS), "repeat_delay": rc.REPEAT_DELAY_S,
            "practice_respawn": rc.PRACTICE_RESPAWN_S, "flags": dict(FLAGS),
            "areas": areas, "systems": systems,
            "range_control": list(getattr(self, "range_control_groups", [])),
        }

    def range_config_lua(self):
        return ("-- DCS Mission Maker: Training Range configuration (generated)\n"
                "DMM_RANGE = " + to_lua(self.range_config()) + "\n")

    def range_brief(self):
        """Range Areas for the Briefing Room map and Range Guide."""
        out = []
        for p in self.range_layout.areas:
            a = p.area
            out.append({"id": a.id, "label": a.label, "purpose": a.purpose,
                        "pos": p.pos, "radius": a.radius_m,
                        "roles": [{"label": role.label,
                                   "systems": [rc.SYSTEMS[i].label for i in ids]}
                                  for role, ids in rc.menu_for(a, self.era, self.enemy_side)],
                        "practice": [rc.PRACTICE_LABELS[k] for k in a.practice]})
        return out

