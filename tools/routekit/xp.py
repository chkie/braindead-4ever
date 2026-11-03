# SPDX-License-Identifier: GPL-3.0-or-later
"""Experience rules, the same as Braindead4Ever/Routes/XP.lua (the addon's XP balance).

Classic rules with one measured Forever change: a creature below the character gives
(5 x creature level + 45) reduced by the level difference, not (5 x character level + 45) as in
Classic (forever-bugs #138, closed as "Not A Bug" by a Blizzard developer on 2026-09-28; Polestar
#30; brain chapter 06 §8; report DR 22b). tools/tests/fixtures/xp_cases.json holds the cases both
implementations must agree on; spec/route_xp_spec.lua reads the same file.

Sources (read 2026-11-01): warcraft.wiki.gg "Experience to level", "Mob experience",
"Experience point"; cmangos/mangos-classic src/game/Tools/Formulas.h.
"""

import math

# XP from level n to n + 1, levels 1 to 59 (index n - 1). Sum 4,084,700 (warcraft.wiki.gg).
TO_LEVEL = (
    400, 900, 1400, 2100, 2800, 3600, 4500, 5400, 6500, 7600,
    8800, 10100, 11400, 12900, 14400, 16000, 17700, 19400, 21300, 23200,
    25200, 27300, 29400, 31700, 34000, 36400, 38900, 41400, 44300, 47400,
    50800, 54500, 58600, 62800, 67100, 71600, 76100, 80800, 85700, 90700,
    95800, 101000, 106300, 111800, 117500, 123200, 129100, 135100, 141200, 147500,
    153900, 160400, 167100, 173900, 180800, 187900, 195000, 202300, 209800,
)
MAX_LEVEL = 60
_REDUCED = {6: 0.8, 7: 0.6, 8: 0.4, 9: 0.2}


def _round(x):
    """Lua's math.floor(x + 0.5): halves round up (Python's round() rounds them to even)."""
    return math.floor(x + 0.5)


def to_level(level):
    """XP from `level` to `level + 1`, or None at the level cap."""
    return TO_LEVEL[level - 1] if 1 <= level < MAX_LEVEL else None


def total_to(level):
    """XP from the start of level 1 to the start of `level` (499,000 for level 30)."""
    return sum(TO_LEVEL[: max(0, level - 1)])


def _trivial(level, mob_level):
    """Levels below the character at which a creature gives no XP any more (as XP.lua)."""
    if mob_level >= level:
        return False
    band = level // 5
    if band <= 1:
        rng = 4
    elif band <= 3:
        rng = 5
    elif band <= 5:
        rng = 6
    elif band <= 7:
        rng = 7
    else:
        rng = min(band, 12)
    return level - mob_level > rng


def zero_diff(level):
    """The level gap at which kill XP would reach zero (vmangos table, as XP.lua)."""
    for limit, zd in ((8, 5), (10, 6), (12, 7), (16, 8), (20, 9), (30, 11), (40, 12), (45, 13), (50, 14), (55, 15), (60, 16)):
        if level < limit:
            return zd
    return 17


def kill_xp(level, mob_level=None, elite=False):
    """XP for a solo kill without rested bonus. At or above the character: (5 x level + 45),
    +5 % per level above, at most +4. Below (Forever): (5 x creature level + 45) x (1 - diff / ZD).
    Elite doubles."""
    if mob_level is None:
        mob_level = level
    if mob_level >= level:
        xp = (level * 5 + 45) * (1 + 0.05 * min(mob_level - level, 4))
    elif _trivial(level, mob_level):
        return 0
    else:
        xp = (mob_level * 5 + 45) * (1 - (level - mob_level) / zero_diff(level))
    if elite:
        xp *= 2
    return _round(xp)


def quest_factor(quest_level, level):
    """Share of the full quest XP at `level`: 1 up to quest level + 5, then 0.8/0.6/0.4/0.2, then 0.1."""
    diff = level - (quest_level if quest_level is not None else level)
    if diff <= 5:
        return 1.0
    return _REDUCED.get(diff, 0.1)


def quest_xp(full, quest_level, level):
    """Quest XP at `level`: full up to quest level + 5, then reduced and rounded to a multiple of 5."""
    if not full or full <= 0:
        return 0
    f = quest_factor(quest_level, level)
    if f == 1.0:
        return full
    return _round(full * f / 5) * 5
