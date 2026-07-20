-- render-markdown.nvim conceals HTML comments (`<!-- ... -->`) by default, so
-- they're invisible except on the cursor line, where anti-conceal reveals them.
-- Markdown has no other comment syntax, so concealing them hides real content.

return {
  "MeanderingProgrammer/render-markdown.nvim",
  opts = {
    html = {
      comment = {
        conceal = false,
      },
    },
  },
}
