# SPDX-License-Identifier: GPL-3.0-or-later
"""Prerequisites from player observations. The same rule runs in the addon
(Pathmark/Routes/Prereq.lua); tools/tests/fixtures/prereq_cases.json holds the cases both must
agree on.

An observation of quest q is made when a player takes q, or sees an NPC offer q:
  t  observer token: a hash of the random install ID and q, so one player counts once per quest
     and observations of different quests cannot be linked
  l  link: the quest the player turned in directly before taking q, at the NPC that gives q, at
     most LINK_SECONDS earlier (0 = none). A follow-up is offered by the NPC that takes the quest
     before it (chain heuristic, QuestieDB #78, DR 20 §5 rule 3).
  u  unlock: 1 when the same NPC listed its offers in that visit before the turn-in and q was not
     among them, so the server offered q only after the linked quest was handed in
  d  candidates the player had already done (turned in shortly before, or the completion flag)
  n  candidates the player had not done although q was offered or taken (refutation)

Rule (chosen values, revisable; docs/ROUTE-RUNTIME.md §Prerequisites from player data):
  links(c), unlocks(c): observers whose link is c (and who saw the unlock); done(c): observers
  with c as link or in d; c is refuted when any observer has c in n.
  "observed": c not refuted, links(c) >= MIN_LINKS, unlocks(c) >= 1, done(c) >= MIN_SUPPORT.
  "observed-none": no such c, at least MIN_NONE observers, every candidate done by at least
  max(MIN_SUPPORT, NONE_SHARE * observers) observers refuted, no unrefuted candidate with
  MIN_LINKS links.
  Measured with the simulated runs in tools/tests/test_own_data.py: co-occurrence alone gave 69
  wrong prerequisites, the link without the unlock still 2 (a quest taken elsewhere and handed in
  at the hub that offers the next quest anyway); with the unlock and the offer lists none. Without
  the recent turn-ins in d, chains whose follow-up comes from another NPC came out as "none"
  (2 in the run with hidden source chains); with them none.
"""

MIN_LINKS = 2
MIN_SUPPORT = 3
MIN_NONE = 5
NONE_SHARE = 0.5
LIST_MAX = 10
LINK_SECONDS = 120


class Observations:
    def __init__(self):
        self.obs = {}  # q -> token -> (link, unlock, d, n)
        self.refuted = {}  # q -> set of candidate IDs

    def add(self, q, token, link=0, unlock=0, d=(), n=()):
        if not token or not q:
            return
        if not link or link == q:
            link, unlock = 0, 0
        d = tuple(x for x in d if x != q)[:LIST_MAX]
        n = tuple(x for x in n if x != q)[:LIST_MAX]
        self.obs.setdefault(q, {})[token] = (link, 1 if unlock else 0, d, n)
        if n:
            self.refuted.setdefault(q, set()).update(n)

    def candidates(self, q):
        """Every quest some observer linked to q or reported as done, refuted ones included."""
        out = set()
        for link, _, d, _ in self.obs.get(q, {}).values():
            if link:
                out.add(link)
            out.update(d)
        return out

    def counts(self, q):
        links, unlocks, done = {}, {}, {}
        for link, unlock, d, _ in self.obs.get(q, {}).values():
            seen = set(d)
            if link:
                links[link] = links.get(link, 0) + 1
                unlocks[link] = unlocks.get(link, 0) + unlock
                seen.add(link)
            for c in seen:
                done[c] = done.get(c, 0) + 1
        return links, unlocks, done

    def result(self, q):
        """(state, groups, observers) with state "observed", "observed-none" or "unknown"."""
        obs = self.obs.get(q, {})
        refuted = self.refuted.get(q, set())
        links, unlocks, done = self.counts(q)
        pre = sorted(
            c
            for c, k in links.items()
            if c not in refuted and k >= MIN_LINKS and unlocks.get(c, 0) >= 1 and done.get(c, 0) >= MIN_SUPPORT
        )
        if pre:
            return "observed", [[c] for c in pre], len(obs)
        block = max(MIN_SUPPORT, NONE_SHARE * len(obs))
        if (
            len(obs) >= MIN_NONE
            and all(c in refuted for c, k in done.items() if k >= block)
            and all(k < MIN_LINKS for c, k in links.items() if c not in refuted)
        ):
            return "observed-none", [], len(obs)
        return "unknown", [], len(obs)

    def quests(self):
        return sorted(self.obs)
