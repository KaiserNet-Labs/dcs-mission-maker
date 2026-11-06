"""Training Range catalogue: Range Areas, Spawn Roles, Spawnable systems and the Default Roster.

Vocabulary (see CONTEXT.md): a Range Area offers Spawn Roles; each Spawn Role offers an
era-matched default plus specific Spawnables. Jet-era ranges (Vietnam, Late Cold War,
Modern) share one catalogue whatever the mission's era, so an F-4E crew can still call up
an SA-2 on a Modern range. WWII and Korea ranges have their own areas and roles.

Everything here is plain data; app/generator/range.py turns it into templates, zones and
the Lua config the in-game script (app/lua/training_range.lua) reads.
"""
from dataclasses import dataclass

from dcs import helicopters, planes, ships, statics, vehicles

from . import eras

AD, ARMOR, ART = vehicles.AirDefence, vehicles.Armor, vehicles.Artillery
INF, UNARMED = vehicles.Infantry, vehicles.Unarmed
FORT, WH = statics.Fortification, statics.Warehouse
ring = eras.ring

DIFFICULTIES = ["easy", "normal", "hard"]          # Area Difficulty
DIFFICULTY_FROM_MISSION = {"easy": "easy", "medium": "normal", "hard": "hard", "extreme": "hard"}
CAPS = {"area": 6, "aircraft": 8, "total": 25}
MAX_FLIGHTS = 32
MENU_LIMIT = 10                                    # DCS F10 items per menu level
REPEAT_DELAY_S = 120
PRACTICE_RESPAWN_S = 300
JET_ERAS = ("vietnam", "coldwar", "modern")


# ------------------------------------------------------------------ Spawnables
@dataclass(frozen=True)
class System:
    """One Spawnable: a single group of units (or statics) the menu can place."""
    id: str
    label: str
    kind: str                      # ground | air | ship | static
    units: tuple = ()              # ground/ship/static: ((type, bearing, metres), ...)
    aircraft: object = None        # air: the pydcs plane/helicopter type
    size: int = 2                  # air: group size
    aliases: tuple = ()            # extra names for Marker Spawn ("s300", "sa-10")
    radar: bool = False            # an air defence site with a search/track radar
    threat_m: int = 0              # engagement range for briefings and Threat ID


def _g(id_, label, units, **kw):
    return System(id_, label, "ground", tuple(units), **kw)


def _sam(id_, site, **kw):
    label, layout = site
    return System(id_, label, "ground", tuple(layout), radar=True, **kw)


def _pair(id_, label, utype, gap=250, **kw):
    return _g(id_, label, [(utype, 0, 0), (utype, 90, gap)], **kw)


def _column(id_, label, lead, follow, n_lead=4, n_follow=2):
    return _g(id_, label, [(lead, 180, 60 * i) for i in range(n_lead)]
              + [(follow, 180, 60 * (n_lead + i)) for i in range(n_follow)])


def _battery(id_, label, gun, n=4, truck=None):
    units = [(gun, 90, 60 * i) for i in range(n)]
    return _g(id_, label, units + ([(truck, 180, 150)] if truck else []))


def _air(id_, label, aircraft, size=2, aliases=()):
    return System(id_, label, "air", aircraft=aircraft, size=size, aliases=aliases)


def _ships(id_, label, *types):
    return System(id_, label, "ship", tuple((t, 180, 900 * i) for i, t in enumerate(types)))


def _static(id_, label, units):
    return System(id_, label, "static", tuple(units))


SA5 = ("SA-5 Gammon", [(AD.RPC_5N62V, 0, 0), (AD.P14_SR, 180, 400)]
       + ring(AD.S_200_Launcher, 6, 350, 30))
RAPIER = ("Rapier", [(AD.Rapier_fsa_blindfire_radar, 0, 0),
                     (AD.Rapier_fsa_optical_tracker_unit, 180, 60)]
          + ring(AD.Rapier_fsa_launcher, 3, 150, 30))
ROLAND = ("Roland", [(AD.Roland_Radar, 0, 0), (AD.Roland_ADS, 90, 200), (AD.Roland_ADS, 270, 200)])

