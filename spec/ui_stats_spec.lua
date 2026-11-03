-- SPDX-License-Identifier: GPL-3.0-or-later
-- "Your run" (Welle 8) in a game session: the route feeds the tally, the page opens only on the
-- player's command, the comparison with the class needs Stats.MIN_RUNS runs and is never built in a
-- fight, the review card at level 10, 20 and 30 comes once per character, the saved tables migrate
-- from the run vault. Counter-checks at the end: with a guard taken out, the same test sees the fault.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

local TOKEN = "mine01"

-- A vault text as Collector/Proto.lua formats it.
local function msg(tok, class, mode, kind, sec, secs, opts)
	opts = opts or {}
	return ("s;1;%s;%d;%d;%s;%s;%d;%d;%d;%d;%d;%d;%d"):format(
		tok,
		opts.race or 1,
		class,
		mode,
		kind,
		sec,
		opts.version or 0,
		secs,
		opts.xp or 1000,
		opts.inOrder or 100,
		opts.level or sec + 1,
		opts.day or 20762
	)
end

-- BraindeadForeverCollectDB with a run vault of the given texts.
local function collect(texts, mine)
	return {
		schema = 1,
		install = "inst00000000",
		runs = { list = texts, first = 1, last = #texts, mine = mine or {} },
	}
end

-- Other warriors' level sections: n runs per level for the levels given.
local function others(levels, n, secs)
	local texts = {}
	for i = 1, n do
		for _, l in ipairs(levels) do
			texts[#texts + 1] = msg(("o%05d"):format(i), 1, "s", "l", l, (secs or 600) + i * 10)
		end
	end
	return texts
end

-- Whole levels 1 to `upto` of this character, as the tally keeps them.
local function history(upto, secs)
	local lv = {}
	for l = 1, upto do
		lv[l] = {
			s = secs or 600,
			x = 1000,
			q = 600,
			k = 300,
			c = 120,
			m = 240,
			f = 0,
			p = 0,
			n = 4,
			d = 0,
			b = 1,
			mo = "s",
			o = 100,
			full = true,
		}
	end
	return lv
end

-- A character standing at `level` with the whole levels before it and the route's level section.
local function veteran(level, opts)
	opts = opts or {}
	return {
		run = TOKEN,
		stats = { schema = 1, lv = history(level - 1, opts.secs), mods = {}, recap = opts.recap or {} },
		route = { lvl = { l = level, full = true, secs = 500, xp = 900, guided = 500, n = 4, d = 4 } },
	}
end

local function login(opts)
	opts = opts or {}
	return S.login({
		level = opts.level or 1,
		xp = opts.xp or 0,
		char = opts.char,
		saved = opts.saved,
		locale = opts.locale,
		combat = opts.combat,
		probe = opts.probe,
		before = function(W)
			_G.BraindeadForeverCollectDB = opts.collect
			if opts.before then
				opts.before(W)
			end
		end,
	})
end

-- Runs the comparison build until it is done (the driver's OnUpdate, one slice per call).
local function drain(ns, limit)
	local d = ns.RunStats.driver
	local n = 0
	while rawget(d, "shown") and n < (limit or 1000) do
		d.scripts.OnUpdate(d, 1 / 60)
		n = n + 1
	end
	return n
end

local function levelUp(ns, to)
	local P = wow.world.player
	P.level, P.xp = to, 0
	wow.fire("PLAYER_LEVEL_UP", to)
	return ns
end

local function shown(name)
	local f = _G[name]
	return f ~= nil and rawget(f, "shown") == true
end

describe("Your run: data from the route", function()
	it("closes each level with the seconds of its run section and splits them by activity", function()
		local ns = login({ level = 1, xp = 0 })
		local P, RS = wow.world.player, ns.RunStats
		for i = 1, 10 do
			if i == 3 then
				wow.fire("PLAYER_STARTED_MOVING")
			elseif i == 6 then
				wow.fire("PLAYER_STOPPED_MOVING")
				S.combat(true)
			elseif i == 8 then
				S.combat(false)
			end
			wow.advance(60)
			P.xp = P.xp + 30
			wow.fire("PLAYER_XP_UPDATE", "player")
		end
		wow.fire("PLAYER_DEAD")
		levelUp(ns, 2)
		local r = RS.Char().lv[1]
		local own = ns.Collector.runs.db.list[ns.Collector.runs.db.last]
		-- the vault's section: 601 s (half a second of the login, rounded), 300 XP
		assert.matches(";l;1;0;601;300;", own, 1, true)
		assert.are.equal(600.5, r.s)
		assert.are.equal(300, r.x)
		assert.are.equal(1, r.d)
		assert.is_true(r.full)
		assert.are.equal(180, math.floor(r.m + 0.5)) -- minutes 3 to 5 moving
		assert.are.equal(120, math.floor(r.c + 0.5)) -- minutes 6 and 7 fighting
		assert.are.equal(2, RS.Tally().level)
		assert.are.same({}, wow.errors)
	end)

	it("counts quests handed in, by QUEST_TURNED_IN or by the completion flag", function()
		local ns = login({ level = 3, xp = 100 })
		local r = ns.RunStats.Char().lv[3]
		wow.fire("QUEST_TURNED_IN", 33, 250, 0)
		wow.fire("QUEST_REMOVED", 33)
		wow.world.completed[783] = true
		wow.fire("QUEST_REMOVED", 783) -- no QUEST_TURNED_IN came (Forever trap)
		wow.advance(2)
		assert.are.equal(2, r.n)
		assert.are.equal(250, r.q)
	end)
end)

describe("Your run: the page", function()
	it("opens only on the player's command: slash, right-click menu, minimap button menu", function()
		local ns = login({ level = 5, xp = 100 })
		wow.advance(10)
		assert.is_false(shown("BraindeadForeverStatsFrame"))
		assert.is_false(shown("BraindeadForeverRecapFrame"))
		assert.is_false(rawget(ns.RunStats.driver, "shown") == true)
		SlashCmdList.BRAINDEADFOREVER("stats")
		assert.is_true(shown("BraindeadForeverStatsFrame"))
		SlashCmdList.BRAINDEADFOREVER("stats") -- toggles
		assert.is_false(shown("BraindeadForeverStatsFrame"))
		S.item(S.menu(ns), "Your run").fn()
		assert.is_true(shown("BraindeadForeverStatsFrame"))
		_G.BraindeadForeverStatsFrame:Hide()
		ns.MinimapButton.Click("RightButton")
		S.item(wow.menu, "Your run").fn()
		assert.is_true(shown("BraindeadForeverStatsFrame"))
		assert.are.same({}, wow.errors)
	end)

	it("compares a level only from MIN_RUNS runs of other players on, else collecting", function()
		local need = 10
		local ns = login({ level = 4, char = veteran(4), collect = collect(others({ 1, 2 }, need - 1)) })
		assert.are.equal(need, ns.Stats.MIN_RUNS)
		local SP = ns.StatsPage
		SlashCmdList.BRAINDEADFOREVER("stats")
		drain(ns)
		local rows = SP.rendered
		-- newest level on top: 4 (running), 3, 2, 1
		assert.are.equal("4", rows[1].cells[1])
		assert.matches("running", rows[1].cells[2])
		assert.are.equal("collecting", rows[3].cells[3])
		assert.are.equal("", rows[3].cells[4])
		assert.is_nil(rows[3].median)
		assert.are.equal("Comparison: collecting data (9 of 10 runs)", SP.TipLines("level", rows[3].data)[8].text)

		ns = login({ level = 4, char = veteran(4), collect = collect(others({ 1, 2 }, need)) })
		SP = ns.StatsPage
		SlashCmdList.BRAINDEADFOREVER("stats")
		drain(ns)
		rows = SP.rendered
		assert.are.equal("11 min", rows[3].cells[3]) -- median of 610..700 s: 655 s
		assert.are.equal("100 %", rows[3].cells[4]) -- 600 s is faster than every other run
		assert.are.equal(655, rows[3].median)
		-- hovering the row: GameTooltip with the details of level 2
		local row = SP.frame.rows[3]
		row.scripts.OnEnter(row)
		assert.are.same({
			"Level 2",
			"Active play: 10 min",
			"1,000 XP • 6,000 XP per hour",
			"XP from quests 60 % • enemies 30 % • other 10 %",
			"Fighting 20 % • moving 40 % • flying 0 % • other 40 %",
			"Quests: 4 done • 1 skipped",
			"Deaths: 0",
			"Way of play: follows the route",
			"Median of your class: 11 min from 10 runs",
			"Faster than 100 % of these runs",
		}, wow.world.tooltip.lines)
		assert.are.same({}, wow.errors)
	end)

	it("shows sections and best times on their tabs, with race and class names", function()
		local char = veteran(11)
		char.stats.mods[1] = { num = 1, v = 1, s = 900, o = 100, mo = "s", l = 3 }
		local ns = login({
			level = 11,
			char = char,
			saved = {
				stats = { schema = 1, best = { [10] = { s = 5000, r = 3, c = 3, g = "r", d = 20760, t = "other1" } } },
			},
		})
		local SP = ns.StatsPage
		SlashCmdList.BRAINDEADFOREVER("stats")
		drain(ns)
		_G.BraindeadForeverStatsFrameTab2.scripts.OnClick(_G.BraindeadForeverStatsFrameTab2)
		assert.are.equal(1, #SP.rendered)
		assert.are.equal("Section 1", SP.rendered[1].cells[1])
		_G.BraindeadForeverStatsFrameTab3.scripts.OnClick(_G.BraindeadForeverStatsFrameTab3)
		-- the dwarf hunter's 5000 s stay the best of the account (this character's band took 5400 s)
		assert.are.equal("1–10", SP.rendered[1].cells[1])
		assert.are.equal("Dwarf • Hunter • follows the route", SP.rendered[1].cells[3])
		assert.are.same({}, wow.errors)
	end)

	it("German: header, summary and a level row", function()
		local ns = login({ level = 3, locale = "deDE", char = veteran(3) })
		SlashCmdList.BRAINDEADFOREVER("stats")
		drain(ns)
		local W = _G.BraindeadForeverStatsFrame
		assert.are.equal("Dein Lauf", W.TitleText.text)
		assert.are.equal("Stufe 3 • Mensch • Krieger", W.head.text)
		assert.are.equal("Aktive Spielzeit", W.sum[1].label.text)
		assert.matches("läuft", ns.StatsPage.rendered[1].cells[2])
	end)
end)

describe("Your run: never in a fight", function()
	it("the page waits for the end of the fight, and so does the comparison build", function()
		local ns = login({ level = 4, char = veteran(4), collect = collect(others({ 1, 2, 3 }, 40)) })
		S.combat(true)
		SlashCmdList.BRAINDEADFOREVER("stats")
		assert.is_false(shown("BraindeadForeverStatsFrame"))
		assert.is_false(ns.RunStats.Building())
		S.combat(false)
		assert.is_true(shown("BraindeadForeverStatsFrame"))
		assert.is_true(ns.RunStats.Building())
		-- a fight starts while the build runs: not one more vault text is read
		ns.RunStats.SLICE = 10
		local d = ns.RunStats.driver
		d.scripts.OnUpdate(d, 1 / 60)
		local fed = ns.RunStats.Job().seq
		S.combat(true)
		for _ = 1, 50 do
			d.scripts.OnUpdate(d, 1 / 60)
		end
		local job = ns.RunStats.Job()
		assert.is_table(job, "the build ran to its end in the fight")
		assert.are.equal(fed, job.seq)
		S.combat(false)
		drain(ns)
		assert.is_false(ns.RunStats.Building())
		assert.are.same({}, wow.blocked)
		assert.are.same({}, wow.errors)
	end)
end)

describe("Your run: review card", function()
	it("comes once at level 10, after the level-up banner, and never again for that level", function()
		local ns = login({ level = 9, char = veteran(9), collect = collect(others({ 1, 2, 3, 4, 5, 6, 7, 8, 9 }, 12)) })
		levelUp(ns, 10)
		assert.is_false(shown("BraindeadForeverRecapFrame"))
		wow.advance(3)
		drain(ns)
		assert.is_true(shown("BraindeadForeverRecapFrame"))
		local R = _G.BraindeadForeverRecapFrame
		assert.are.equal("Level 10 reached", R.head.text)
		assert.are.equal("Mensch • Krieger • follows the route", R.who.text) -- the stand-in client names them in German
		assert.are.equal("Active play time, level 1 to 10", R.timeLabel.text)
		assert.are.equal("1 h 28 min", R.time.text) -- levels 1 to 8 at 600 s, level 9 the route section's 500.5 s
		assert.are.equal("Median of your class", R.facts[1].label.text)
		assert.matches("%(12 runs%)$", R.facts[1].value.text)
		assert.are.equal("Braindead 4ever", R.foot.text)
		assert.is_true(ns.RunStats.Char().recap[10])
		R:Hide()
		-- the same level-up again, a zone change and a new session: the card stays closed
		levelUp(ns, 10)
		wow.fire("ZONE_CHANGED_NEW_AREA")
		wow.advance(5)
		drain(ns)
		assert.is_false(shown("BraindeadForeverRecapFrame"))
		local char = _G.BraindeadForeverCharDB
		ns = login({ level = 10, char = char })
		wow.advance(5)
		drain(ns)
		assert.is_false(shown("BraindeadForeverRecapFrame"))
		assert.are.same({}, wow.errors)
	end)

	it("waits for the end of a fight and for leaving an instance", function()
		local ns = login({ level = 19, char = veteran(19) })
		S.combat(true)
		levelUp(ns, 20)
		wow.advance(5)
		drain(ns)
		assert.is_false(shown("BraindeadForeverRecapFrame"))
		wow.world.instance = true
		S.combat(false)
		drain(ns)
		assert.is_false(shown("BraindeadForeverRecapFrame"))
		wow.advance(5)
		wow.fire("ZONE_CHANGED_NEW_AREA")
		wow.advance(5)
		drain(ns)
		assert.is_false(shown("BraindeadForeverRecapFrame"))
		wow.world.instance = false
		wow.fire("ZONE_CHANGED_NEW_AREA")
		wow.advance(5)
		drain(ns)
		assert.is_true(shown("BraindeadForeverRecapFrame"))
		assert.are.equal("Level 20 reached", _G.BraindeadForeverRecapFrame.head.text)
		assert.are.same({}, wow.blocked)
	end)

	it("switched off in the settings or on the card: no card, nothing waits", function()
		local ns = login({ level = 9, char = veteran(9) })
		ns.UI.Set("recap", false)
		levelUp(ns, 10)
		wow.advance(5)
		drain(ns)
		assert.is_false(shown("BraindeadForeverRecapFrame"))
		assert.is_nil(ns.RunStats.PendingRecap())
		ns.UI.Set("recap", true)
		wow.fire("ZONE_CHANGED_NEW_AREA")
		wow.advance(5)
		assert.is_false(shown("BraindeadForeverRecapFrame"))
		-- the check box on the card writes the same option
		ns = login({ level = 19, char = veteran(19) })
		levelUp(ns, 20)
		wow.advance(5)
		drain(ns)
		local R = _G.BraindeadForeverRecapFrame
		assert.is_true(R.check:GetChecked())
		R.check:SetChecked(false)
		R.check.scripts.OnClick(R.check)
		assert.is_false(ns.UI.Get("recap"))
	end)

	it("no card at other levels and none without a single whole level of the band", function()
		local ns = login({ level = 11, char = veteran(11) })
		levelUp(ns, 12)
		wow.advance(5)
		assert.is_false(shown("BraindeadForeverRecapFrame"))
		local fresh = { run = TOKEN, route = { lvl = { l = 9, secs = 50, xp = 10, guided = 0, n = 0, d = 0 } } }
		ns = login({ level = 9, char = fresh }) -- the addon came in during level 9
		levelUp(ns, 10)
		wow.advance(5)
		drain(ns)
		assert.is_false(shown("BraindeadForeverRecapFrame"))
		assert.is_nil(ns.RunStats.PendingRecap())
	end)
end)

describe("Your run: saved tables", function()
	it("take the own sections over from the run vault and fill the account's best times", function()
		local texts = {}
		for l = 1, 9 do
			texts[#texts + 1] = msg(TOKEN, 1, "s", "l", l, 500, { xp = 800 })
			texts[#texts + 1] = msg("alt001", 3, "f", "l", l, 400, { race = 3 }) -- another own character
		end
		texts[#texts + 1] = msg(TOKEN, 1, "s", "m", 4711, 300, { version = 2, level = 4 })
		texts[#texts + 1] = msg("other1", 1, "s", "l", 1, 100) -- someone else
		local ns = login({
			level = 10,
			char = { run = TOKEN },
			collect = collect(texts, { [TOKEN] = true, alt001 = true }),
		})
		local char, acct = ns.RunStats.Char(), ns.RunStats.Account()
		assert.are.equal(1, char.schema)
		assert.are.same({ s = 500, x = 800, mo = "s", o = 100, full = true }, char.lv[1])
		assert.are.equal(
			9,
			(function()
				local n = 0
				for l in pairs(char.lv) do
					n = n + (l < 10 and 1 or 0)
				end
				return n
			end)()
		)
		assert.are.same({ num = 4711, v = 2, s = 300, o = 100, mo = "s", l = 4 }, char.mods[1])
		assert.are.same({ s = 3600, r = 3, c = 3, g = "f", d = 20762, t = "alt001" }, acct.best[10])
		assert.are.equal(1, acct.schema)
		assert.are.equal(_G.BraindeadForeverDB.stats, acct)
	end)

	it("write the live tables back into whatever the globals hold at logout", function()
		local ns = login({ level = 3, char = veteran(3) })
		local char = ns.RunStats.Char()
		_G.BraindeadForeverCharDB = {}
		wow.fire("PLAYER_LOGOUT")
		assert.are.equal(char, _G.BraindeadForeverCharDB.stats)
	end)
end)

describe("Your run: counter-checks", function()
	it("without the minimum number of runs, nine runs show a median and a rank", function()
		local ns = login({ level = 4, char = veteran(4), collect = collect(others({ 1, 2 }, 9)) })
		ns.Stats.MIN_RUNS = 1 -- the guard taken out: any run counts
		SlashCmdList.BRAINDEADFOREVER("stats")
		drain(ns)
		local row = ns.StatsPage.rendered[3]
		assert.are.equal("11 min", row.cells[3])
		assert.are.equal("100 %", row.cells[4])
	end)

	it("without the fight guard the comparison build reads the vault in a fight", function()
		local ns = login({ level = 4, char = veteran(4), collect = collect(others({ 1, 2, 3 }, 40)) })
		ns.RunStats.Fighting = function()
			return false
		end
		SlashCmdList.BRAINDEADFOREVER("stats")
		ns.RunStats.SLICE = 10
		local d = ns.RunStats.driver
		d.scripts.OnUpdate(d, 1 / 60)
		local fed = ns.RunStats.Job().seq
		S.combat(true)
		d.scripts.OnUpdate(d, 1 / 60)
		assert.is_true(ns.RunStats.Job().seq > fed)
	end)

	it("without the out-of-combat queue the page opens in a fight", function()
		local ns = login({ level = 4, char = veteran(4) })
		ns.UI.OutOfCombat = function(_, fn, ...)
			fn(...)
			return true
		end
		S.combat(true)
		SlashCmdList.BRAINDEADFOREVER("stats")
		assert.are.same({ "BraindeadForeverStatsFrame:Show" }, wow.blocked)
	end)

	it("without the shown mark the review card comes a second time", function()
		local ns = login({ level = 9, char = veteran(9) })
		ns.RunStats.RecapDone = function() end -- the mark taken out
		levelUp(ns, 10)
		wow.advance(5)
		drain(ns)
		assert.is_true(shown("BraindeadForeverRecapFrame"))
		_G.BraindeadForeverRecapFrame:Hide()
		wow.fire("ZONE_CHANGED_NEW_AREA")
		wow.advance(5)
		drain(ns)
		assert.is_true(shown("BraindeadForeverRecapFrame"))
	end)
end)
