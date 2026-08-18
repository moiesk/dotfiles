-- markview.nvim now owns Markdown rendering so smart tables can replace its
-- table renderer. Running two previewers on the same buffer produces
-- overlapping extmarks and conceal rules.

return {
  "MeanderingProgrammer/render-markdown.nvim",
  enabled = false,
}