_SYSTEMS = [
    # --- air defence, east
    _sam("sa10", eras.SA10, aliases=("sa-10", "s300", "s-300", "grumble"), threat_m=75000),
    _sam("sa5", SA5, aliases=("sa-5", "s200", "s-200", "gammon"), threat_m=150000),
    _sam("sa2", eras.SA2, aliases=("sa-2", "s75", "guideline"), threat_m=45000),
    _sam("sa11", eras.SA11, aliases=("sa-11", "buk", "gadfly"), threat_m=35000),
    _sam("sa6", eras.SA6, aliases=("sa-6", "kub", "gainful"), threat_m=25000),
    _sam("sa3", eras.SA3, aliases=("sa-3", "s125", "goa"), threat_m=25000),
    _g("sa8", "SA-8 Gecko", [(AD.Osa_9A33_ln, 0, 0), (AD.Osa_9A33_ln, 90, 300)],
       aliases=("sa-8", "osa", "gecko"), radar=True, threat_m=10000),
    _g("sa15", "SA-15 Gauntlet", [(AD.Tor_9A331, 0, 0), (AD.Tor_9A331, 90, 300)],
       aliases=("sa-15", "tor", "gauntlet"), radar=True, threat_m=12000),
    _g("sa19", "SA-19 Grison (Tunguska)", [(AD.X_2S6_Tunguska, 0, 0), (AD.X_2S6_Tunguska, 90, 300)],
       aliases=("sa-19", "tunguska", "grison"), radar=True, threat_m=8000),
    _pair("sa13", "SA-13 Gopher", AD.Strela_10M3, aliases=("sa-13", "strela10", "gopher"),
          threat_m=5000),
    _pair("sa9", "SA-9 Gaskin", AD.Strela_1_9P31, aliases=("sa-9", "strela1", "gaskin"),
          threat_m=4000),
    _pair("zsu234", "ZSU-23-4 Shilka", AD.ZSU_23_4_Shilka, aliases=("shilka", "zsu-23-4"),
          radar=True, threat_m=2500),
    _pair("zu23", "ZU-23 emplacement", AD.ZU_23_Emplacement, aliases=("zu-23",), threat_m=2000),
    _pair("zsu57", "ZSU-57-2", AD.ZSU_57_2, aliases=("zsu-57",), threat_m=3000),
    _g("igla", "SA-18 Igla team", [(AD.SA_18_Igla_manpad, 0, 0), (AD.SA_18_Igla_manpad, 90, 40),
                                   (AD.SA_18_Igla_comm, 180, 20)],
       aliases=("sa-18", "manpads", "igla"), threat_m=5000),
    _g("ewr1l13", "1L13 early-warning radar", [(AD.X_1L13_EWR, 0, 0)], aliases=("1l13", "ewr"),
       radar=True),
    _g("ewr55g6", "55G6 early-warning radar", [(AD.X_55G6_EWR, 0, 0)], aliases=("55g6",),
       radar=True),
    _g("ewrp19", "P-19 radar", [(AD.P_19_s_125_sr, 0, 0)], aliases=("p19", "p-19", "flatface"),
       radar=True),
    # --- air defence, west
    _sam("patriot", eras.PATRIOT, aliases=("mim-104", "pac2"), threat_m=70000),
    _sam("hawk", eras.HAWK, aliases=("mim-23",), threat_m=40000),
    _sam("nasams", eras.NASAMS, threat_m=25000),
    _sam("rapier", RAPIER, threat_m=7000),
    _sam("roland", ROLAND, threat_m=8000),
    _pair("chaparral", "M48 Chaparral", AD.M48_Chaparral, aliases=("m48",), threat_m=8000),
    _pair("avenger", "M1097 Avenger", AD.M1097_Avenger, aliases=("m1097",), threat_m=5000),
    _pair("linebacker", "M6 Linebacker", AD.M6_Linebacker, aliases=("m6",), threat_m=5000),
    _pair("vulcan", "M163 Vulcan", AD.Vulcan, aliases=("m163",), radar=True, threat_m=2000),
    _pair("gepard", "Gepard", AD.Gepard, radar=True, threat_m=3500),
    _g("stinger", "Stinger team", [(AD.Soldier_stinger, 0, 0), (AD.Soldier_stinger, 90, 40),
                                   (AD.Stinger_comm, 180, 20)],
       aliases=("manpads", "fim-92"), threat_m=5000),
    _g("fps117", "FPS-117 early-warning radar", [(AD.FPS_117, 0, 0), (AD.FPS_117_ECS, 90, 60)],
       aliases=("fps-117", "ewr"), radar=True),
    # --- armour, east
    _column("t55", "T-55 column", ARMOR.T_55, ARMOR.BTR_60),
    _column("t62", "T-62M column", ARMOR.T62M, ARMOR.BMP_1),
    _column("t72", "T-72B column", ARMOR.T_72B, ARMOR.BMP_2),
    _column("t80", "T-80U column", ARMOR.T_80UD, ARMOR.BMP_2),
    _column("t90", "T-90 column", ARMOR.T_90, ARMOR.BMP_3),
    _column("bmp2", "BMP-2 company", ARMOR.BMP_2, ARMOR.BRDM_2),
    _column("btr80", "BTR-80 company", ARMOR.BTR_80, ARMOR.BRDM_2),
    # --- armour, west
    _column("m60", "M60 column", ARMOR.M_60, ARMOR.M_113),
    _column("m1", "M1A2 Abrams column", ARMOR.M1A2C_SEP_V3, ARMOR.M_2_Bradley),
    _column("leopard2", "Leopard 2 column", ARMOR.Leopard_2A5, ARMOR.Marder),
    _column("challenger", "Challenger 2 column", ARMOR.Challenger2, ARMOR.MCV_80),
    _column("leclerc", "Leclerc column", ARMOR.Leclerc, ARMOR.VAB_Mephisto),
    _column("bradley", "Bradley company", ARMOR.M_2_Bradley, ARMOR.M1043_HMMWV_Armament),
    _column("stryker", "Stryker company", ARMOR.M1126_Stryker_ICV, ARMOR.M1134_Stryker_ATGM),
    # --- infantry and technicals
    _g("inf_east", "Infantry platoon", [(INF.Soldier_AK, 90, 8 * i) for i in range(8)]
       + [(INF.Paratrooper_RPG_16, 90, 70), (INF.Paratrooper_RPG_16, 90, 80)],
       aliases=("infantry",)),
    _g("technicals", "Technicals", [(ARMOR.HL_DSHK, 180, 40 * i) for i in range(4)]),
    _g("inf_west", "Infantry platoon", [(INF.Soldier_M4, 90, 8 * i) for i in range(8)]
       + [(INF.Soldier_M249, 90, 70), (INF.Soldier_M249, 90, 80)], aliases=("infantry",)),
    _g("humvees", "Armed Humvees", [(ARMOR.M1043_HMMWV_Armament, 180, 40 * i) for i in range(4)]),
    # --- artillery
    _battery("grad", "BM-21 Grad battery", ART.Grad_URAL, truck=UNARMED.Ural_375),
    _battery("gvozdika", "2S1 Gvozdika battery", ART.SAU_Gvozdika, truck=UNARMED.Ural_375),
    _battery("msta", "2S19 Msta battery", ART.SAU_Msta, truck=UNARMED.Ural_375),
    _battery("smerch", "BM-30 Smerch battery", ART.Smerch, n=3, truck=UNARMED.Ural_375),
    _battery("m109", "M109 battery", ART.M_109, truck=UNARMED.M_818),
    _battery("mlrs", "M270 MLRS battery", ART.MLRS, n=3, truck=UNARMED.M_818),
    _battery("l118", "L118 light gun battery", ART.L118_Unit, truck=UNARMED.Bedford_MWD),
    # --- convoys
    _g("convoy_east", "Supply convoy", [(UNARMED.Ural_375, 180, 50 * i) for i in range(5)]
       + [(ARMOR.BTR_80, 0, 60)], aliases=("convoy",)),
    _g("convoy_west", "Supply convoy", [(UNARMED.M_818, 180, 50 * i) for i in range(5)]
       + [(ARMOR.M1043_HMMWV_Armament, 0, 60)], aliases=("convoy",)),
    # --- strike targets (statics)
    _static("hq", "Command post", [(FORT.Military_staff, 0, 0), (FORT.Barracks_2, 90, 80),
                                   (FORT.Barracks_2, 270, 80), (FORT.Comms_tower_M, 180, 60)]),
    _static("bunker", "Bunker complex", [(FORT.Fire_Control_Bunker, 0, 0),
                                         (FORT.Shelter, 90, 70), (FORT.Shelter_B, 270, 70)]),
    _static("depot", "Supply depot", [(WH.Warehouse, 0, 0), (WH.Warehouse, 90, 110),
                                      (FORT.Fuel_tank, 200, 120), (FORT.Fuel_tank, 220, 170),
                                      (FORT.FARP_Ammo_Dump_Coating, 300, 120)]),
    _static("hangars", "Hangars", [(FORT.Hangar_A, 0, 0), (FORT.Hangar_A, 90, 120),
                                   (FORT.Tech_hangar_A, 180, 120)]),
    _static("comms", "Comms site", [(FORT.TV_tower, 0, 0), (FORT.Comms_tower_M, 90, 60),
                                    (FORT.Small_werehouse_1, 180, 50)]),
    # --- aircraft, east
    _air("mig21", "MiG-21", planes.MiG_21Bis), _air("mig23", "MiG-23", planes.MiG_23MLD),
    _air("mig29", "MiG-29A", planes.MiG_29A), _air("mig29s", "MiG-29S", planes.MiG_29S),
    _air("su27", "Su-27", planes.Su_27), _air("su30", "Su-30", planes.Su_30),
    _air("mig31", "MiG-31", planes.MiG_31), _air("j11", "J-11A", planes.J_11A),
    _air("mig25", "MiG-25", planes.MiG_25PD),
    _air("tu22", "Tu-22M3", planes.Tu_22M3), _air("tu95", "Tu-95", planes.Tu_95MS),
    _air("su24", "Su-24M", planes.Su_24M), _air("su34", "Su-34", planes.Su_34),
    _air("mi24", "Mi-24V", helicopters.Mi_24V),
    _air("mi8", "Mi-8", helicopters.Mi_8MT),
    _air("ka50", "Ka-50", helicopters.Ka_50),
    _air("mi28", "Mi-28N", helicopters.Mi_28N),
    # --- aircraft, west
    _air("f4e", "F-4E", planes.F_4E_45MC), _air("f5e", "F-5E", planes.F_5E_3),
    _air("f16", "F-16C", planes.F_16C_bl_52d), _air("f15c", "F-15C", planes.F_15C),
    _air("f18", "F/A-18C", planes.FA_18C_hornet), _air("f14a", "F-14A", planes.F_14A_135_GR),
    _air("m2000", "Mirage 2000-5", planes.Mirage_2000_5),
    _air("b52", "B-52H", planes.B_52H), _air("b1b", "B-1B", planes.B_1B),
    _air("tornado", "Tornado IDS", planes.Tornado_IDS),
    _air("ah64", "AH-64A", helicopters.AH_64A),
    _air("ah1w", "AH-1W", helicopters.AH_1W),
    _air("gazelle", "SA342 Gazelle", helicopters.SA342M),
    # --- ships
    _ships("molniya", "Molniya patrol boats", ships.MOLNIYA, ships.MOLNIYA),
    _ships("albatros", "Grisha corvettes", ships.ALBATROS, ships.ALBATROS),
    _ships("rezky", "Krivak frigate group", ships.REZKY, ships.ALBATROS),
    _ships("neustrash", "Neustrashimy frigate group", ships.NEUSTRASH, ships.REZKY),
    _ships("moskva", "Slava cruiser group", ships.MOSCOW, ships.NEUSTRASH, ships.REZKY),
    _ships("piotr", "Kirov cruiser group", ships.PIOTR, ships.REZKY),
    _ships("combattante", "La Combattante patrol boats", ships.La_Combattante_II,
           ships.La_Combattante_II),
    _ships("perry", "Perry frigate group", ships.PERRY, ships.PERRY),
    _ships("burke", "Arleigh Burke group", ships.USS_Arleigh_Burke_IIa, ships.PERRY),
    _ships("tico", "Ticonderoga cruiser group", ships.TICONDEROG, ships.USS_Arleigh_Burke_IIa),
    # --- WWII / Korea
    _sam("flak88", eras.FLAK88, threat_m=10000), _sam("flak88h", eras.FLAK88_HEAVY, threat_m=10000),
    _sam("aa37", eras.ALLIED_AA, threat_m=9000), _sam("aa37h", eras.ALLIED_AA_HEAVY, threat_m=9000),
    _sam("raaa", eras.RADAR_AAA, threat_m=12000), _sam("raaah", eras.RADAR_AAA_HEAVY, threat_m=12000),
    _pair("flak38", "Flak 38 pair", AD.Flak38, threat_m=2000),
    _pair("bofors", "Bofors 40 mm pair", AD.Bofors40, threat_m=2500),
    _pair("quad50", "M45 Quadmount pair", AD.M45_Quadmount, threat_m=1500),
    _pair("s60", "S-60 57 mm pair", AD.S_60_Type59_Artillery, threat_m=4000),
    _column("pz4", "Panzer IV column", ARMOR.Pz_IV_H, ARMOR.Sd_Kfz_251),
    _column("panther", "Panther column", ARMOR.Pz_V_Panther_G, ARMOR.Sd_Kfz_251),
    _column("tiger", "Tiger column", ARMOR.Tiger_I, ARMOR.Sd_Kfz_251),
    _column("sherman", "Sherman column", ARMOR.M4_Sherman, ARMOR.M2A1_halftrack),
    _column("cromwell", "Cromwell column", ARMOR.Cromwell_IV, ARMOR.M2A1_halftrack),
    _column("t34", "T-34-85 column", ARMOR.T_34_85, UNARMED.Ural_375),
    _g("inf_axis", "Infantry platoon", [(INF.Soldier_mauser98, 90, 8 * i) for i in range(10)]),
    _g("inf_allied", "Infantry platoon", [(INF.Soldier_wwii_us, 90, 8 * i) for i in range(10)]),
    _battery("lefh", "leFH 18 battery", ART.LeFH_18_40_105, truck=UNARMED.Blitz_36_6700A),
    _battery("m2a1", "M2A1 105 mm battery", ART.M2A1_105, truck=UNARMED.CCKW_353),
    _g("convoy_axis", "Supply convoy", [(UNARMED.Blitz_36_6700A, 180, 50 * i) for i in range(6)]),
    _g("convoy_allied", "Supply convoy", [(UNARMED.CCKW_353, 180, 50 * i) for i in range(6)]),
    _air("bf109", "Bf 109 K-4", planes.Bf_109K_4), _air("fw190a", "Fw 190 A-8", planes.FW_190A8),
    _air("fw190d", "Fw 190 D-9", planes.FW_190D9), _air("ju88", "Ju 88", planes.Ju_88A4, size=3),
    _air("p51", "P-51D", planes.P_51D), _air("p47", "P-47D", planes.P_47D_30),
    _air("spitfire", "Spitfire IX", planes.SpitfireLFMkIX),
    _air("b17", "B-17G", planes.B_17G, size=3), _air("a20", "A-20G", planes.A_20G, size=3),
    _air("mig15", "MiG-15", planes.MiG_15bis), _air("f86", "F-86F", planes.F_86F_Sabre),
    _ships("sboot", "S-boats", ships.Schnellboot_type_S130, ships.Schnellboot_type_S130),
    _ships("uboat", "U-boat and escort", ships.Uboat_VIIC, ships.Schnellboot_type_S130),
    _ships("lst", "Landing ships", ships.LST_Mk2, ships.LST_Mk2),
    _ships("cargo", "Cargo ships", ships.Dry_cargo_ship_1, ships.Dry_cargo_ship_2),
]
SYSTEMS: dict[str, System] = {s.id: s for s in _SYSTEMS}


