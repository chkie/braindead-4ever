-- SPDX-License-Identifier: GPL-3.0-or-later
-- Performance of the interface against the project budget (brain chapter 12 §9: under 0.1 ms per
-- frame on average, at most 10 MB; the arrow update at most 0.15 ms, no allocation in its path).
-- Offline measurement on stock Lua 5.1 with stand-ins: it shows the order of magnitude and catches
-- allocations per frame; the binding numbers come from C_AddOnProfiler in the client (gate T16).
-- The measured values are written to the test output.
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession")

local function report(fmt, ...)
	io.stdout:write("\n[perf] " .. fmt:format(...))
end

-- Widget methods of the stand-ins record their arguments in tables; for the allocation count they
-- must not, so they become plain no-ops here.
local function quietWidgets()
	local F = wow.Frame
	local saved = {}
	for _, name in ipairs({ "SetVertexColor", "SetRotation", "SetAlpha", "SetText", "SetPoint", "ClearAllPoints" }) do
		saved[name] = rawget(F, name)
		rawset(F, name, function() end)
	end
	return function()
		for name, fn in pairs(saved) do
			rawset(F, name, fn)
		end
	end
end

describe("Interface performance (offline)", function()
	it("arrow: per frame well under budget and without allocation", function()
		local ns = S.login()
		local t = ns.Nav.Target(ns.Route.Current())
		S.face(ns, t, 40)
		local restore = quietWidgets()
		local N = 60000 -- 1000 s at 60 frames per second
		collectgarbage("collect")
		collectgarbage("stop")
		local before = collectgarbage("count")
		local start = os.clock()
		for _ = 1, N do
			ns.Arrow.Update(1 / 60)
		end
		local ms = (os.clock() - start) * 1000 / N
		local kb = collectgarbage("count") - before
		collectgarbage("restart")
		restore()
		report("arrow update: %.4f ms per frame, %.2f KB allocated over %d frames", ms, kb, N)
		assert.is_true(ms < 0.05, ("arrow %.4f ms per frame"):format(ms))
		-- a standing player: the distance text never changes, so nothing may allocate
		assert.is_true(kb < 1, ("arrow allocates %.2f KB"):format(kb))
	end)

	it("step window: a refresh costs little and runs on events only", function()
		local ns = S.login()
		local N = 500
		local start = os.clock()
		for _ = 1, N do
			ns.StepFrame.Refresh()
		end
		local ms = (os.clock() - start) * 1000 / N
		report("step window full refresh (step or route change): %.3f ms", ms)
		assert.is_true(ms < 5, ("refresh %.3f ms"):format(ms))
		start = os.clock()
		for _ = 1, N do
			ns.StepFrame.Refresh(true)
		end
		local light = (os.clock() - start) * 1000 / N
		report("step window light refresh (quest log update): %.3f ms", light)
		-- quest log updates are coalesced to at most 5 light refreshes per second (0.2 s, StepFrame.Queue):
		-- worst case while questing, spread over 60 frames per second
		local worst = light * 5 / 60
		report("step window worst case from quest log bursts: %.4f ms per frame (budget 0.1)", worst)
		assert.is_true(worst < 0.1)
		start = os.clock()
		for _ = 1, 100 do
			ns.StepFrame.Invalidate()
		end
		report(
			"XP balance and dungeon hint on a step change: %.3f ms (only on StepChanged, XPBalance, RouteRecalculated)",
			(os.clock() - start) * 10
		)
		-- per frame only the throttled distance check runs
		local W = ns.StepFrame.frame
		local restore = quietWidgets()
		start = os.clock()
		for _ = 1, 60000 do
			W.scripts.OnUpdate(W, 1 / 60)
		end
		local perFrame = (os.clock() - start) * 1000 / 60000
		restore()
		report("step window per frame: %.4f ms", perFrame)
		assert.is_true(perFrame < 0.05)
	end)

	it("explorer style and the quest tracker pass stay under budget (Welle 5b)", function()
		local ns = S.login({ saved = { ui = { style = "self", hint = 0 } } })
		local N = 200
		local start = os.clock()
		for _ = 1, N do
			ns.StepFrame.Refresh(true)
		end
		local light = (os.clock() - start) * 1000 / N
		report("step window light refresh, explorer style without a riddle left: %.3f ms", light)
		report("worst case from quest log bursts: %.4f ms per frame (budget 0.1)", light * 5 / 60)
		assert.is_true(light * 5 / 60 < 0.1)
		-- quest tracker: a pass with a full log of 25 quests, once per burst of quest events (0.2 s)
		local W = wow.world
		for i = 1, 25 do
			W.questLog[#W.questLog + 1] = { questID = 90000 + i }
			W.watch(90000 + i, true)
		end
		start = os.clock()
		for _ = 1, N do
			ns.QuestWatch.Apply()
		end
		local pass = (os.clock() - start) * 1000 / N
		report(
			"quest tracker pass (25 quests in the log): %.3f ms, at most 5 per second: %.4f ms per frame",
			pass,
			pass * 5 / 60
		)
		assert.is_true(pass * 5 / 60 < 0.1)
	end)

	it("memory of the interface stays far under 10 MB", function()
		collectgarbage("collect")
		wow.reset({})
		local files = wow.addonFiles()
		local core, ui = {}, {}
		for _, f in ipairs(files) do
			if f:find("/UI/", 1, true) then
				ui[#ui + 1] = f
			else
				core[#core + 1] = f
			end
		end
		local ns = wow.loadFiles(core)
		collectgarbage("collect")
		local before = collectgarbage("count")
		wow.loadFiles(ui, "BraindeadForever", ns)
		collectgarbage("collect")
		local kb = collectgarbage("count") - before
		report("interface code loaded: %.0f KB (Lua 5.1, offline)", kb)
		assert.is_true(kb < 1024)
	end)
end)
