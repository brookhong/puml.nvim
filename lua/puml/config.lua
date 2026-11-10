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
    image_format = "png", -- "png" | "svg"
    image_dir = nil, -- default: stdpath("cache") .. "/puml"
  },

  export = {
    format = "png",
    dir = nil, -- default: directory of the source file (or cwd)
  },

  keymaps = {
    prefix = "<leader>u", -- set to false to disable all default keymaps
    textobjects = { inner = "iu", outer = "au" }, -- set to false to disable
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
  return M.options
end

return M