# ------------------------------------------------------------------ Spawn Roles
@dataclass(frozen=True)
class Role:
    """A Spawn Role: a menu entry listing an era default plus specific systems per enemy side."""
    id: str
    label: str
    systems: dict                  # enemy side -> [system id], most common first
    repeatable: bool = False       # offers Repeating Spawn
    size: int | None = None        # air roles: overrides the system's group size


def _role(id_, label, east, west, **kw):
    return Role(id_, label, {"east": east, "west": west}, **kw)


ROLES_JET = {r.id: r for r in [
    _role("lr_sam", "Long-range SAM", ["sa10", "sa5", "sa2"], ["patriot", "hawk"]),
    _role("mr_sam", "Medium SAM", ["sa11", "sa6", "sa3"], ["hawk", "nasams", "rapier"]),
    _role("sr_sam", "Short-range SAM", ["sa15", "sa8", "sa19", "sa13", "sa9"],
          ["roland", "chaparral", "avenger", "linebacker", "rapier"]),
    _role("shorad", "SHORAD / AAA", ["zsu234", "sa19", "sa13", "zu23", "zsu57"],
          ["vulcan", "gepard", "avenger", "linebacker"]),
    _role("ewr", "Early-warning radar", ["ewr1l13", "ewr55g6", "ewrp19"], ["fps117"]),
    _role("armour", "Armour column", ["t72", "t80", "t90", "t62", "t55", "bmp2", "btr80"],
          ["m1", "leopard2", "challenger", "leclerc", "m60", "bradley", "stryker"],
          repeatable=True),
    _role("infantry", "Infantry / technicals", ["inf_east", "technicals"],
          ["inf_west", "humvees"], repeatable=True),
    _role("artillery", "Artillery", ["grad", "gvozdika", "msta", "smerch"],
          ["m109", "mlrs", "l118"]),
    _role("manpads", "MANPADS", ["igla"], ["stinger"]),
    _role("convoy", "Supply convoy", ["convoy_east"], ["convoy_west"], repeatable=True),
    _role("buildings", "Buildings", ["hq", "hangars", "comms"], ["hq", "hangars", "comms"]),
    _role("bunkers", "Bunkers", ["bunker"], ["bunker"]),
    _role("depot", "Depot", ["depot"], ["depot"]),
    _role("fighter_pair", "Fighter pair",
          ["mig29", "su27", "mig21", "mig23", "mig29s", "su30", "mig31", "j11", "mig25"],
          ["f16", "f15c", "f18", "f4e", "f5e", "f14a", "m2000"], repeatable=True, size=2),
    _role("fighter_four", "Fighter 4-ship",
          ["mig29", "su27", "mig21", "mig23", "mig29s", "su30", "mig31", "j11", "mig25"],
          ["f16", "f15c", "f18", "f4e", "f5e", "f14a", "m2000"], repeatable=True, size=4),
    _role("bomber", "Bomber", ["tu22", "tu95", "su24", "su34"], ["b52", "b1b", "tornado"],
          repeatable=True),
    _role("helicopter", "Helicopter", ["mi24", "mi8", "ka50", "mi28"], ["ah64", "ah1w", "gazelle"],
          repeatable=True, size=2),
    _role("patrol", "Patrol boats", ["molniya", "albatros"], ["combattante"]),
    _role("frigates", "Frigate group", ["rezky", "neustrash"], ["perry", "burke"]),
    _role("cruiser", "Cruiser group", ["moskva", "piotr"], ["tico"]),
]}

