-- SPDX-License-Identifier: GPL-3.0-or-later
-- Collector/Migrate.lua (versioned migration on a copy) and Collector/Proto.lua (exchange protocol).
local wow = require("spec.helpers.wow")

local function load()
	wow.reset()
	return wow.loadFiles({
		"Pathmark/Locales/enUS.lua",
		"Pathmark/Core/Util.lua",
		"Pathmark/Collector/Migrate.lua",
		"Pathmark/Collector/Proto.lua",
	})
end

describe("Migrate", function()
	local steps = {
		[1] = function(d)
			d.install = d.install or "abcdefghijkl"
		end,
		[2] = function(d)
			if d.log and not d.chunks then
				d.chunks, d.log = d.log, nil
			end
		end,
	}

	it("lifts old data step by step on a copy and leaves the original untouched", function()
		local ns = load()
		local saved = { log = { "a" } }
		local db = assert(ns.Migrate.Upgrade(saved, 2, steps))
		assert.are_not.equal(saved, db)
		assert.are.equal(2, db.schema)
		assert.are.equal("abcdefghijkl", db.install)
		assert.are.same({ "a" }, db.chunks)
		assert.is_nil(db.log)
		assert.are.same({ log = { "a" } }, saved)
	end)

	it("returns the same table when it is current", function()
		local ns = load()
		local saved = { schema = 2 }
		assert.are.equal(saved, ns.Migrate.Upgrade(saved, 2, steps))
	end)

	it("refuses data from a newer version", function()
		local ns = load()
		assert.are.same({ nil, "newer" }, { ns.Migrate.Upgrade({ schema = 9 }, 2, steps) })
	end)

	it("keeps the saved table unchanged when a step fails", function()
		local ns = load()
		local saved = { schema = 1, chunks = { "x" } }
		local bad = {
			[2] = function()
				error("broken step", 0)
			end,
		}
		local db, why = ns.Migrate.Upgrade(saved, 2, bad)
		assert.is_nil(db)
		assert.are.equal("step 2: broken step", why)
		assert.are.same({ schema = 1, chunks = { "x" } }, saved)
	end)

	it("makes random IDs from [0-9a-z] of the requested length", function()
		local ns = load()
		local id = ns.Util.NewId(12)
		assert.are.equal(12, #id)
		assert.matches("^[0-9a-z]+$", id)
	end)
end)

describe("Proto", function()
	it("formats finds as short ASCII with IDs and numbers only", function()
		local ns = load()
		local P = ns.Proto
		assert.are.equal("q;1;783;c;823;1429;4231;6512", P.Format("q", 783, "c", 823, 1429, 4231, 6512))
		assert.are.equal("o;1;2843;1429;10;10000", P.Format("o", 2843, 1429, 10, 10000))
		assert.are.equal("r;1;61;e;1429;1;2", P.Format("r", 61, "e", 1429, 1, 2))
		assert.are.equal("f;1;352;2;1429;4000;5000", P.Format("f", 352, 2, 1429, 4000, 5000))
		assert.is_true(#P.PREFIX <= 16)
	end)

	it("sends nothing half-valid", function()
		local ns = load()
		local P = ns.Proto
		assert.is_nil(P.Format("q", 783, "p", 0, 1429, 1, 1)) -- shared by a player: no giver
		assert.is_nil(P.Format("o", 2843, 1429, 10001, 5)) -- outside the map
		assert.is_nil(P.Format("o", 2843, 1429, 1)) -- field missing
		assert.is_nil(P.Format("o", 0, 1429, 1, 1)) -- no ID
		assert.is_nil(P.Format("o", 1.5, 1429, 1, 1))
		assert.is_nil(P.Format("x", 1, 2, 3))
		assert.is_nil(P.Format("o", "Prüfung", 1429, 1, 1)) -- no text
	end)

	it("parses what it formats", function()
		local ns = load()
		local P = ns.Proto
		local f = assert(P.Parse(P.Format("t", 783, "o", 2843, 1429, 4231, 6512)))
		assert.are.same({ kind = "t", n = 6, 783, "o", 2843, 1429, 4231, 6512 }, f)
		local r = assert(P.Parse("r;1;61;w;1429;1;2"))
		assert.are.equal("w", r[2])
	end)

	it("skips other versions and unknown kinds, and marks broken messages", function()
		local ns = load()
		local P = ns.Proto
		assert.are.same({ nil, "skip" }, { P.Parse("o;2;1;1;1;1") })
		assert.are.same({ nil, "skip" }, { P.Parse("z;1;1;2;3") })
		assert.are.same({ nil, "bad" }, { P.Parse("hello") })
		assert.are.same({ nil, "bad" }, { P.Parse("o;1;1;1;1") }) -- field missing
		assert.are.same({ nil, "bad" }, { P.Parse("o;1;1;1;1;1;1") }) -- field too many
		assert.are.same({ nil, "bad" }, { P.Parse("o;1;1;1;1;99999") })
		assert.are.same({ nil, "bad" }, { P.Parse("q;1;1;Z;1;1;1;1") })
		assert.are.same({ nil, "bad" }, { P.Parse(("o;1;1;1;1;1"):rep(50)) })
		assert.are.same({ nil, "bad" }, { P.Parse(42) })
	end)

	it("gives the same key to the same find a few steps apart", function()
		local ns = load()
		local P = ns.Proto
		local a = P.Key(P.Parse("o;1;2843;1429;4231;6512"))
		local b = P.Key(P.Parse("o;1;2843;1429;4290;6555"))
		local c = P.Key(P.Parse("o;1;2843;1429;5231;6512"))
		assert.are.equal(a, b)
		assert.are_not.equal(a, c)
		-- quest givers and flight masters do not move: position is not part of the key
		assert.are.equal(P.Key(P.Parse("q;1;783;c;823;1429;1;1")), P.Key(P.Parse("q;1;783;c;823;1429;9000;9000")))
		assert.are.equal(P.Key(P.Parse("f;1;352;2;1429;1;1")), "f;352;2")
	end)
end)
