-- Make nvim-lint's markdownlint-cli2 respect the same config the CLI uses.
--
-- nvim-lint pipes the buffer over stdin (args = { "-" }), so markdownlint-cli2
-- has no file path to walk up from and resolves config purely from Neovim's
-- cwd. It does not search above cwd, so a project's .markdownlint-cli2.jsonc is
-- silently ignored whenever cwd isn't the project root. Resolve the config from
-- the buffer's own directory and pass it explicitly.
--
-- conform (the formatter) needs no such fix: it passes a real filename, so
-- markdownlint-cli2 walks up from the file and finds these configs on its own.

local CONFIG_NAMES = {
  ".markdownlint-cli2.jsonc",
  ".markdownlint-cli2.yaml",
  ".markdownlint-cli2.cjs",
  ".markdownlint.jsonc",
  ".markdownlint.json",
  ".markdownlint.yaml",
  ".markdownlint.yml",
}

-- Nearest project config wins; the home config is the fallback.
local function resolve_config()
  local buf = vim.api.nvim_buf_get_name(0)
  local start = buf ~= "" and vim.fs.dirname(buf) or vim.uv.cwd()
  local found = vim.fs.find(CONFIG_NAMES, { upward = true, path = start, type = "file" })[1]
  return found or vim.fs.normalize("~/.markdownlint-cli2.jsonc")
end

return {
  "mfussenegger/nvim-lint",
  opts = {
    linters = {
      ["markdownlint-cli2"] = {
        args = { "--config", resolve_config, "-" },
      },
    },
  },
}
