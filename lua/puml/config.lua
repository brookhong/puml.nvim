local M = {}

M.defaults = {
  -- Command used to run PlantUML locally. Use e.g. { "java", "-jar", "/path/to/plantuml.jar" }.
  cmd = { "plantuml" },
  -- Optional PlantUML server (picoweb or plantuml-server), e.g. "http://localhost:8080".
  -- When set, rendering is done over HTTP with curl instead of `cmd`.
  server = nil,
  curl = "curl",

  preview = {
    auto = true, -- re-render automatically on `events`
    events = { "BufWritePost", "TextChanged", "InsertLeave" },
    debounce_ms = 400,
    follow_cursor = true, -- re-render when the cursor moves to another diagram (multi-diagram files / markdown)
    width = 0.5, -- vertical split width (ratio of columns, or absolute columns if > 1)
    mode = "auto", -- "auto" | "text" | "image"
    -- In "auto" mode: diagram types listed here use the given mode, everything else uses `auto_default`.
    per_type = { sequence = "text" },
    auto_default = "image",
    text_format = "utxt", -- "utxt" (unicode box drawing) | "txt" (plain ascii)
    -- Draw activity diagrams in text mode with the built-in renderer (PlantUML's text
    -- output for them has no boxes or arrows). false = use PlantUML's output as-is.
    builtin_text = true,
    image_format = "png", -- "png" | "svg"
    image_dir = nil, -- default: stdpath("cache") .. "/puml"
  },

  export = {
    format = "png",
    dir = nil, -- default: directory of the source file (or cwd)
  },

  keymaps = {
    -- The only default mapping (normal + visual): opens the menu of everything that makes
    -- sense at the cursor / selection. false = no mapping (use :PumlMenu).
    menu = "<leader>u",
    -- Opt-in text objects for the enclosing block, e.g. { inner = "iu", outer = "au" }.
    textobjects = false,
  },

  -- Pickers (menu, insert, connect, wrap, templates): "labels" = foyer-style popup where each
  -- choice has a one-key label (mnemonic when possible; `/` filters), "select" = vim.ui.select.
  picker = {
    ui = "labels",
    selection_hint = true, -- in visual mode, show the wrap blocks + labels beside the selection
    -- Labels for wrap blocks. In linewise visual (V) they are live keys while the hint shows,
    -- so only keys of little use there (in-line / word motions, q, m, z); never j/k/G/{/}/o/
    -- y/d/c/x/p/>/</=/:/n/i/a/...).
    selection_keys = "lhwebftqmzWBEFTQK",
    characters = "asdfghjklqwertyuiopzxcvbnm1234567890ASDFGHJKLQWERTYUIOPZXCVBNM", -- allowed labels
  },

  connect = {
    ask_direction = true, -- ask for up/down/left/right on non-sequence diagrams
  },

  markdown = {
    enabled = true,
    filetypes = { "markdown" },
    fences = { "plantuml", "puml", "uml" },
  },

  -- Extra / overriding catalog entries per diagram type, e.g.
  -- catalog = { sequence = { { label = "my thing", body = "A -> B: ${1}" } } }
  catalog = {},

  diagnostics = true,
  cmp = true, -- register an nvim-cmp source named "puml" if nvim-cmp is installed
}

M.options = vim.deepcopy(M.defaults)

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", vim.deepcopy(M.defaults), opts or {})
  -- lists should be replaced, not merged
  if opts and opts.cmd then
    M.options.cmd = opts.cmd
  end
  if opts and opts.preview and opts.preview.events then
    M.options.preview.events = opts.preview.events
  end
  -- old config: `keymaps.prefix` now names the menu key
  local km = opts and opts.keymaps
  if type(km) == "table" and km.menu == nil and km.prefix ~= nil then
    M.options.keymaps.menu = km.prefix
  end
  if km == false then
    M.options.keymaps = { menu = false, textobjects = false }
  end
  return M.options
end

return M
