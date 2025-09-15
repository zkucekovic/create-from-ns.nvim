local M = {}

M.config = {
	rules = {
		{ pattern = "Interface", trigger = "iface" },
		{ pattern = "Trait", trigger = "trait" },
		{ pattern = ".*", trigger = "class" },
	},
	keymap = nil, -- optional: { "n", "<leader>cn" }
}

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
	if M.config.keymap then
		local mode, lhs, rhs, kmopts = unpack(M.config.keymap)
		vim.keymap.set(mode, lhs, rhs or "<cmd>CreateFromNS<CR>", kmopts or { desc = "Create from namespace" })
	end
end

-- Parse PSR-4 from composer.json (autoload only)
local function load_psr4()
	local json = vim.fn.json_decode(vim.fn.readfile("composer.json"))
	local psr4 = {}
	if json and json["autoload"] and json["autoload"]["psr-4"] then
		for ns, paths in pairs(json["autoload"]["psr-4"]) do
			if type(paths) == "string" then
				psr4[ns] = { paths }
			elseif type(paths) == "table" then
				psr4[ns] = paths
			end
		end
	end
	return psr4
end

-- Find fully-qualified name on the current line nearest to the cursor.
-- Matches things like \Intellex\Storage\Entity\Embedding\EmbeddingVectorInterface
-- Also handles nullable "?\" prefix by stripping '?'.
local function fqn_near_cursor()
	local pos = vim.api.nvim_win_get_cursor(0) -- {row, col}, 1-based row, 0-based col
	local row, col = pos[1], pos[2]
	local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
	if line == "" then
		return nil
	end

	local c = col + 1 -- 1-based for Lua string indices

	-- collect all \Foo\Bar occurrences with their spans
	local candidates = {}
	for s, e in line:gmatch("()\\[%w_\\]+()") do
		table.insert(candidates, { s = s, e = e - 1 }) -- inclusive end
	end
	if #candidates == 0 then
		-- fallback: try to extract from the WORD under cursor (handles e.g. text objects)
		local word = vim.fn.expand("<cWORD>")
		local m = word:match("\\[%w_\\]+")
		return m and m:gsub("^%?", "") or nil
	end

	-- 1) pick the one covering the cursor, else
	for _, span in ipairs(candidates) do
		if c >= span.s and c <= span.e then
			local fqn = line:sub(span.s, span.e):gsub("^%?", "")
			return fqn
		end
	end
	-- 2) pick the closest to the left, else 3) first to the right
	local left, right
	for _, span in ipairs(candidates) do
		if span.e < c then
			left = (not left or span.e > left.e) and span or left
		elseif span.s > c then
			right = (not right or span.s < right.s) and span or right
		end
	end
	local chosen = left or right or candidates[1]
	return chosen and line:sub(chosen.s, chosen.e):gsub("^%?", "") or nil
end

local function pick_trigger(filename)
	for _, rule in ipairs(M.config.rules) do
		if filename:match(rule.pattern) then
			return rule.trigger
		end
	end
	return nil
end

function M.create_from_namespace()
	local fqn = fqn_near_cursor()
	if not fqn then
		print("No namespace found on this line.")
		return
	end

	-- ensure no leading backslash for matching against PSR-4 prefixes
	local word = fqn:gsub("^\\+", "")
	local psr4 = load_psr4()

	-- longest-prefix match
	local best_prefix, best_path
	for ns, paths in pairs(psr4) do
		if word:sub(1, #ns) == ns and (#ns > #(best_prefix or "")) then
			best_prefix, best_path = ns, paths[1] -- first path if multiple
		end
	end
	if not best_prefix then
		print("No PSR-4 mapping found for " .. fqn)
		return
	end

	local rel = word:sub(#best_prefix + 1):gsub("\\", "/")
	local file = best_path .. rel .. ".php"

	local is_new = vim.fn.filereadable(file) == 0
	if is_new then
		vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
		vim.fn.writefile({ "<?php", "declare(strict_types=1);", "" }, file)
	end

	vim.cmd("edit " .. file)

	if is_new then
		local fname = vim.fn.fnamemodify(file, ":t")
		local trig = pick_trigger(fname)
		if trig then
			vim.schedule(function()
				local ls = require("luasnip")
				local snip = ls.get_snippet_by_trigger(trig)
				if snip then
					ls.snip_expand(snip)
				else
					print("No snippet found for trigger: " .. trig)
				end
			end)
		end
	end
end

return M
