-- lua/create_from_ns/init.lua
local M = {}

M.config = {
	rules = {
		{ pattern = "Interface", trigger = "iface" },
		{ pattern = "Trait", trigger = "trait" },
		{ pattern = ".*", trigger = "class" },
	},
	keymap = nil, -- optional: { "n", "<leader>cn" } or { "n", "<leader>cn", "<cmd>CreateFromNS<CR>", { silent = true } }
}

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
	if M.config.keymap then
		local mode, lhs, rhs, kmopts = unpack(M.config.keymap)
		vim.keymap.set(mode, lhs, rhs or "<cmd>CreateFromNS<CR>", kmopts or { desc = "Create from namespace" })
	end
end

-- --- helpers ---------------------------------------------------------------

-- Parse PSR-4 (autoload only), using tdd.nvim-style handling of string|array paths.
local function load_psr4()
	local ok, raw = pcall(vim.fn.readfile, "composer.json")
	if not ok or not raw or #raw == 0 then
		return {}
	end
	local okj, json = pcall(vim.fn.json_decode, raw)
	if not okj or type(json) ~= "table" then
		return {}
	end

	local psr4 = {}
	local autoload = json["autoload"]
	if autoload and autoload["psr-4"] then
		for ns, paths in pairs(autoload["psr-4"]) do
			if type(paths) == "string" then
				psr4[ns] = { paths }
			elseif type(paths) == "table" then
				psr4[ns] = paths
			end
		end
	end
	return psr4
end

-- Find fully qualified name near cursor (e.g. \Vendor\Pkg\Name)
local function fqn_near_cursor()
	local row, col = unpack(vim.api.nvim_win_get_cursor(0)) -- row:1-based, col:0-based
	local line = vim.api.nvim_buf_get_lines(0, row - 1, row, false)[1] or ""
	if line == "" then
		return nil
	end
	local c = col + 1 -- 1-based indexing for Lua strings

	local spans = {}
	for s, e in line:gmatch("()\\[%w_\\]+()") do
		table.insert(spans, { s = s, e = e - 1 })
	end
	if #spans == 0 then
		local word = vim.fn.expand("<cWORD>")
		local m = word and word:match("\\[%w_\\]+")
		return m and m:gsub("^%?+", "") or nil
	end

	for _, sp in ipairs(spans) do
		if c >= sp.s and c <= sp.e then
			return line:sub(sp.s, sp.e):gsub("^%?+", "")
		end
	end
	local left, right
	for _, sp in ipairs(spans) do
		if sp.e < c then
			left = (not left or sp.e > left.e) and sp or left
		elseif sp.s > c then
			right = (not right or sp.s < right.s) and sp or right
		end
	end
	local chosen = left or right or spans[1]
	return chosen and line:sub(chosen.s, chosen.e):gsub("^%?+", "") or nil
end

local function pick_trigger(filename)
	for _, rule in ipairs(M.config.rules) do
		if filename:match(rule.pattern) then
			return rule.trigger
		end
	end
	return nil
end

-- Find a LuaSnip snippet for current filetype by its trigger.
local function get_snippet_by_trigger(trig)
	local ok, ls = pcall(require, "luasnip")
	if not ok then
		return nil
	end
	local ft = vim.bo.filetype
	if not ft or ft == "" then
		return nil
	end

	local snips = ls.get_snippets(ft) or {}
	-- In different LuaSnip versions this can be nested; scan recursively.
	local function scan(tbl)
		for _, v in pairs(tbl) do
			if type(v) == "table" then
				if (v.trig or v.trigger) == trig then
					return v
				end
				local found = scan(v)
				if found then
					return found
				end
			end
		end
		return nil
	end
	return scan(snips)
end

-- --- main ------------------------------------------------------------------

function M.create_from_namespace()
	local fqn = fqn_near_cursor()
	if not fqn then
		print("No namespace found on this line.")
		return
	end

	local word = fqn:gsub("^\\+", "")
	local psr4 = load_psr4()

	-- longest-prefix match
	local best_prefix, best_base
	for ns, paths in pairs(psr4) do
		if word:sub(1, #ns) == ns and (#ns > #(best_prefix or "")) then
			best_prefix, best_base = ns, paths[1]
		end
	end
	if not best_prefix then
		print("No PSR-4 mapping found for " .. fqn)
		return
	end

	local rel = word:sub(#best_prefix + 1):gsub("\\", "/")
	local file = best_base .. rel .. ".php"

	local is_new = vim.fn.filereadable(file) == 0
	if is_new then
		vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
		-- touch empty file
		vim.fn.writefile({}, file)
	end

	vim.cmd("edit " .. vim.fn.fnameescape(file))

	if is_new then
		-- decide and expand snippet
		local fname = vim.fn.fnamemodify(file, ":t")
		local trig = pick_trigger(fname)
		if not trig then
			return
		end

		vim.schedule(function()
			local snip = get_snippet_by_trigger(trig)
			if not snip then
				print("No LuaSnip snippet found for trigger: " .. trig)
				return
			end
			-- make sure we're in insert mode and at BOF for clean expansion
			vim.api.nvim_win_set_cursor(0, { 1, 0 })
			vim.cmd("startinsert")
			require("luasnip").snip_expand(snip)
		end)
	end
end

return M
