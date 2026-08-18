-- markview.nvim now owns Markdown rendering so smart tables can replace its
-- table renderer. Running two previewers on the same buffer produces
-- overlapping extmarks and conceal rules.
--
-- If this plugin is ever re-enabled, restore `html.comment.conceal = false`
-- with it: render-markdown.nvim conceals HTML comments (`<!-- ... -->`) by
-- default, so they're invisible except on the cursor line, where anti-conceal
-- reveals them. Markdown has no other comment syntax, so concealing them hides
-- real content. markview.nvim does not conceal them, so nothing regresses while
-- this stays disabled.

return {
  "MeanderingProgrammer/render-markdown.nvim",
  enabled = false,
}
