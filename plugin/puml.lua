if vim.g.loaded_puml then
  return
end
vim.g.loaded_puml = true

-- filetype detection: ftdetect/plantuml.lua

local function puml()
  return require("puml")
end

local function item_complete(arglead)
  local util = require("puml.util")
  local d = util.current(0)
  local ids = {}
  for _, it in ipairs(require("puml.catalog").items_for(d and d.type or "sequence")) do
    table.insert(ids, require("puml.catalog").slug(it.label))
  end
  return vim.tbl_filter(function(s)
    return s:find(arglead, 1, true) == 1
  end, ids)
end

local cmd = vim.api.nvim_create_user_command

cmd("Puml", function(o)
  puml().open(o.args)
end, { nargs = "?", complete = "file", desc = "Open a PlantUML diagram with live preview" })

cmd("PumlPreview", function()
  puml().attach(0)
  require("puml.preview").toggle(0)
end, { desc = "Toggle PlantUML preview split" })

cmd("PumlRender", function()
  puml().attach(0)
  local p = require("puml.preview")
  if not p.is_open(vim.api.nvim_get_current_buf()) then
    return p.open(0)
  end
  p.render(0, { force = true })
end, { desc = "Render the diagram under the cursor" })

cmd("PumlMode", function(o)
  puml().attach(0)
  local p = require("puml.preview")
  local buf = vim.api.nvim_get_current_buf()
  if o.args == "" then
    return p.cycle_mode(buf)
  end
  p.set_mode(buf, o.args)
end, {
  nargs = "?",
  complete = function()
    return { "auto", "text", "image" }
  end,
  desc = "Set preview mode",
})

cmd("PumlMenu", function(o)
  puml().attach(0)
  require("puml.menu").open(0, o.range > 0 and { o.line1, o.line2 } or nil)
end, { range = true, desc = "Menu of all puml actions" })

cmd("PumlCatalog", function()
  vim.cmd.enew()
  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype, vim.bo[buf].bufhidden, vim.bo[buf].swapfile = "nofile", "wipe", false
  pcall(vim.api.nvim_buf_set_name, buf, "puml-catalog")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, require("puml.catalog").mindmap())
  vim.bo[buf].filetype = "plantuml"
  puml().attach(buf)
  require("puml.preview").open(buf)
end, { desc = "Mindmap of diagram types and their available items" })

cmd("PumlInsert", function(o)
  require("puml.actions").insert(o.args)
end, { nargs = "?", complete = item_complete, desc = "Insert a PlantUML element" })

cmd("PumlConnect", function()
  require("puml.actions").connect()
end, { desc = "Connect two nodes with an arrow" })

cmd("PumlWrap", function(o)
  require("puml.actions").wrap_range(o.line1, o.line2, o.args ~= "" and o.args or nil)
end, { range = true, nargs = "?", desc = "Wrap lines in a block (loop/alt/if/package...)" })

cmd("PumlNew", function(o)
  require("puml.actions").new(o.args)
end, {
  nargs = "?",
  complete = function()
    return require("puml.catalog").template_order
  end,
  desc = "Insert a new diagram from a template",
})

cmd("PumlExport", function(o)
  require("puml.actions").export(o.args)
end, {
  nargs = "?",
  complete = function()
    return { "png", "svg", "txt", "utxt", "pdf", "eps", "latex", "vdx", "scxml" }
  end,
  desc = "Export the diagram under the cursor",
})

local group = vim.api.nvim_create_augroup("puml", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "*",
  callback = function(ev)
    local ft = vim.bo[ev.buf].filetype
    if ft == "plantuml" then
      puml().attach(ev.buf)
    elseif require("puml.util").is_markdown(ev.buf) then
      puml().attach(ev.buf)
    end
  end,
})
