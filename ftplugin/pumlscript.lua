-- puml script (.pus): indentation is the nesting, so indent like Python.
if vim.b.did_ftplugin then
  return
end
vim.b.did_ftplugin = true

vim.bo.commentstring = "# %s"
vim.bo.comments = ":#"
vim.bo.expandtab = true
vim.bo.shiftwidth = 4
vim.bo.softtabstop = 4
vim.bo.autoindent = true
vim.bo.indentexpr = "v:lua.require'puml.script'.indent()"
-- re-indent when a line starts with one of these, e.g. `else:` typed under the block
-- (no `<:>`: typing a `:` must not pull a line back into the block above)
vim.bo.indentkeys = "!^F,o,O,=elif,=else,=branch,=case"
vim.b.undo_ftplugin = "setl commentstring< comments< expandtab< shiftwidth< softtabstop< autoindent< indentexpr< indentkeys<"
