local M = {}

M.config = {
	rules = {
		{ pattern = "Interface", trigger = "iface" },
		{ pattern = "Trait", trigger = "trait" },
		{ pattern = ".*", trigger = "class" },
	},
}

function M.setup(opts)
	M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

-- Parse PSR-4 from composer.json (autoload only)
local function load_psr4()
	local json = vim.fn.json_decode(vim.fn.readfile("composer.json"))
	local psr4 = {}

	if json["autoload"] and json["autoload"]["psr-4"] then
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

local function pick_trigger(filename)
	for _, rule in ipairs(M.config.rules) do
		if filename:match(rule.pattern) then
			return rule.trigger
		end
	end
	return nil
end

function M.create_from_namespace()
	local word = vim.fn.expand("<cWORD>"):gsub("^\\", "")
	local psr4 = load_psr4()

	-- find best matching namespace prefix
	local best_prefix, best_path
	for ns, paths in pairs(psr4) do
		if word:sub(1, #ns) == ns and (#ns > #(best_prefix or "")) then
			best_prefix, best_path = ns, paths[1] -- pick first path
		end
	end
	if not best_prefix then
		print("No PSR-4 mapping found for " .. word)
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
