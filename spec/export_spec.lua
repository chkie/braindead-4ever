-- SPDX-License-Identifier: GPL-3.0-or-later
-- Collector/Export.lua and decoder/decode.mjs: frame, checksum and the round trip
-- Lua -> zlib (as CompressString) -> Base64 -> website decoder -> the same data.
local wow = require("spec.helpers.wow")
local node = require("spec.helpers.node")
local json = require("spec.helpers.json")

local function load()
	wow.reset()
	return wow.loadFiles({
		"BraindeadForever/Locales/enUS.lua",
		"BraindeadForever/Core/Util.lua",
		"BraindeadForever/Collector/Export.lua",
	})
end

-- Codec with the real compression of Node's zlib (method 0 = raw Deflate, 1 = Zlib).
local function nodeCodec(m)
	return {
		m = m,
		json = json.encode,
		zip = function(s)
			return node.compress(s, m == "z" and 1 or 0)
		end,
		b64 = json.b64encode,
	}
end

describe("Export frame", function()
	it("computes Adler-32 like the reference", function()
		local ns = load()
		assert.are.equal("11e60398", ns.Export.Adler32("Wikipedia"))
		assert.are.equal("00000001", ns.Export.Adler32(""))
	end)

	it("builds PM1:<m>:<length>:<adler32>:<base64> and reads it back", function()
		local ns = load()
		local codec = {
			m = "d",
			json = json.encode,
			zip = function(s)
				return s
			end,
			b64 = json.b64encode,
		}
		local text = assert(ns.Export.Build({ a = 1 }, codec))
		local m, len, sum, body = text:match("^PM1:(%a):(%d+):(%x+):(.+)$")
		assert.are.equal("d", m)
		assert.are.equal(#body, tonumber(len))
		assert.are.equal(ns.Export.Adler32(body), sum)
		local back, method = ns.Export.Parse(text)
		assert.are.equal(body, back)
		assert.are.equal("d", method)
	end)

	it("tells truncated from changed text and ignores line breaks", function()
		local ns = load()
		local codec = {
			m = "d",
			json = json.encode,
			zip = function(s)
				return s
			end,
			b64 = json.b64encode,
		}
		local text = assert(ns.Export.Build({ list = { 1, 2, 3 }, t = "Prüfung" }, codec))
		local cut = text:sub(1, -5)
		assert.matches("^truncated: %d+ of %d+ characters$", select(2, ns.Export.Parse(cut)))
		local last = text:sub(-1)
		local changed = text:sub(1, -2) .. (last == "A" and "B" or "A")
		assert.are.equal("checksum mismatch", select(2, ns.Export.Parse(changed)))
		local wrapped = text:sub(1, 20) .. "\n  " .. text:sub(21, 40) .. "\r\n" .. text:sub(41)
		assert.is_string((ns.Export.Parse(wrapped)))
		assert.are.equal("not a PM1 export", select(2, ns.Export.Parse("JT1:abc")))
		assert.are.equal("no text", select(2, ns.Export.Parse(nil)))
	end)

	it("reports an encoder that returns nothing or fails", function()
		local ns = load()
		local empty = { m = "d", json = json.encode, zip = function() end, b64 = json.b64encode }
		assert.are.same({ nil, "encode: empty" }, { ns.Export.Build({}, empty) })
		local broken = {
			m = "d",
			json = function()
				error("boom", 0)
			end,
			zip = tostring,
			b64 = tostring,
		}
		assert.are.same({ nil, "encode: boom" }, { ns.Export.Build({}, broken) })
	end)

	it("uses the client codec with Deflate by default", function()
		local ns = load()
		local codec = ns.Export.GameCodec()
		assert.are.equal("d", codec.m)
		assert.are.equal("Z0:abc", codec.zip("abc")) -- stand-in tags the method: 0 = Deflate
		assert.are.equal("Z1:abc", ns.Export.GameCodec("z").zip("abc"))
	end)
end)

describe("Export round trip through the website decoder", function()
	it("needs Node 22 or newer", function()
		assert.is_true((tonumber(node.version()) or 0) >= 22, "node is missing or too old")
	end)

	for _, m in ipairs({ "d", "z" }) do
		it("decodes method " .. m .. " to the same data, umlauts included", function()
			local ns = load()
			local payload = {
				format = "braindead-forever",
				t = "Prüfung äöü ß",
				n = 42,
				own = { "chunk\t0\t1\t20762\nxp\t3\t1\t2" },
			}
			local text = assert(ns.Export.Build(payload, nodeCodec(m)))
			assert.matches("^PM1:" .. m .. ":", text)
			local out = assert(node.decode(text))
			assert.are.equal(json.encode(payload), json.encode(node.parseJSON(out)))
			-- pasted with line breaks in a chat window: still readable
			local wrapped = text:sub(1, 30) .. "\n" .. text:sub(31)
			assert.is_string((node.decode(wrapped)))
		end)
	end

	it("rejects truncated and changed text before decompressing", function()
		local ns = load()
		local text = assert(ns.Export.Build({ n = 1 }, nodeCodec("d")))
		assert.matches("truncated", select(2, node.decode(text:sub(1, -3))))
		local changed = text:sub(1, -2) .. (text:sub(-1) == "A" and "B" or "A")
		assert.matches("checksum mismatch", select(2, node.decode(changed)))
	end)
end)
