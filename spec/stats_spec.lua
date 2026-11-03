-- SPDX-License-Identifier: GPL-3.0-or-later
-- Routes/Stats.lua (Welle 8, "Your run"): the tally per level, the comparison with the class from the
-- run vault and the best times, on dummy records and vault texts. Pure Lua, no client.
local wow = require("spec.helpers.wow")

local function load()
	wow.reset({})
	return wow.loadFiles({ "BraindeadForever/Routes/Stats.lua" }).Stats
end

-- A vault text as Collector/Proto.lua formats it.
local function msg(tok, class, mode, kind, sec, secs, inOrder, opts)
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
		inOrder,
		opts.level or sec + 1,
		opts.day or 20762
	)
end

local function index(S, texts, class, mine)
	local idx = S.NewIndex(class or 1, mine)
	for _, t in ipairs(texts) do
		S.Feed(idx, t)
	end
	return S.Seal(idx)
end

describe("Your run: tally per level", function()
	it("splits active time by activity and keeps breaks apart", function()
		local S = load()
		local db = S.CharDB({})
		local t = S.NewTally(db)
		t:Level(5, true)
		t.mark = 0
		t:Flag(10, "move", true) -- 10 s standing, then moving
		t:Flag(40, "combat", true) -- 30 s moving, then a fight
		t:Flag(70, "combat", false) -- 30 s fighting
		t:Play(100, 100, 100, nil) -- 30 s moving again
		local r = db.lv[5]
		assert.are.equal(100, r.s)
		assert.are.equal(0, r.p)
		assert.are.equal(30, r.c)
		assert.are.equal(60, r.m)
		assert.are.equal(0, r.f)
		-- a gap of 900 s, counted as 300 (idle cap): 600 s of break, the activities share the 300
		t:Flag(150, "taxi", true)
		t:Play(1000, 300, 900, nil)
		assert.are.equal(400, r.s)
		assert.are.equal(600, r.p)
		assert.is_true(math.abs(r.f - (300 * 850 / 900)) < 1e-9)
	end)

	it("counts XP from kills before and after the kill event, quest rewards and the rest", function()
		local S = load()
		local db = S.CharDB({})
		local t = S.NewTally(db)
		t:Level(7, true)
		t:Kill(10)
		t:Play(10.5, 0, 0, 80) -- kill first, XP 0.5 s later
		t:Play(20, 0, 0, 90)
		t:Kill(20.4) -- XP first, kill 0.4 s later
		t:Play(30, 0, 0, 400) -- a quest reward ...
		t:Quest(400) -- ... and its QUEST_TURNED_IN
		t:Play(40, 0, 0, 50) -- discovery, no kill
		t:Kill(45) -- a kill 5 s later does not take it
		local r = db.lv[7]
		assert.are.equal(620, r.x)
		assert.are.equal(170, r.k)
		assert.are.equal(400, r.q)
		assert.are.equal(1, r.n)
		local sh = S.Shares(r)
		assert.are.same({ 65, 27, 8 }, { sh.quest, sh.kill, sh.other })
	end)

	it("one XP gain per kill: a second gain right after a kill is not a kill", function()
		local S = load()
		local db = S.CharDB({})
		local t = S.NewTally(db)
		t:Level(3, true)
		t:Kill(5)
		t:Play(5.2, 0, 0, 60)
		t:Play(5.5, 0, 0, 300) -- a quest turned in right after
		assert.are.equal(60, db.lv[3].k)
	end)

	it("closes a level with the route's section, counts skipped quests and deaths", function()
		local S = load()
		local db = S.CharDB({})
		local t = S.NewTally(db)
		t:Level(4, true).b0 = 2
		t:Play(1, 50, 50, 100)
		t:Death()
		t:Quest(nil) -- turned in, the client named no XP
		local closed = t:LevelUp(5, { secs = 1840, xp = 2800, mode = "s", inOrder = 100, full = true }, 5, 20762)
		assert.are.equal(1840, closed.s) -- the run section's seconds win
		assert.are.equal(2800, closed.x)
		assert.are.equal(3, closed.b)
		assert.are.equal(1, closed.d)
		assert.are.equal(1, closed.n)
		assert.are.equal("s", closed.mo)
		assert.is_true(closed.full)
		assert.is_nil(closed.b0)
		assert.are.equal(20762, closed.day)
		assert.are.equal(5, t.level)
		assert.are.equal(5, db.lv[5].b0)
		assert.is_true(db.lv[5].full)
		assert.are.equal(2, S.Skipped(db.lv[5], 7)) -- live count of the running level
	end)

	it("keeps the first run of a module and version, as the vault does", function()
		local S = load()
		local db = S.CharDB({})
		local t = S.NewTally(db)
		assert.is_true(t:Module(1234, "a-speed-start", 1, 600, 100, "s", 5))
		assert.is_false(t:Module(1234, "a-speed-start", 1, 400, 100, "s", 5))
		assert.is_true(t:Module(1234, "a-speed-start", 2, 400, 100, "s", 5))
		assert.are.equal(2, #db.mods)
		assert.are.equal(600, db.mods[1].s)
	end)
end)

describe("Your run: way of play and bands", function()
	it("groups like tools/routekit/runs.py: follows, free, partly", function()
		local S = load()
		assert.are.equal("r", S.Group("s", 80))
		assert.are.equal("r", S.Group("e", 100))
		assert.are.equal("p", S.Group("s", 79))
		assert.are.equal("f", S.Group("f", 100))
		assert.are.equal("p", S.Group(nil, nil))
	end)

	it("sums a band of ten levels, says whether it is whole and from which level it counts", function()
		local S = load()
		local lv = {}
		for l = 1, 9 do
			lv[l] = { s = 600, x = 1000, mo = "s", o = 100, full = true, c = 100, m = 200, f = 0, n = 3, d = 0, b = 1 }
		end
		local b = S.Band(lv, 10)
		assert.are.same({ 1, 9, 5400, 9, true, "r", 27, 9 }, { b.lo, b.hi, b.s, b.levels, b.complete, b.g, b.n, b.b })
		lv[3].mo = "f"
		assert.are.equal("p", S.Band(lv, 10).g) -- mixed ways of play
		lv[1].full = nil -- the addon came in during level 1
		b = S.Band(lv, 10)
		assert.is_false(b.complete)
		assert.are.equal(2, b.from)
		assert.are.equal(4800, b.s)
		assert.are.same({ 10, 19 }, { S.BandRange(20) })
	end)

	it("keeps the best time per band; an equal time keeps the older one", function()
		local S = load()
		local best = {}
		assert.is_true(S.Best(best, 10, 18000, 1, 1, "r", 20760, "aaaaaa"))
		assert.is_false(S.Best(best, 10, 18000, 3, 3, "r", 20761, "bbbbbb"))
		assert.is_true(S.Best(best, 10, 17000, 3, 3, "f", 20762, "bbbbbb"))
		assert.are.same({ s = 17000, r = 3, c = 3, g = "f", d = 20762, t = "bbbbbb" }, best[10])
	end)
end)

describe("Your run: comparison with the class from the run vault", function()
	it("median and rank from MIN_RUNS runs on, else collecting without a number", function()
		local S = load()
		local texts = {}
		for i = 1, S.MIN_RUNS - 1 do
			texts[i] = msg(("t%05d"):format(i), 1, "s", "l", 5, 1000 + i * 100, 100)
		end
		local idx = index(S, texts)
		local c = S.Compare(idx, "l", 5, 0, "r", 1500)
		assert.are.same({ state = "collecting", n = S.MIN_RUNS - 1, need = S.MIN_RUNS }, c)
		texts[#texts + 1] = msg("t99999", 1, "e", "l", 5, 2000, 90)
		idx = index(S, texts)
		c = S.Compare(idx, "l", 5, 0, "r", 1500)
		assert.are.equal("ready", c.state)
		assert.are.equal(10, c.n)
		assert.are.equal(1550, c.median) -- 1100 .. 2000, even count: mean of 1500 and 1600
		assert.are.equal(55, c.faster) -- 5 slower, 1 tie (half): 5.5 of 10
	end)

	it("counts only the player's class, other players and the same way of play and version", function()
		local S = load()
		local texts = {}
		for i = 1, 12 do
			texts[#texts + 1] = msg(("a%05d"):format(i), 1, "s", "l", 6, 900, 100) -- follows
			texts[#texts + 1] = msg(("b%05d"):format(i), 1, "f", "l", 6, 700, 100) -- free play
			texts[#texts + 1] = msg(("c%05d"):format(i), 8, "s", "l", 6, 500, 100) -- another class
			texts[#texts + 1] = msg(("d%05d"):format(i), 1, "s", "m", 4242, 300, 100, { version = 2 })
		end
		texts[#texts + 1] = msg("mine01", 1, "s", "l", 6, 100, 100)
		local idx = index(S, texts, 1, { mine01 = true })
		assert.are.equal(900, S.Compare(idx, "l", 6, 0, "r").median)
		assert.are.equal(12, S.Compare(idx, "l", 6, 0, "r").n) -- the own token is left out
		assert.are.equal(700, S.Compare(idx, "l", 6, 0, "f").median)
		assert.are.equal("collecting", S.Compare(idx, "l", 6, 0, "p").state)
		assert.are.equal(300, S.Compare(idx, "m", 4242, 2, "r").median)
		assert.are.equal("collecting", S.Compare(idx, "m", 4242, 1, "r").state)
		assert.are.equal(36, idx.used) -- 12 follow, 12 free, 12 module runs; the other class and the own token not
	end)

	it("adds up whole bands per token for the review card", function()
		local S = load()
		local texts = {}
		for i = 1, 11 do
			local tok = ("k%05d"):format(i)
			for l = 1, 9 do
				texts[#texts + 1] = msg(tok, 1, "s", "l", l, 600 + i, 100)
			end
		end
		for l = 1, 8 do -- one token without level 9: no band
			texts[#texts + 1] = msg("short1", 1, "s", "l", l, 10, 100)
		end
		local idx = index(S, texts)
		local c = S.Compare(idx, "b", 10, 0, "r", 9 * 605)
		assert.are.equal(11, c.n)
		assert.are.equal(9 * 606, c.median)
		assert.is_nil(idx.toks) -- the per-token sums are dropped after sealing
	end)

	it("takes the own sections over from the vault", function()
		local S = load()
		local list = {
			msg("mine01", 1, "s", "l", 5, 1840, 100, { xp = 2800, day = 20761 }),
			msg("other1", 1, "s", "l", 5, 1000, 100),
			msg("mine01", 1, "s", "m", 777, 600, 90, { version = 3, level = 6 }),
			"garbage",
		}
		local out = S.FromVault(list, 1, 4, { mine01 = true })
		assert.are.same(
			{ "mine01" },
			(function()
				local k = {}
				for tok in pairs(out) do
					k[#k + 1] = tok
				end
				return k
			end)()
		)
		local own = out.mine01
		assert.are.same({ s = 1840, x = 2800, mo = "s", o = 100, full = true, day = 20761 }, own.lv[5])
		assert.are.same({ num = 777, v = 3, s = 600, o = 90, mo = "s", l = 6 }, own.mods[1])
		assert.are.same({ 1, 1 }, { own.race, own.class })
	end)
end)
