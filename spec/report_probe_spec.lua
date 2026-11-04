-- SPDX-License-Identifier: GPL-3.0-or-later
-- Core/Report.lua (report a problem) and Probe/ (developer API probe).
local wow = require("spec.helpers.wow")
local S = require("spec.helpers.uisession") -- loads the German texts like a German client

describe("Report", function()
	it("lists version, build, step, position, modules, quest log and errors without names", function()
		local ns = wow.session()
		ns.CurrentStep = function()
			return "elwynn.12"
		end
		wow.world.questLog = {
			{
				questID = 783,
				objectives = {
					{ numFulfilled = 4, numRequired = 8 },
					{ numFulfilled = 1, numRequired = 1, finished = true },
				},
			},
		}
		ns.Guard.Call("arrow", function()
			error("arrow failed", 0)
		end)
		SlashCmdList.BRAINDEADFOREVER("report Quest hängt\nbei Wolf")
		local text = ns.CopyWindow().box:GetText()
		assert.matches("^Braindead 4ever report v1 | addon dev | build 70532 | toc 16001 | enUS", text)
		assert.matches("Step: elwynn.12", text, 1, true)
		assert.matches("Level 5 | Human/WARRIOR | Alliance", text, 1, true)
		assert.matches("Position: map 1429 | 42.31, 65.12", text, 1, true)
		assert.matches("collector%s+on", text)
		assert.matches("exchange%s+on", text)
		assert.matches("  783 [open] 4/8 1/1+", text, 1, true)
		assert.matches("  1x [arrow] arrow failed", text, 1, true)
		assert.matches("Note (player input): Quest hängt bei Wolf", text, 1, true)
		for _, secret in ipairs({ "Testchar", "Brightwood", "Testrealm", "Player-" }) do
			assert.is_nil(text:find(secret, 1, true), secret)
		end
	end)

	it("names the current route step and survives a withheld position", function()
		local ns = wow.session()
		wow.world.player.x = nil
		local text = ns.Report.Build()
		assert.matches("Step: a-speed-start-elwynn/a783", text, 1, true)
		assert.matches("Position: map 1429 | no coordinate", text, 1, true)
		assert.matches("Errors:\n  none", text, 1, true)
	end)
end)

-- The report window says where the text belongs and carries the Discord link in a box the player can
-- select and copy (links are not clickable in the game). The report text itself stays as it was.
describe("Report window: Discord link", function()
	local LINK = "discord.gg/ujjEM9NE5D"
	local WHERE = {
		enUS = "Post this text in #bug-reports on our Discord:",
		deDE = "Poste diesen Text im Kanal #bug-reports auf unserem Discord:",
	}

	for _, locale in ipairs({ "enUS", "deDE" }) do
		it("names #bug-reports and shows the link in a copyable box (" .. locale .. ")", function()
			local ns = S.login({ locale = locale })
			SlashCmdList.BRAINDEADFOREVER("report")
			local win = ns.CopyWindow()
			assert.is_true(win:IsShown())
			assert.are.equal(WHERE[locale], win.where.text)
			assert.is_true(win.where:IsShown())
			assert.matches("#bug-reports", win.where.text, 1, true)
			assert.are.equal("EditBox", win.link.type)
			assert.is_true(win.link:IsShown())
			assert.are.equal(LINK, win.link:GetText())
			-- copyable: the player cannot change it, focus selects it
			win.link:SetText("changed by the player")
			win.link.scripts.OnTextChanged(win.link, true)
			assert.are.equal(LINK, win.link:GetText())
			assert.is_function(win.link.scripts.OnEditFocusGained)
			-- the report body is unchanged and carries no link
			assert.is_nil(win.box:GetText():find("discord", 1, true))
		end)
	end

	it("does not show the link in other copy windows", function()
		local ns = wow.session()
		ns.ShowCopy("Export", "PM1:x")
		local win = ns.CopyWindow()
		assert.is_false(win.where:IsShown())
		assert.is_false(win.link:IsShown())
		SlashCmdList.BRAINDEADFOREVER("report")
		assert.is_true(win.link:IsShown())
	end)
end)

