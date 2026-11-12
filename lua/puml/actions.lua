-- Authoring actions: insert element, connect nodes, wrap in block, new diagram, export.
local config = require("puml.config")
local util = require("puml.util")
local parse = require("puml.parse")
local catalog = require("puml.catalog")
local render = require("puml.render")
local picker = require("puml.picker")

local M = {}

local function current_or_warn(buf)
  local d = util.current(buf)
  if not d then
    util.notify("cursor is not inside a PlantUML diagram", vim.log.levels.WARN)
  end
  return d
end

-- Where to insert a new line relative to the cursor, and with which indent.
local function insertion_point(buf, d)
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  if d then
    if d.fence and row <= d.fence[1] then
      row = d.fence[1]
    end
    if not d.wrapped and row < d.body_s then
      row = d.body_s - 1 -- right after @startuml
    elseif row > d.body_e then
      row = d.body_e
    end
  end
  local line = lines[row] or ""
  local indent = util.indent_of(line)
  if util.trim(line) == "" then
    -- use the indentation of the previous non-blank line
    for r = row - 1, 1, -1 do
      if util.trim(lines[r]) ~= "" then
        indent = util.indent_of(lines[r])
        line = lines[r]
        break
      end
    end
  end
  local tl = util.trim(line):lower()
  if parse._opener(tl) and not tl:match("^@") then
    indent = indent .. util.indent_unit(buf)
  elseif tl:match("^else") or tl:match("^elseif") or tl:match("^case") or tl:match("^fork again") or tl:match("^split again") then
    indent = indent .. util.indent_unit(buf)
  end
  return row, indent, util.trim(lines[row] or "") == ""
end

--- Buffer line the new statement will occupy (it goes before that line), see insert_snippet.
function M.insertion_line(buf, d)
  local row, _, blank = insertion_point(buf, d)
  if blank and row == vim.api.nvim_win_get_cursor(0)[1] then
    return row
  end
  return row + 1
end

--- Insert a snippet body on a new line below the cursor (or on the current line if blank).
function M.insert_snippet(body, buf)
  buf = buf or vim.api.nvim_get_current_buf()
  local d = util.current(buf)
  local row, indent, blank = insertion_point(buf, d)
  if blank and row == vim.api.nvim_win_get_cursor(0)[1] then
    vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { "" })
  else
    vim.api.nvim_buf_set_lines(buf, row, row, false, { "" })
    row = row + 1
  end
  vim.api.nvim_win_set_cursor(0, { row, 0 })
  M.expand(body, indent, buf)
end

--- Expand a snippet at the cursor on an empty line, applying `indent` to every line.
function M.expand(body, indent, buf)
  local unit = util.indent_unit(buf)
  body = body:gsub("\t", function()
    return unit
  end)
  body = indent .. body:gsub("\n", function()
    return "\n" .. indent
  end)
  vim.snippet.expand(body)
end

local function pick_item(items, prompt, cb)
  picker.select(items, {
    prompt = prompt,
    format_item = function(it)
      return it.label
    end,
    detail = function(it)
      return picker.snippet(it.body)
    end,
  }, function(it)
    if it then
      cb(it)
    end
  end)
end

--- Insert an element from the catalog of the current diagram type.
--- @param id string|nil catalog item id (slug of label); prompts when nil
function M.insert(id)
  local buf = vim.api.nvim_get_current_buf()
  local d = current_or_warn(buf)
  if not d then
    return
  end
  -- only what fits the grammar where the new line goes
  local items, why = require("puml.feasible").insertable(d, M.insertion_line(buf, d))
  if id and id ~= "" then
    local it = catalog.find(d.type, id)
    if not it then
      return util.notify("unknown element '" .. id .. "' for " .. d.type, vim.log.levels.WARN)
    end
    if not vim.tbl_contains(items, it) then
      return util.notify("can't insert " .. it.label .. " here", vim.log.levels.WARN)
    end
    return M.insert_snippet(it.body, buf)
  end
  if #items == 0 then
    return util.notify("can't insert here: " .. (why or "nothing fits"), vim.log.levels.WARN)
  end
  pick_item(items, "Insert " .. d.type .. " element", function(it)
    M.insert_snippet(it.body, buf)
  end)
end

local NEW = "+ new name…"

