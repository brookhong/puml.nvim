-- Locating the "current diagram" in a buffer (plain PlantUML files or markdown fences).
local config = require("puml.config")

local M = {}

function M.trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.indent_of(line)
  return line:match("^(%s*)") or ""
end

function M.indent_unit(buf)
  buf = buf or 0
  if vim.bo[buf].expandtab then
    local sw = vim.fn.shiftwidth()
    return string.rep(" ", sw > 0 and sw or 2)
  end
  return "\t"
end

function M.notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "puml" })
end

function M.is_markdown(buf)
  local o = config.options.markdown
  if not o.enabled then
    return false
  end
  return vim.tbl_contains(o.filetypes, vim.bo[buf].filetype)
end

-- Split `lines` into diagrams. Returns a list of { s, e, tag } (1-based rows of @start/@end).
local function find_diagrams(lines)
  local list, cur = {}, nil
  for i, l in ipairs(lines) do
    local tag = l:match("^%s*@start(%w+)")
    if tag then
      cur = { s = i, e = #lines, tag = tag:lower() }
      table.insert(list, cur)
    elseif cur and l:match("^%s*@end%w+") then
      cur.e = i
      cur = nil
    end
  end
  return list
end

--- Pick the diagram for `row` inside `lines`.
--- Returned rows are 1-based and relative to `lines`.
---   body_s/body_e : first/last row of the diagram body (without @start/@end)
---   input         : lines fed to PlantUML (always starts with @start...)
---   base          : row such that  buffer_row = base + plantuml_error_line(0-based)
local function pick(lines, row)
  local ds = find_diagrams(lines)
  if #ds == 0 then
    local input = { "@startuml" }
    vim.list_extend(input, lines)
    table.insert(input, "@enduml")
    return {
      tag = "uml",
      s = 1,
      e = #lines,
      body_s = 1,
      body_e = #lines,
      body = lines,
      input = input,
      base = 0,
      index = 1,
      count = 1,
      wrapped = true,
    }
  end
  local chosen, idx
  for i, d in ipairs(ds) do
    if d.s <= row and row <= d.e then
      chosen, idx = d, i
      break
    end
    if d.s <= row then
      chosen, idx = d, i
    end
  end
  if not chosen then
    chosen, idx = ds[1], 1
  end
  local has_end = lines[chosen.e] and lines[chosen.e]:match("^%s*@end%w+") ~= nil
  local body_e = has_end and chosen.e - 1 or chosen.e
  local input = vim.list_slice(lines, chosen.s, chosen.e)
  if not has_end then
    table.insert(input, "@end" .. chosen.tag)
  end
  return {
    tag = chosen.tag,
    s = chosen.s,
    e = chosen.e,
    body_s = chosen.s + 1,
    body_e = body_e,
    body = vim.list_slice(lines, chosen.s + 1, body_e),
    input = input,
    base = chosen.s,
    index = idx,
    count = #ds,
  }
end

local function shift(d, off)
  for _, k in ipairs({ "s", "e", "body_s", "body_e", "base" }) do
    d[k] = d[k] + off
  end
  return d
end

local function markdown_diagram(buf, lines, row)
  local fences = config.options.markdown.fences
  local open, n = nil, 0
  for i, l in ipairs(lines) do
    if not open then
      local lang = l:match("^%s*```+%s*{?%.?([%w_-]+)")
      if lang and vim.tbl_contains(fences, lang:lower()) then
        open = i
        n = n + 1
      end
    elseif l:match("^%s*```") then
      if open < row and row < i then
        local d = pick(vim.list_slice(lines, open + 1, i - 1), row - open)
        d.index, d.fence = n, { open, i }
        return shift(d, open)
      end
      open = nil
    end
  end
  return nil
end

--- Get the diagram under the cursor (or at `row`) for buffer `buf`.
--- Returns nil when in markdown and the cursor is not inside a plantuml fence.
function M.current(buf, row)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if not row then
    local win = vim.fn.bufwinid(buf)
    row = win ~= -1 and vim.api.nvim_win_get_cursor(win)[1] or 1
  end
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local d
  if M.is_markdown(buf) then
    d = markdown_diagram(buf, lines, row)
  else
    d = pick(lines, row)
  end
  if d then
    d.buf = buf
    d.type = require("puml.parse").detect(d.body, d.tag)
  end
  return d
end

--- Output path for a diagram rendered from `buf`.
function M.output_path(buf, d, ext, dir)
  local name = vim.api.nvim_buf_get_name(buf)
  local stem
  if name == "" then
    stem = "diagram-" .. buf
  else
    stem = vim.fn.fnamemodify(name, ":t:r")
  end
  if d and (d.count > 1 or d.fence) then
    stem = stem .. "-" .. d.index
  end
  dir = dir or (name ~= "" and vim.fn.fnamemodify(name, ":p:h")) or vim.fn.getcwd()
  vim.fn.mkdir(dir, "p")
  return dir .. "/" .. stem .. "." .. ext
end

return M
