-- Filetype detection lives here, not in plugin/: Neovim (and lazy.nvim, for plugins
-- lazy-loaded with `ft = "plantuml"`) sources ftdetect/ at startup, so `:e foo.puml`
-- gets ft=plantuml, which in turn loads the plugin.
vim.filetype.add({
  extension = { puml = "plantuml", plantuml = "plantuml", pu = "plantuml", iuml = "plantuml", wsd = "plantuml",
    pus = "pumlscript" }, -- puml script, see docs/script.md
})

-- With lazy-loading by filetype, a `.pus` buffer only gets highlighting, indentation and
-- :PumlScript if "pumlscript" is in the plugin's `ft` list. Say so instead of silently
-- showing plain text.
vim.api.nvim_create_autocmd("FileType", {
  pattern = "pumlscript",
  group = vim.api.nvim_create_augroup("puml_ftdetect_check", { clear = true }),
  callback = function(ev)
    vim.schedule(function()
      if not vim.g.loaded_puml and not vim.g.puml_warned_lazy and vim.api.nvim_buf_is_valid(ev.buf) then
        vim.g.puml_warned_lazy = true
        vim.notify('puml.nvim is not loaded for .pus files: add "pumlscript" to its `ft` list '
          .. '(e.g. ft = { "plantuml", "pumlscript", "markdown" })', vim.log.levels.WARN)
      end
    end)
  end,
})