ROLES_WARBIRD = {r.id: r for r in [
    _role("flak", "Flak battery", ["flak88", "flak88h", "raaa", "raaah"], ["aa37", "aa37h"]),
    _role("light_flak", "Light flak", ["flak38", "s60", "zu23"], ["bofors", "quad50"]),
    _role("armour", "Armour column", ["panther", "pz4", "tiger", "t34"],
          ["sherman", "cromwell"], repeatable=True),
    _role("infantry", "Infantry", ["inf_axis", "inf_east"], ["inf_allied"], repeatable=True),
    _role("artillery", "Artillery", ["lefh"], ["m2a1"]),
    _role("convoy", "Supply convoy", ["convoy_axis", "convoy_east"], ["convoy_allied"],
          repeatable=True),
    _role("buildings", "Buildings", ["hq", "hangars"], ["hq", "hangars"]),
    _role("depot", "Depot", ["depot"], ["depot"]),
    _role("fighter_pair", "Fighter pair", ["fw190a", "fw190d", "bf109", "mig15"],
          ["p51", "spitfire", "p47", "f86"], repeatable=True, size=2),
    _role("fighter_four", "Fighter 4-ship", ["fw190a", "fw190d", "bf109", "mig15"],
          ["p51", "spitfire", "p47", "f86"], repeatable=True, size=4),
    _role("bomber", "Bomber", ["ju88"], ["b17", "a20"], repeatable=True),
    _role("patrol", "Patrol boats", ["sboot", "uboat", "cargo"], ["lst"]),
    _role("cargo", "Cargo ships", ["cargo"], ["cargo"]),
]}

