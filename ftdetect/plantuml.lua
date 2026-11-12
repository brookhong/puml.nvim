-- Filetype detection lives here, not in plugin/: Neovim (and lazy.nvim, for plugins
-- lazy-loaded with `ft = "plantuml"`) sources ftdetect/ at startup, so `:e foo.puml`
-- gets ft=plantuml, which in turn loads the plugin.
vim.filetype.add({
  extension = { puml = "plantuml", plantuml = "plantuml", pu = "plantuml", iuml = "plantuml", wsd = "plantuml" },
})
