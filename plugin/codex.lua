if vim.fn.has("nvim-0.8.0") ~= 1 then
  vim.api.nvim_err_writeln("Codex requires Neovim >= 0.8.0")
  return
end

if vim.g.loaded_codex then
  return
end
vim.g.loaded_codex = 1

-- Optional auto-setup: set vim.g.codex_auto_setup = { auto_start = true }
if vim.g.codex_auto_setup then
  vim.defer_fn(function()
    require("codex").setup(vim.g.codex_auto_setup)
  end, 0)
end

local main_module_ok, _ = pcall(require, "codex")
if not main_module_ok then
  vim.notify("Codex: Failed to load main module. Plugin may not function correctly.", vim.log.levels.ERROR)
end