describe("Probe", function()
	local function probe()
		return wow.session({ probe = true })
	end

	local function result(ns, id)
		return ns.Probe.DB().results[id]
	end

	it("measures functions, values, events and tests in one run", function()
		local ns = probe()
		-- Functions the client lacks show up as missing (the UI stand-ins have both).
		_G.GetPlayerFacing = nil
		local atlas = _G.C_Texture
		_G.C_Texture = nil
		SlashCmdList.BRAINDEADFOREVER("probe run")
		_G.C_Texture = atlas
		assert.matches("checks saved", wow.output(), 1, true)
		assert.are.same({ "OK", "free" }, { result(ns, "ver.build").result, result(ns, "ver.build").context })
		assert.matches('"1.60.1", "70532"', result(ns, "ver.build").detail, 1, true)
		assert.are.equal("OK", result(ns, "quest.trivial").result) -- Forever-only, present in the stand-in
		assert.are.equal("MISSING", result(ns, "nav.facing").result)
		assert.are.equal("OK", result(ns, "ver.camelot").result)
		assert.are.equal("OK", result(ns, "enc.deflate").result)
		assert.matches("^PM1:d:", result(ns, "enc.deflate").detail)
		assert.are.equal("OK", result(ns, "enc.zlib").result)
		assert.are.equal("OK", result(ns, "comm.prefix").result)
		assert.are.equal("with surname separator", result(ns, "comm.nameformat").detail)
		assert.are.equal("MISSING", result(ns, "atlas.arrow").result)
	end)

	it("measures the Classic XP assumptions: level table, kill XP, quest XP", function()
		local ns = probe()
		local P = wow.world.player -- level 5
		ns.Probe.Run()
		assert.are.same({ "FAILED", "level 5: client 400, Classic 2800" }, {
			result(ns, "xp.curve").result,
			result(ns, "xp.curve").detail,
		})
		P.xpMax = 2800
		assert.are.equal("OK", ns.Probe.Check("xp.curve").result)
		assert.is_nil(result(ns, "xp.kill"), "manual check, not part of a run")
		assert.are.equal("FAILED", ns.Probe.Check("xp.kill").result)
		-- kill of a level 5 creature: 5 * 5 + 45 = 70
		wow.world.units.target = { guid = "Creature-0-1-0-2-299-0", level = 5, classification = "normal" }
		P.xp = P.xp + 70
		wow.fire("PLAYER_XP_UPDATE", "player")
		local kill = ns.Probe.Check("xp.kill")
		assert.are.equal("OK", kill.result)
		assert.matches("gain 70 at level 5, target level 5 normal: Classic 70", kill.detail, 1, true)
		-- quest 783: route data 40 XP at quest level 1, full at level 5
		wow.world.questLog = { { questID = 783, rewardXP = 40 } }
		assert.are.equal("OK", ns.Probe.Check("xp.quest").result)
		wow.world.questLog = { { questID = 783, rewardXP = 55 } }
		assert.are.same({ "FAILED", "quest 783 level 1 at level 5: client 55, data 40" }, {
			ns.Probe.Check("xp.quest").result,
			ns.Probe.Check("xp.quest").detail,
		})
	end)

	it("reports a Forever-only function as missing in the Retail test bed", function()
		local ns = wow.session({ probe = true, flavor = "retail" })
		ns.Probe.Run()
		assert.are.equal("MISSING", result(ns, "quest.trivial").result)
		assert.are.equal("MISSING", result(ns, "ver.rulesevent").result)
	end)

	it("marks secret return values and failing arguments", function()
		local ns = probe()
		wow.world.units.target = { guid = wow.SECRET, name = "Rare", classification = "rare" }
		ns.Probe.Run()
		wow.fire("PLAYER_TARGET_CHANGED")
		assert.are.equal("OK", result(ns, "find.rareclass").result)
		assert.are.equal("MISSING", result(ns, "find.creatureid").result) -- C_CreatureInfo missing in the stand-in
		wow.world.npc = { guid = wow.SECRET, name = wow.SECRET }
		wow.fire("QUEST_DETAIL", 0)
		assert.are.equal("ARGERROR", result(ns, "name.npctooltip").result) -- no NPC ID from a secret GUID
		assert.are.equal("SECRET", result(ns, "name.npc").result)
		wow.world.combat = true
		wow.fire("PLAYER_REGEN_DISABLED")
		assert.are.same({ "SECRET", "PLAYER_REGEN_DISABLED/combat" }, {
			result(ns, "find.targetguid").result,
			result(ns, "find.targetguid").context,
		})
	end)

	it("runs context checks when the quest dialog, loot or flight map opens", function()
		local ns = probe()
		wow.world.npc, wow.world.questID =
			{ guid = "Creature-0-1465-0-2105-823-0000ABC123", name = "Marshal McBride" }, 783
		wow.fire("QUEST_DETAIL", 0)
		assert.are.same({ "OK", '"Creature-0-1465-0-2105-823-0000ABC123"' }, {
			result(ns, "find.giverguid").result,
			result(ns, "find.giverguid").detail,
		})
		assert.are.equal("783", result(ns, "find.giverquest").detail)
		wow.world.loot = { { link = "|Hitem:1:::|h[x]|h", sources = { "GameObject-0-1-0-1-2843-1", 1 } } }
		wow.fire("LOOT_OPENED", false, false)
		assert.are.equal('"GameObject-0-1-0-1-2843-1", 1', result(ns, "find.lootsource").detail)
		wow.fire("TAXIMAP_OPENED", 0)
		assert.are.equal("OK", result(ns, "find.taxinodes").result)
	end)

	it("counts events with their first payload and never registers the combat log", function()
		local ns = probe()
		wow.fire("QUEST_ACCEPTED", 783)
		wow.fire("QUEST_ACCEPTED", 784)
		ns.Probe.Run()
		assert.are.equal("fired 2x, first payload: 783", result(ns, "mod.collector.QUEST_ACCEPTED").detail)
		assert.are.equal("not registered on purpose", result(ns, "find.combatlog").detail)
		assert.is_nil(ns.Probe.frame.events.COMBAT_LOG_EVENT_UNFILTERED)
	end)

	it("derives checks from every module's required and optional API", function()
		local ns = probe()
		local ids = {}
		for _, c in ipairs(ns.Probe.All()) do
			assert.is_nil(ids[c.id], "duplicate id " .. c.id)
			ids[c.id] = c
		end
		assert.is_table(ids["mod.collector.C_EncodingUtil.SerializeJSON"])
		assert.is_table(ids["mod.exchange.C_ChatInfo.SendAddonMessage"])
		-- names already checked explicitly are not repeated
		assert.is_nil(ids["mod.collector.C_QuestLog.IsQuestFlaggedCompleted"])
		assert.is_table(ids["quest.flagged"])
		assert.is_table(ids["mod.report.C_QuestLog.IsFailed"])
	end)

	it("records blocked actions with addon and function", function()
		local ns = probe()
		wow.fire("ADDON_ACTION_BLOCKED", "Braindead4Ever", "UseQuestLogSpecialItem()")
		local report = ns.Probe.Report()
		assert.matches('blocked\tADDON_ACTION_BLOCKED\t"Braindead4Ever"\t"UseQuestLogSpecialItem()"', report, 1, true)
	end)

	it("lets only a person set the plan status, and only to known values", function()
		local ns = probe()
		SlashCmdList.BRAINDEADFOREVER("probe status find.lootsource verified")
		assert.are.equal("verified", ns.Probe.DB().plan["find.lootsource"])
		SlashCmdList.BRAINDEADFOREVER("probe status find.lootsource done")
		SlashCmdList.BRAINDEADFOREVER("probe status no.such.id built")
		assert.are.equal("verified", ns.Probe.DB().plan["find.lootsource"])
		ns.Probe.Run()
		assert.are.equal("verified", ns.Probe.DB().plan["find.lootsource"]) -- a run never changes it
	end)

	it("runs manual checks only on request and shows the report in the copy window", function()
		local ns = probe()
		wow.world.group.party = true
		ns.Probe.Run()
		assert.is_nil(result(ns, "comm.burst"))
		SlashCmdList.BRAINDEADFOREVER("probe check comm.burst")
		assert.matches("^PARTY: 0,0,0,0,0,0,0,0,0,0,0,0", result(ns, "comm.burst").detail)
		SlashCmdList.BRAINDEADFOREVER("probe report")
		local text = ns.CopyWindow().box:GetText()
		assert.matches("^# Braindead 4ever probe addon=dev build=70532 toc=16001 project=18 locale=enUS", text)
		assert.matches("\ncomm.burst\ttest\tSendAddonMessage burst\t-\tOK\t", text, 1, true)
		assert.matches("\nfind.lootsource\tfunc\tGetLootSourceInfo\t-\tNOT RUN\twaits for LOOT_OPENED\t", text, 1, true)
	end)

	it("keeps the SavedVariables marker for the cold start test", function()
		local ns = probe()
		ns.Probe.Run()
		assert.matches("no previous marker", result(ns, "sv.coldstart").detail, 1, true)
		local saved = BraindeadForeverDB
		ns = wow.session({ probe = true, saved = saved })
		ns.Probe.Run()
		assert.matches("previous marker from %d+, build 70532", result(ns, "sv.coldstart").detail)
	end)

	it("is not part of the player package", function()
		local ns = wow.session()
		assert.is_nil(ns.Probe)
		SlashCmdList.BRAINDEADFOREVER("probe run")
		assert.is_nil(BraindeadForeverDB.probe)
	end)
end)
