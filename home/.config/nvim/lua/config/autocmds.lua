-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Follow the macOS appearance inside herdr panes.
--
-- Ghostty reports light/dark changes to its child with DEC mode 2031, and Nvim's
-- TUI re-queries the background and flips 'background' when it sees one. Herdr
-- consumes that notification for its own UI and never relays it to its panes, so
-- an Nvim already running in a pane is never told. (Herdr does answer the OSC 11
-- background query correctly, which is why a freshly started Nvim gets it right,
-- and Nvim ignores an OSC 11 reply it did not ask for -- so polling the OS is the
-- only way in.) Drop this once herdr relays mode 2031.
if vim.fn.has("mac") == 1 and vim.env.HERDR_ENV then
  local group = vim.api.nvim_create_augroup("herdr_appearance", { clear = true })

  local function sync_background()
    vim.system({ "defaults", "read", "-g", "AppleInterfaceStyle" }, { text = true }, function(out)
      -- The key is absent (exit 1) in light mode.
      local bg = (out.code == 0 and out.stdout:find("Dark")) and "dark" or "light"
      vim.schedule(function()
        if vim.o.background ~= bg then
          vim.o.background = bg
        end
      end)
    end)
  end

  vim.uv.new_timer():start(2000, 2000, sync_background)
  vim.api.nvim_create_autocmd("FocusGained", { group = group, callback = sync_background })
end
