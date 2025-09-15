if vim.g.loaded_create_from_ns then
	return
end
vim.g.loaded_create_from_ns = true

vim.api.nvim_create_user_command("CreateFromNS", function()
	require("create_from_ns").create_from_namespace()
end, {})
