# SPDX-License-Identifier: GPL-3.0-or-later
"""Game constants for WoW: Forever 1.60.1 that the route tools need.

Sources (no value here is guessed; client files are not a source, brain chapter 16 §5). The open
data named here is the same that data/sources holds (licences: NOTICE); "in game" names the addon
API call that confirms the value once the live client runs.
- race IDs and factions: All The Things, .contrib/.db/shared/constants/raceIDs.lua (MIT, commit
  f8d538a), Skyborne 95 (Alliance) and 96 (Horde); in game UnitRace (third return).
- bit of each race in a quest race mask: on 1,747 of 1,896 quests Polestar forever-db racesMask
  and All The Things races name the same races (data/sources, counted 2026-11-03); no swap of two
  bits raises that count, and Polestar uses bits 0 to 7, 32 and 33 only.
- class IDs and tokens: in game GetClassInfo(classID) and UnitClass; class mask bit = classID - 1
  agrees on all 488 quests with both Polestar classesMask and All The Things classes.
- the 56 race and class combinations: brain chapter 14 §1; 20 of them seen played at the start
  positions of EG Link (data/sources/eglink/starts.jsonl), none outside the list. The other 36
  have no open source yet: confirm in the character creation of the live client.
- uiMapIDs: Polestar forever-db table ui_map (data/sources/polestar/ui_map.jsonl), which lists
  every ID below except 947 (Azeroth); in game C_Map.GetMapInfo.
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

# Allowed classes per race (brain chapter 14 §1 table; see the module docstring for the evidence).
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


# uiMapIDs (Forever keeps the Classic Era IDs; Polestar ui_map, chapter 07 §7).
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
# map-percent coordinates from Classic-based sources are not valid there. Forever frames: Polestar
# ui_map; warcraft.wiki.gg "Forever map comparison" marks all four as changed. In game:
# C_Map.GetWorldPosFromMapPos(uiMapID, CreateVector2D(0, 0)) and (1, 1).
CHANGED_FRAMES = {1412, 1423, 1433, 1453}

# Continents and other maps that are not a zone for routing purposes (Polestar ui_map, 947 Azeroth).
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

# Quest IDs from 70000 up are new in Forever: 553 of the 555 quests All The Things marks as added or
# created in 1.60.1 have such an ID (data/sources/att/quests.jsonl timeline, counted 2026-11-03).
NEW_QUEST_MIN_ID = 70000


def is_new_quest(q):
    return q >= NEW_QUEST_MIN_ID
