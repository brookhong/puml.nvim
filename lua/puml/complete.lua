-- Completion: nvim-cmp source + omnifunc for declared names and catalog snippets.
local util = require("puml.util")
local parse = require("puml.parse")
local catalog = require("puml.catalog")

local M = {}

local function diagram()
  local buf = vim.api.nvim_get_current_buf()
  local ft = vim.bo[buf].filetype
  if ft ~= "plantuml" and not util.is_markdown(buf) then
    return nil
  end
  return util.current(buf)
end

---------------------------------------------------------------------------
-- nvim-cmp source
---------------------------------------------------------------------------
local source = {}
source.__index = source

function source.new()
  return setmetatable({}, source)
end

function source:get_debug_name()
  return "puml"
end

function source:is_available()
  return diagram() ~= nil
end

function source:get_keyword_pattern()
  return [[\k\+]]
end

function source:complete(_, callback)
  local d = diagram()
  if not d then
    return callback({ items = {}, isIncomplete = false })
  end
  local ok, cmp = pcall(require, "cmp")
  local K = ok and cmp.lsp.CompletionItemKind or { Variable = 6, Snippet = 15 }
  local items = {}
  for _, n in ipairs(parse.names(d.body)) do
    table.insert(items, { label = n, kind = K.Variable, detail = d.type .. " name" })
  end
  for _, it in ipairs(catalog.items_for(d.type)) do
    table.insert(items, {
      label = it.label,
      filterText = it.label:gsub("[^%w]+", " "),
      kind = K.Snippet,
      insertText = it.body,
      insertTextFormat = 2,
      documentation = { kind = "markdown", value = "```plantuml\n" .. it.body:gsub("%${%d+:?([^}]*)}", "%1") .. "\n```" },
    })
  end
  callback({ items = items, isIncomplete = false })
end

function M.register_cmp()
  local ok, cmp = pcall(require, "cmp")
  if ok and not M._registered then
    cmp.register_source("puml", source.new())
    M._registered = true
  end
end

---------------------------------------------------------------------------
-- omnifunc (names only)
---------------------------------------------------------------------------
function M.omnifunc(findstart, base)
  if findstart == 1 then
    local line = vim.api.nvim_get_current_line():sub(1, vim.fn.col(".") - 1)
    local s = line:find('[%w_%.%[%("]*$')
    return (s or #line + 1) - 1
  end
  local d = diagram()
  if not d then
    return {}
  end
  local res = {}
  for _, n in ipairs(parse.names(d.body)) do
    if base == "" or n:lower():find(base:lower(), 1, true) == 1 then
      table.insert(res, { word = n, menu = "[puml]" })
    end
  end
  return res
end

return M