# Era default per (era, enemy side): role id -> system id. The first entry of each menu.
ERA_DEFAULTS = {
    ("vietnam", "east"): {"lr_sam": "sa2", "mr_sam": "sa3", "sr_sam": "sa9", "shorad": "zsu234",
                          "ewr": "ewrp19", "armour": "t55", "infantry": "inf_east",
                          "artillery": "grad", "manpads": "igla", "fighter_pair": "mig21",
                          "fighter_four": "mig21", "bomber": "su24", "helicopter": "mi8",
                          "patrol": "molniya", "frigates": "rezky", "cruiser": "moskva"},
    ("vietnam", "west"): {"lr_sam": "hawk", "mr_sam": "hawk", "sr_sam": "chaparral",
                          "shorad": "vulcan", "armour": "m60", "infantry": "inf_west",
                          "artillery": "m109", "fighter_pair": "f4e", "fighter_four": "f4e",
                          "bomber": "b52", "helicopter": "ah1w", "frigates": "perry"},
    ("coldwar", "east"): {"lr_sam": "sa10", "mr_sam": "sa6", "sr_sam": "sa8", "shorad": "zsu234",
                          "ewr": "ewr1l13", "armour": "t72", "infantry": "inf_east",
                          "artillery": "gvozdika", "manpads": "igla", "fighter_pair": "mig29",
                          "fighter_four": "mig23", "bomber": "tu22", "helicopter": "mi24",
                          "patrol": "molniya", "frigates": "rezky", "cruiser": "moskva"},
    ("coldwar", "west"): {"lr_sam": "hawk", "mr_sam": "hawk", "sr_sam": "roland",
                          "shorad": "gepard", "armour": "m60", "infantry": "inf_west",
                          "artillery": "m109", "manpads": "stinger", "fighter_pair": "f15c",
                          "fighter_four": "f4e", "bomber": "b52", "helicopter": "ah1w",
                          "frigates": "perry"},
    ("modern", "east"): {"lr_sam": "sa10", "mr_sam": "sa11", "sr_sam": "sa15", "shorad": "sa19",
                         "ewr": "ewr55g6", "armour": "t90", "infantry": "inf_east",
                         "artillery": "msta", "manpads": "igla", "fighter_pair": "su27",
                         "fighter_four": "mig29s", "bomber": "su34", "helicopter": "ka50",
                         "patrol": "molniya", "frigates": "neustrash", "cruiser": "piotr"},
    ("modern", "west"): {"lr_sam": "patriot", "mr_sam": "nasams", "sr_sam": "avenger",
                         "shorad": "linebacker", "ewr": "fps117", "armour": "m1",
                         "infantry": "inf_west", "artillery": "mlrs", "manpads": "stinger",
                         "fighter_pair": "f16", "fighter_four": "f18", "bomber": "b1b",
                         "helicopter": "ah64", "patrol": "combattante", "frigates": "burke",
                         "cruiser": "tico"},
    ("ww2", "east"): {"flak": "flak88", "light_flak": "flak38", "armour": "panther",
                      "infantry": "inf_axis", "artillery": "lefh", "convoy": "convoy_axis",
                      "fighter_pair": "fw190a", "fighter_four": "bf109", "bomber": "ju88",
                      "patrol": "sboot"},
    ("ww2", "west"): {"flak": "aa37", "light_flak": "bofors", "armour": "sherman",
                      "infantry": "inf_allied", "artillery": "m2a1", "convoy": "convoy_allied",
                      "fighter_pair": "p51", "fighter_four": "p47", "bomber": "b17",
                      "patrol": "lst"},
    ("korea", "east"): {"flak": "raaa", "light_flak": "s60", "armour": "t34",
                        "infantry": "inf_east", "convoy": "convoy_east", "fighter_pair": "mig15",
                        "fighter_four": "mig15", "patrol": "cargo"},
    ("korea", "west"): {"flak": "aa37", "light_flak": "quad50", "armour": "sherman",
                        "infantry": "inf_allied", "convoy": "convoy_allied", "fighter_pair": "f86",
                        "fighter_four": "f86", "bomber": "b17", "patrol": "lst"},
}


