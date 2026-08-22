-- Kept as a deliberate tombstone: LazyVim enables render-markdown.nvim by
-- default, so disabling it needs a spec.
--
-- markview.nvim now owns Markdown rendering so smart tables can replace its
-- table renderer. Running two previewers on the same buffer produces
-- overlapping extmarks and conceal rules.
--
-- If this plugin is ever re-enabled, restore `html.comment.conceal = false`
-- with it: render-markdown.nvim conceals HTML comments (`<!-- ... -->`) by
-- default, so they're invisible except on the cursor line, where anti-conceal
-- reveals them. Markdown has no other comment syntax, so concealing them hides
-- real content. markview.nvim ships no HTML parser or renderer at all (its only
-- comment handling is the experimental `fancy_comments` support for code
-- comments, off by default), so nothing regresses while this stays disabled.

return {
  "MeanderingProgrammer/render-markdown.nvim",
  enabled = false,
}
