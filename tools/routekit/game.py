# SPDX-License-Identifier: GPL-3.0-or-later
"""Game constants for WoW: Forever 1.60.1 that the route tools need.

Sources (no value here is guessed):
- races, classes and the 56 combinations: client table CharBaseInfo (product wowf, build
  1.60.1.70707), ChrRaces PlayableRaceBit, counted in brain chapter 14 §1 on 2026-11-01;
- uiMapIDs: client tables UiMap/UiMapAssignment (wowf 70707), brain chapter 07 §7;
- start zones: Classic assignment from brain chapter 14 code pattern 1 (to be confirmed in game),
  Zephras for both Skyborne races.
"""

ALLIANCE = "Alliance"
HORDE = "Horde"

# raceID -> (token, faction, PlayableRaceBit)
RACES = {
    1: ("HUMAN", ALLIANCE, 0),
    3: ("DWARF", ALLIANCE, 2),
    4: ("NIGHTELF", ALLIANCE, 3),
    7: ("GNOME", ALLIANCE, 6),
    95: ("SKYBORNE_A", ALLIANCE, 32),
    2: ("ORC", HORDE, 1),
    5: ("UNDEAD", HORDE, 4),
    6: ("TAUREN", HORDE, 5),
    8: ("TROLL", HORDE, 7),
    96: ("SKYBORNE_H", HORDE, 33),
}
RACE_BY_TOKEN = {v[0]: k for k, v in RACES.items()}

# classID -> token (classFile)
CLASSES = {
    1: "WARRIOR",
    2: "PALADIN",
    3: "HUNTER",
    4: "ROGUE",
    5: "PRIEST",
    7: "SHAMAN",
    8: "MAGE",
    9: "WARLOCK",
    11: "DRUID",
}
CLASS_BY_TOKEN = {v: k for k, v in CLASSES.items()}

# CharBaseInfo wowf 70707: allowed classes per race (brain chapter 14 §1 table).
COMBOS = {
    1: (1, 2, 3, 4, 5, 8, 9),
    3: (1, 2, 3, 4, 5, 7),
    7: (1, 4, 5, 8, 9),
    4: (1, 3, 4, 5, 11),
    95: (1, 3, 4, 8, 11),
    2: (1, 3, 4, 7, 8, 9),
    5: (1, 2, 4, 5, 8, 9),
    8: (1, 3, 4, 5, 7, 8, 9),
    6: (1, 3, 7, 11),
    96: (1, 3, 4, 7, 11),
}


def all_combos():
    """All (raceID, classID) pairs, sorted by faction, race, class."""
    out = []
    for race in sorted(RACES, key=lambda r: (RACES[r][1] != ALLIANCE, r)):
        for cls in COMBOS[race]:
            out.append((race, cls))
    return out


def faction_of(race):
    return RACES[race][1]


def races_of(faction):
    return [r for r, v in RACES.items() if v[1] == faction]


def races_from_mask(mask):
    """Client race mask (64 bit, PlayableRaceBit) -> set of raceIDs; 0 means every race."""
    if not mask:
        return None
    out = {r for r, v in RACES.items() if mask >> v[2] & 1}
    return out or set()


def classes_from_mask(mask):
    """Client class mask (bit = classID - 1) -> set of classIDs; 0 means every class."""
    if not mask:
        return None
    out = {c for c in CLASSES if mask >> (c - 1) & 1}
    return out or set()


# uiMapIDs (Forever keeps the Classic Era IDs, chapter 07 §7).
ZONES = {
    1411: "Durotar",
    1412: "Mulgore",
    1413: "The Barrens",
    1416: "Alterac Mountains",
    1417: "Arathi Highlands",
    1418: "Badlands",
    1420: "Tirisfal Glades",
    1421: "Silverpine Forest",
    1424: "Hillsbrad Foothills",
    1426: "Dun Morogh",
    1429: "Elwynn Forest",
    1431: "Duskwood",
    1432: "Loch Modan",
    1433: "Redridge Mountains",
    1434: "Stranglethorn Vale",
    1436: "Westfall",
    1437: "Wetlands",
    1438: "Teldrassil",
    1439: "Darkshore",
    1440: "Ashenvale",
    1441: "Thousand Needles",
    1442: "Stonetalon Mountains",
    1443: "Desolace",
    1445: "Dustwallow Marsh",
    1453: "Stormwind City",
    1454: "Orgrimmar",
    1455: "Ironforge",
    1456: "Thunder Bluff",
    1457: "Darnassus",
    1458: "Undercity",
    2521: "Zephras Isle",
    2665: "Zephras Isle",
}

# Zones whose world frame changed between Classic Era and Forever (chapter 07 §7):
# map-percent coordinates from Classic-based sources are not valid there.
CHANGED_FRAMES = {1412, 1423, 1433, 1453}

# Continents and other maps that are not a zone for routing purposes.
NOT_ZONES = {947, 1414, 1415, 1463, 1464}

# Start module per raceID (chapter 14 code pattern 1; Classic assignment, confirm in game).
START_MODULE = {
    1: "ELWYNN",
    3: "DUNMOROGH",
    7: "DUNMOROGH",
    4: "TELDRASSIL",
    95: "ZEPHRAS_A",
    2: "DUROTAR",
    8: "DUROTAR",
    6: "MULGORE",
    5: "TIRISFAL",
    96: "ZEPHRAS_H",
}

# Quest IDs from 70000 up are new in Forever (DB2 diff, chapter 08 §9: 1,808 of 1,811 there).
NEW_QUEST_MIN_ID = 70000


def is_new_quest(q):
    return q >= NEW_QUEST_MIN_ID