# ------------------------------------------------------------------ Range Areas
@dataclass(frozen=True)
class Area:
    """A Range Area: one kind of practice, the Spawn Roles it offers and its Practice Targets."""
    id: str
    label: str
    purpose: str
    roles: tuple
    placement: str                 # ground | air | sea | heli
    radius_m: int
    practice: tuple = ()           # Practice Target kinds, see PRACTICE
    jtac: bool = False


AREAS_JET = [
    Area("sead", "SEAD/DEAD", "Suppress or destroy air defences: HARM shots, radar hunting, "
         "rolling back an air defence network.",
         ("lr_sam", "mr_sam", "sr_sam", "shorad", "ewr"), "ground", 6000, ("radar",)),
    Area("cas", "CAS", "Close air support with a JTAC: armour, troops, artillery under "
         "short-range air defences.",
         ("armour", "infantry", "artillery", "shorad", "manpads"), "ground", 5000,
         ("circle", "strafe", "vehicles"), jtac=True),
    Area("strike", "Strike", "Precision strike on fixed targets: coordinates, laser and "
         "GPS weapons, re-attacks.",
         ("buildings", "bunkers", "depot", "shorad", "convoy"), "ground", 5000, ("buildings",)),
    Area("a2a", "Air-to-Air", "BVR and dogfighting against AI fighters and bombers that "
         "stay inside this area.",
         ("fighter_pair", "fighter_four", "bomber", "helicopter"), "air", 40000),
    Area("antiship", "Anti-Ship", "Maritime strike against patrol boats, frigates and "
         "cruisers.", ("patrol", "frigates", "cruiser"), "sea", 15000, ("ship",)),
    Area("heli", "Helicopter", "Low-level attack close to the helicopter base: armour, troops "
         "and short-range threats.",
         ("armour", "infantry", "shorad", "manpads", "convoy"), "heli", 4000, ("vehicles",),
         jtac=True),
]
AREAS_WARBIRD = [
    Area("flak", "Flak / Ground Attack", "Dive-bombing and strafing flak positions.",
         ("flak", "light_flak", "armour"), "ground", 5000, ("circle", "strafe")),
    Area("cas", "Ground Attack", "Attacking columns, troops and guns in the open.",
         ("armour", "infantry", "artillery", "light_flak", "convoy"), "ground", 5000,
         ("circle", "strafe", "vehicles")),
    Area("strike", "Strike", "Bombing fixed targets.", ("buildings", "depot", "light_flak"),
         "ground", 5000, ("buildings",)),
    Area("a2a", "Air-to-Air", "Dogfighting against AI fighters and bombers that stay inside "
         "this area.", ("fighter_pair", "fighter_four", "bomber"), "air", 30000),
    Area("antiship", "Anti-Ship", "Attacking shipping.", ("patrol", "cargo"), "sea", 12000,
         ("ship",)),
]


