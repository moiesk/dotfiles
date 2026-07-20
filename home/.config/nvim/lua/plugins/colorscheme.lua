-- Nvim's TUI re-queries the terminal background on a DEC 2031 theme notification
-- and updates 'background', which reloads the colorscheme. `flavour = "auto"`
-- makes catppuccin follow 'background', so macOS light/dark flips latte/mocha.

return {
  {
    "catppuccin/nvim",
    name = "catppuccin",
    opts = {
      flavour = "auto",
      background = { light = "latte", dark = "mocha" },
    },
  },

  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "catppuccin",
    },
  },
}