local function pick_name(names, prompt, cb)
  local choices = vim.list_extend(vim.deepcopy(names), { NEW })
  picker.select(choices, {
    prompt = prompt,
    key = function(c)
      return c == NEW and "+" or nil
    end,
  }, function(choice)
    if not choice then
      return
    end
    if choice == NEW then
      vim.ui.input({ prompt = prompt .. " (new): " }, function(v)
        if v and util.trim(v) ~= "" then
          cb(util.trim(v))
        end
      end)
    else
      cb(choice)
    end
  end)
end

local function add_direction(arrow, dir)
  if not dir or dir == "" then
    return arrow
  end
  local s, n = arrow:gsub("%-%-", "-" .. dir .. "-", 1)
  if n == 0 then
    s, n = arrow:gsub("%.%.", "." .. dir .. ".", 1)
  end
  if n == 0 then
    s, n = arrow:gsub("%-", "-" .. dir .. "-", 1)
  end
  return s
end

--- Whether connecting two nodes with an arrow makes sense for `typ`.
function M.can_connect(typ)
  return not (typ == "activity" or typ == "mindmap" or typ == "wbs" or typ == "gantt")
end

--- Connect two nodes: pick from, to, arrow style, (direction), label.
function M.connect()
  local buf = vim.api.nvim_get_current_buf()
  local d = current_or_warn(buf)
  if not d then
    return
  end
  if not M.can_connect(d.type) then
    return util.notify("connect is not applicable to " .. d.type .. " diagrams; use insert instead", vim.log.levels.WARN)
  end
  local names = parse.names(d.body)
  local win = vim.api.nvim_get_current_win()
  pick_name(names, "From", function(from)
    local to_names = vim.tbl_filter(function(n)
      return n ~= from
    end, names)
    if d.type == "sequence" then
      table.insert(to_names, from) -- self message last
    end
    pick_name(to_names, "To (from " .. from .. ")", function(to)
      picker.select(catalog.arrows_for(d.type), {
        prompt = "Arrow " .. from .. " ? " .. to,
        format_item = function(a)
          return a.label
        end,
      }, function(a)
        if not a then
          return
        end
        local function finish(dir)
          local arrow = add_direction(a.arrow, dir)
          vim.ui.input({ prompt = "Label (optional): " }, function(label)
            if label == nil then
              return
            end
            if not vim.api.nvim_win_is_valid(win) then
              return
            end
            vim.api.nvim_set_current_win(win)
            local line = from .. " " .. arrow .. " " .. to
            label = util.trim(label)
            if label ~= "" then
              line = line .. (d.type == "sequence" and ": " or " : ") .. label
            end
            local cur = util.current(buf) or d
            local row, indent, blank = insertion_point(buf, cur)
            if blank and row == vim.api.nvim_win_get_cursor(0)[1] then
              vim.api.nvim_buf_set_lines(buf, row - 1, row, false, { indent .. line })
            else
              vim.api.nvim_buf_set_lines(buf, row, row, false, { indent .. line })
              row = row + 1
            end
            vim.api.nvim_win_set_cursor(0, { row, #indent })
          end)
        end
        if d.type ~= "sequence" and config.options.connect.ask_direction then
          picker.select({ "(auto)", "up", "down", "left", "right" }, {
            prompt = "Direction",
            key = function(x)
              return ({ ["(auto)"] = "a", up = "k", down = "j", left = "h", right = "l" })[x]
            end,
          }, function(dir)
            if dir == nil then
              return
            end
            finish(dir ~= "(auto)" and dir or nil)
          end)
        else
          finish(nil)
        end
      end)
    end)
  end)
end

--- Wrap rows [s, e] (1-based, inclusive) of the current buffer in a block.
function M.wrap_range(s, e, label)
  local buf = vim.api.nvim_get_current_buf()
  local d = util.current(buf, s)
  if not d then
    return util.notify("selection is not inside a PlantUML diagram", vim.log.levels.WARN)
  end
  local wraps, why = require("puml.feasible").wraps(d, s, e)
  if #wraps == 0 then
    return util.notify("can't wrap: " .. (why or "no blocks for " .. d.type), vim.log.levels.WARN)
  end
  local function apply(w)
    local function go(answer)
      answer = util.trim(answer or "")
      local function fill(t)
        local r = t:gsub("%%s", function()
          return answer
        end)
        return util.trim((r:gsub("  +", " ")))
      end
      local lines = vim.api.nvim_buf_get_lines(buf, s - 1, e, false)
      local base
      for _, l in ipairs(lines) do
        if util.trim(l) ~= "" then
          local ind = util.indent_of(l)
          if not base or #ind < #base then
            base = ind
          end
        end
      end
      base = base or ""
      local unit = util.indent_unit(buf)
      local out = { base .. fill(w.open) }
      for _, l in ipairs(lines) do
        table.insert(out, util.trim(l) == "" and l or (unit .. l))
      end
      for _, m in ipairs(w.mid or {}) do
        table.insert(out, base .. fill(m))
        table.insert(out, base .. unit)
      end
      table.insert(out, base .. fill(w.close))
      vim.api.nvim_buf_set_lines(buf, s - 1, e, false, out)
      if w.mid then
        vim.api.nvim_win_set_cursor(0, { s + #lines + 2, #base + #unit })
      else
        vim.api.nvim_win_set_cursor(0, { s, #base })
      end
    end
    if w.prompt then
      vim.ui.input({ prompt = w.prompt .. ": ", default = w.default }, function(v)
        if v ~= nil then
          go(v)
        end
      end)
    else
      go("")
    end
  end
  if label then
    for _, w in ipairs(wraps) do
      if w.label == label or catalog.slug(w.label) == label then
        return apply(w)
      end
    end
    for _, w in ipairs(catalog.wraps_for(d.type)) do
      if w.label == label or catalog.slug(w.label) == label then
        return util.notify("can't wrap this selection in " .. w.label, vim.log.levels.WARN)
      end
    end
    return util.notify("unknown block '" .. label .. "' for " .. d.type, vim.log.levels.WARN)
  end
  picker.select(wraps, {
    prompt = "Wrap " .. (e - s + 1) .. " line(s) in",
    detail = function(w)
      return picker.desc(w.desc)
    end,
    -- exactly where the selection hint was (beside the selection), with its labels
    chars = require("puml.hint").keys(),
    place = function(w, h)
      return require("puml.hint").place(s, e, w, h)
    end,
    format_item = function(w)
      return w.label
    end,
  }, function(w)
    if w then
      apply(w)
    end
  end)
end

--- Insert a new diagram from a template.
function M.new(typ)
  local function apply(t)
    local body = catalog.templates[t]
    if not body then
      return util.notify("unknown template " .. t, vim.log.levels.WARN)
    end
    local buf = vim.api.nvim_get_current_buf()
    local ft = vim.bo[buf].filetype
    if ft == "" then
      vim.bo[buf].filetype = "plantuml"
    end
    if util.is_markdown(buf) then
      body = "```plantuml\n" .. body .. "\n```"
    end
    local empty = vim.api.nvim_buf_line_count(buf) == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
    if t == "empty" then
      if not empty then
        vim.api.nvim_buf_set_lines(buf, vim.fn.line("."), vim.fn.line("."), false, { "" })
        vim.api.nvim_win_set_cursor(0, { vim.fn.line(".") + 1, 0 })
      end
      M.expand(body, "", buf)
      return
    end
    local lines = vim.split(body, "\n", { plain = true })
    if empty then
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
    else
      local row = vim.fn.line(".")
      table.insert(lines, 1, "")
      vim.api.nvim_buf_set_lines(buf, row, row, false, lines)
      vim.api.nvim_win_set_cursor(0, { row + 2, 0 })
    end
    require("puml.preview").schedule(buf, 10)
  end
  if typ and typ ~= "" then
    return apply(typ)
  end
  picker.select(catalog.template_order, {
    prompt = "New diagram",
    detail = function(t)
      return catalog.template_desc[t]
    end,
  }, function(t)
    if t then
      apply(t)
    end
  end)
end

--- Export the current diagram to a file next to the source.
function M.export(fmt)
  local buf = vim.api.nvim_get_current_buf()
  local d = current_or_warn(buf)
  if not d then
    return
  end
  fmt = (fmt and fmt ~= "") and fmt or config.options.export.format
  local ext = fmt == "utxt" and "utxt" or fmt
  local path = util.output_path(buf, d, ext, config.options.export.dir)
  util.notify("exporting " .. d.type .. " diagram → " .. path)
  render.render(d.input, fmt, path, function(res)
    if res.ok then
      util.notify("exported: " .. path)
    else
      util.notify("export failed: " .. ((res.err and res.err.message) or "unknown error"), vim.log.levels.ERROR)
    end
  end)
end

return M