def is_warbird(era):
    return era not in JET_ERAS


def areas_for(era, has_sea):
    areas = AREAS_WARBIRD if is_warbird(era) else AREAS_JET
    return [a for a in areas if a.placement != "sea" or has_sea]


def roles_for(era):
    return ROLES_WARBIRD if is_warbird(era) else ROLES_JET


def menu_for(area, era, enemy_side):
    """[(role, [system ids, era default first])] as the F10 menu will list them."""
    roles = roles_for(era)
    defaults = ERA_DEFAULTS[(era, enemy_side)]
    out = []
    for rid in area.roles:
        role = roles[rid]
        ids = list(role.systems[enemy_side])
        default = defaults.get(rid)
        if default in ids:
            ids.remove(default)
            ids.insert(0, default)
        if ids:
            out.append((role, ids))
    return out


def all_systems(era, enemy_side, has_sea):
    """Every system id a range for this era and side can spawn, without duplicates."""
    seen = []
    for area in areas_for(era, has_sea):
        for _, ids in menu_for(area, era, enemy_side):
            seen += [i for i in ids if i not in seen]
    return seen


def aliases(system):
    """Marker Spawn names for a system: its id, label words and declared aliases, lower case."""
    names = {system.id, *system.aliases}
    names.add(system.label.split(" ")[0].lower())
    return sorted({n.lower().replace(" ", "") for n in names})


