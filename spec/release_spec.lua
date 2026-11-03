-- SPDX-License-Identifier: GPL-3.0-or-later
-- Hotfix readiness (Welle 9, K9; release gate T30, concept §1.6): release notes by hand in English
-- with known issues (manual-changelog), CI on hotfix branches, the Discord notice without
-- mentions and a test post that needs nothing but the secret.
local function read(path)
	local fh = assert(io.open(path, "rb"))
	local text = fh:read("*a")
	fh:close()
	return text
end

describe("Release and hotfix", function()
	it("the packager takes the release notes from CHANGELOG.md (markdown)", function()
		local pkg = read(".pkgmeta")
		local block = pkg:match("\nmanual%-changelog:\n(.-)\n%S") or pkg:match("\nmanual%-changelog:\n(.*)$")
		assert.is_string(block, "no manual-changelog in .pkgmeta")
		assert.matches("filename: CHANGELOG.md", block, 1, true)
		assert.matches("markup-type: markdown", block, 1, true)
		assert.is_nil(pkg:find("\t"), "YAML: spaces only")
	end)

	it("CHANGELOG.md has notes and known issues in English only (the repository is English)", function()
		local text = read("CHANGELOG.md")
		local top = text:match("\n## ([^\n]+)")
		assert.is_string(top)
		for _, heading in ipairs({
			"\n## Known issues\n",
		}) do
			assert.is_truthy(text:find(heading, 1, true), "missing" .. heading)
		end
		assert.matches("/reload is not enough", text, 1, true)
		assert.is_nil(text:find("[äöüÄÖÜß]"), "no German text")
		assert.is_nil(text:find("\226\128\148"), "no em dash")
		local shown = text:gsub("<!%-%-.-%-%->", "") -- the editing note is not shown
		assert.is_nil(shown:find("!", 1, true), "no exclamation marks in release notes")
	end)

	it("CI runs on hotfix branches", function()
		local ci = read(".github/workflows/ci.yml")
		assert.matches('branches: [main, "hotfix/**"]', ci, 1, true)
	end)

	it("the Discord notice and its test post suppress every mention", function()
		for _, path in ipairs({ ".github/workflows/release.yml", ".github/workflows/discord-test.yml" }) do
			local wf = read(path)
			assert.matches("allowed_mentions:{parse:[]}", wf, 1, true)
			assert.matches("env.DISCORD_WEBHOOK_URL != ''", wf, 1, true)
		end
		assert.matches("workflow_dispatch", read(".github/workflows/discord-test.yml"), 1, true)
	end)

	it("CONTRIBUTING.md describes the hotfix branch from the release tag", function()
		local text = read("CONTRIBUTING.md")
		assert.matches("git switch -c hotfix/launch v0.1.0", text, 1, true)
		assert.matches("### Hotfix", text, 1, true)
	end)
end)
