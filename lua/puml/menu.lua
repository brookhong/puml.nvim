-- Action menu: the single entry point (keymaps.menu) to every puml action, so
-- users don't need to remember any keymaps. Only actions that make sense for the
-- diagram under the cursor (or the selection) are listed.
local config = require("puml.config")
local util = require("puml.util")

local M = {}

--- Every action: `key` is its fixed label in the menu.
--- `when(ctx)` decides availability; `label` may be a function of ctx.
--- `run(ctx)` — ctx.range is { s, e } when invoked on a selection.
M.actions = {
  {
    key = "i",
    label = function(ctx)
      return "Insert " .. ctx.d.type .. " element"
    end,
    when = function(ctx)
      -- something must fit the grammar where the new line goes (not inside a note, ...)
      if not (ctx.d and not ctx.range and not ctx.blank) then
        return false
      end
      local actions = require("puml.actions")
      local items = require("puml.feasible").insertable(ctx.d, actions.insertion_line(ctx.buf, ctx.d))
      return #items > 0
    end,
    run = function()
      require("puml.actions").insert()
    end,
  },
  {
    key = "c",
    label = "Connect two nodes",
    when = function(ctx)
      return ctx.d and not ctx.range and not ctx.blank and require("puml.actions").can_connect(ctx.d.type)
    end,
    run = function()
      require("puml.actions").connect()
    end,
  },
  {
    -- needs a selection: never listed in the normal-mode menu; with a selection it is
    -- the only action, so <leader>u goes straight to the block picker
    key = "w",
    label = "Wrap selection in block",
    when = function(ctx)
      return ctx.range ~= nil and ctx.wrap_ok
    end,
    run = function(ctx)
      require("puml.actions").wrap_range(ctx.range[1], ctx.range[2])
    end,
  },
  {
    key = "p",
    label = function(ctx)
      return ctx.preview_open and "Close preview" or "Open preview"
    end,
    when = function(ctx)
      return not ctx.range and (ctx.d ~= nil or ctx.preview_open)
    end,
    run = function(ctx)
      require("puml.preview").toggle(ctx.buf)
    end,
  },
  {
    key = "r",
    label = "Render now",
    when = function(ctx)
      return ctx.d and not ctx.range and not ctx.blank and ctx.preview_open
    end,
    run = function(ctx)
      require("puml.preview").render(ctx.buf, { force = true })
    end,
  },
  {
    key = "m",
    label = function(ctx)
      return "Preview mode (now: " .. ctx.mode .. ")"
    end,
    when = function(ctx)
      return ctx.d and not ctx.range and not ctx.blank
    end,
    run = function(ctx)
      local modes = vim.tbl_filter(function(m)
        return m ~= ctx.mode
      end, { "auto", "text", "image" })
      require("puml.picker").select(modes, { prompt = "Preview mode" }, function(m)
        if m then
          require("puml.preview").set_mode(ctx.buf, m)
        end
      end)
    end,
  },
  {
    key = "n",
    label = function(ctx)
      return ctx.d and not ctx.blank and "Add another diagram from template" or "New diagram from template"
    end,
    when = function(ctx)
      return not ctx.range
    end,
    run = function()
      require("puml.actions").new()
    end,
  },
  {
    key = "e",
    label = "Export diagram",
    when = function(ctx)
      return ctx.d and not ctx.range and not ctx.blank
    end,
    run = function()
      require("puml.actions").export()
    end,
  },
}

--- Collect what the menu needs to know about the cursor / selection.
function M.context(buf, range)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local win = vim.fn.bufwinid(buf)
  local row = win ~= -1 and vim.api.nvim_win_get_cursor(win)[1] or 1
  local d = util.current(buf, range and range[1] or row)
  local preview = require("puml.preview")
  local ctx = { buf = buf, range = range, row = row, d = d, preview_open = preview.is_open(buf) }
  if d then
    ctx.blank = true
    for _, l in ipairs(d.body) do
      if util.trim(l) ~= "" then
        ctx.blank = false
        break
      end
    end
    local s = preview.state[buf]
    ctx.mode = (s and s.mode) or config.options.preview.mode
    -- wrapping needs a selection inside a single diagram body, and blocks that fit the grammar there
    local s1, e1 = range and range[1] or row, range and range[2] or row
    local d2 = range and util.current(buf, e1) or d
    if not range then
      ctx.wraps = {} -- normal mode: wrapping is never offered
    elseif ctx.blank then
      ctx.wraps, ctx.wrap_reason = {}, "the diagram is empty"
    elseif not (d2 and d2.s == d.s) then
      ctx.wraps, ctx.wrap_reason = {}, "the selection spans more than one diagram"
    else
      ctx.wraps, ctx.wrap_reason = require("puml.feasible").wraps(d, s1, e1)
    end
    ctx.wrap_ok = #ctx.wraps > 0
  end
  return ctx
end

--- Actions available in `ctx`, with resolved labels.
function M.available(ctx)
  local out = {}
  for _, a in ipairs(M.actions) do
    if a.when(ctx) then
      local label = type(a.label) == "function" and a.label(ctx) or a.label
      table.insert(out, vim.tbl_extend("force", a, { label = label }))
    end
  end
  return out
end

--- Show the action menu for `buf`.
--- @param range table|nil { start_line, end_line } (from visual mode)
function M.open(buf, range)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  -- run actions in a window showing the source buffer (menu may be opened from the preview)
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 and vim.api.nvim_get_current_win() ~= win then
    vim.api.nvim_set_current_win(win)
  end
  local ctx = M.context(buf, range)
  local items = M.available(ctx)
  if #items == 0 then
    return util.notify(range and ("can't wrap: " .. (ctx.wrap_reason or "not inside a diagram")) or "nothing to do here", vim.log.levels.WARN)
  end
  -- a single choice (e.g. a selection can only be wrapped): skip the menu
  if #items == 1 then
    return items[1].run(ctx)
  end
  local title = "puml"
  if ctx.d then
    title = title .. " · " .. ctx.d.type
  end
  require("puml.picker").select(items, {
    prompt = title,
    kind = "puml_menu",
    format_item = function(a)
      return a.label
    end,
    -- fixed labels: <leader>u then the same letter always does the same thing
    key = function(a)
      return a.key
    end,
  }, function(a)
    if a then
      a.run(ctx)
    end
  end)
end

function M.open_visual()
  local s, e = vim.fn.line("v"), vim.fn.line(".")
  if s > e then
    s, e = e, s
  end
  local buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  M.open(buf, { s, e })
end

return M
