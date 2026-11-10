if vim.b.did_ftplugin then
  return
end
vim.b.did_ftplugin = true

vim.bo.commentstring = "' %s"
vim.bo.comments = "sO:/',mO:\\ ,eO:'/,:'"
vim.b.undo_ftplugin = "setl commentstring< comments<"
