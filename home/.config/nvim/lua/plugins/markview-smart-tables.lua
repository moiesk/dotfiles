return {
  {
    "gunasekar/markview-smart-tables.nvim",
    -- Explicit: `keys` below would otherwise make this spec lazy, and the
    -- renderer hook has to be installed before markview draws anything.
    lazy = false,
    dependencies = {
      {
        "OXY2DEV/markview.nvim",
        lazy = false,
      },
    },
    keys = {
      -- Replaces the `<leader>um` toggle LazyVim registered from inside
      -- render-markdown.nvim's config, which is disabled here.
      { "<leader>um", "<cmd>Markview toggle<cr>", desc = "Toggle Markview" },
    },
    opts = {
      wrap_width = 0.9,
      wrap_minwidth = 5,
    },
    config = function(_, opts)
      require("markview-smart-tables").setup(opts)
      require("markview").setup({
        preview = {
          -- Preview must be active in a mode before hybrid_modes is consulted;
          -- outside `modes` markview tears the whole preview down instead of
          -- revealing just the node under the cursor.
          modes = { "n", "no", "c", "i", "v", "V", "\22", "R" },
          -- Reveal the source while the cursor is on a rendered node so tables
          -- remain easy to navigate and edit.
          hybrid_modes = { "n", "v", "V", "\22", "i", "R" },
        },
        renderers = {
          markdown_table = function(buffer, item)
            require("markview-smart-tables").render(buffer, item)
          end,
        },
      })
    end,
  },
}