# ------------------------------------------------------------- Practice Targets
# Kind -> what the generator places: ("static", [(type, bearing, metres)]) or
# ("group", [(unit type, bearing, metres)]) for a radiating target, placed at the area centre.
PRACTICE = {
    "circle": ("static", [(FORT.White_Tyre, 0, 0)] + ring(FORT.White_Tyre, 8, 50)
               + ring(FORT.Black_Tyre, 12, 100)),
    "strafe": ("static", [(FORT.White_Tyre, 90, 400 + 25 * i) for i in range(4)]),
    "vehicles": ("static", [(UNARMED.Ural_375, 200, 300 + 40 * i) for i in range(4)]),
    "buildings": ("static", [(WH.Warehouse, 0, 0), (FORT.Small_werehouse_1, 90, 80),
                             (FORT.Military_staff, 180, 90)]),
    "radar": ("group", [(AD.P_19_s_125_sr, 0, 0), (UNARMED.Ural_375, 180, 60)]),
    "ship": ("static", [(ships.Dry_cargo_ship_1, 0, 0)]),
}
PRACTICE_LABELS = {"circle": "Bombing circle", "strafe": "Strafe pit", "vehicles": "Target vehicles",
                   "buildings": "Target buildings", "radar": "Radar (doesn't shoot)",
                   "ship": "Cargo ship"}


# ------------------------------------------------------------------ Default Roster
# (aircraft id, Flight Role of flight 1 (hot start), Flight Role of flight 2 (cold start), base)
DEFAULT_ROSTER = [
    ("FA-18C_hornet", "sead", "aa", "carrier"),
    ("F-16C_50", "sead", "cas", "airfield"),
    ("F-15ESE", "strike", "aa", "airfield"),
    ("F-14B", "aa", "strike", "carrier"),
    ("A-10C_2", "cas", "cas", "airfield"),
    ("AV8BNA", "cas", "strike", "airfield"),
    ("F-4E-45MC", "sead", "aa", "airfield"),
    ("M-2000C", "aa", "cas", "airfield"),
    ("JF-17", "antiship", "aa", "airfield"),
    ("AH-64D_BLK_II", "cas", "cas", "airfield"),
    ("Ka-50_3", "cas", "cas", "airfield"),
    ("Mi-24P", "cas", "cas", "airfield"),
    ("UH-1H", "cas", "cas", "airfield"),
]
FLIGHT_ROLES = {"aa": "Air-to-Air", "sead": "SEAD", "cas": "CAS", "strike": "Strike",
                "antiship": "Anti-Ship", "control": "Range Control"}
# Range Control seats (ADR 0001): one seat each, so the Range Admin can fly a jet or a helicopter.
RANGE_CONTROL_ROSTER = ["F-16C_50", "UH-1H"]
CONTROL_SUFFIX = " - Range Control"     # group names end with this; the server hook matches it
# Flight Role -> the Range Area its route goes to (helicopters fly CAS to the Helicopter area).
ROLE_AREA = {"aa": "a2a", "sead": "sead", "cas": "cas", "strike": "strike", "antiship": "antiship"}


def default_roster(has_carrier):
    """Flight requests for the Default Roster: two 2-ships per type, hot then cold, then the
    one-seat Range Control flights."""
    out = []
    for ac, role1, role2, base in DEFAULT_ROSTER:
        b = base if has_carrier else "airfield"
        out.append({"aircraft": ac, "slots": 2, "start": "hot", "base": b, "role": role1})
        out.append({"aircraft": ac, "slots": 2, "start": "cold", "base": b, "role": role2})
    for ac in RANGE_CONTROL_ROSTER:
        out.append({"aircraft": ac, "slots": 1, "start": "hot", "base": "airfield", "role": "control"})
    return out


def check_menus():
    """Every F10 menu level fits DCS's limit, for every era and side. Returns problems."""
    problems = []
    for (era, side) in ERA_DEFAULTS:
        for has_sea in (True, False):
            areas = areas_for(era, has_sea)
            if len(areas) + 1 > MENU_LIMIT:       # + Range Control / help
                problems.append(f"{era}/{side}: {len(areas)} areas")
            for area in areas:
                menu = menu_for(area, era, side)
                if len(menu) + 2 > MENU_LIMIT:    # + Difficulty, Clear
                    problems.append(f"{era}/{side} {area.id}: {len(menu)} roles")
                for role, ids in menu:
                    if len(ids) > MENU_LIMIT:
                        problems.append(f"{era}/{side} {area.id}/{role.id}: {len(ids)} systems")
                    missing = [i for i in ids if i not in SYSTEMS]
                    if missing:
                        problems.append(f"{area.id}/{role.id}: unknown {missing}")
    return problems
