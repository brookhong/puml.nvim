-- While lines are selected in visual mode, show the wrap blocks beside the
-- selection, labelled. In linewise visual (V) the labels are live: pressing one
-- wraps the selection. Labels are drawn from `picker.selection_keys`: keys of little
-- use in linewise visual (in-line and word motions, q, m, z), never the ones that
-- extend or act on a selection, so j/k/G/{/} and y/d/c/>/... keep working. In
-- charwise/blockwise visual the hint is passive and `<leader>u` + label picks.
local config = require("puml.config")

local M = {}

local api = vim.api
local ns = api.nvim_create_namespace("puml_hint")
local state = { win = nil, buf = nil, maps = nil, sig = nil }

local VISUAL = { v = true, V = true, ["\22"] = true }

--- Where a popup of `width` x `height` (without border) goes for lines s..e of
--- the current window: to the right of the selected text, or under it when
--- there is no room. Returns editor row, col (0-based) of the border's corner.
function M.place(s, e, width, height)
  local win = api.nvim_get_current_win()
  local wpos = api.nvim_win_get_position(win)
  local wheight = api.nvim_win_get_height(win)
  local top = vim.fn.screenpos(win, s, 1)
  if top.row == 0 then -- start of the selection scrolled off: top of the window
    top = { row = wpos[1] + 1, col = vim.fn.screenpos(win, vim.fn.line("w0"), 1).col }
  end
  local textcol = top.col > 0 and top.col or (wpos[2] + 1)
  local maxw = 0
  for _, l in ipairs(api.nvim_buf_get_lines(0, s - 1, e, false)) do
    maxw = math.max(maxw, vim.fn.strdisplaywidth(l))
  end
  local leftcol = vim.fn.winsaveview().leftcol
  local col = textcol - 1 + math.max(0, maxw - leftcol) + 2
  local row = top.row - 2 -- first entry level with the first selected line
  -- a float may cover a neighbouring split (e.g. the preview) while selecting
  if col + width + 2 > vim.o.columns then
    -- no room beside it: under the selection
    local bot = vim.fn.screenpos(win, e, 1)
    row = bot.row > 0 and bot.row or (wpos[1] + wheight)
    col = textcol - 1
  end
  local maxrow = vim.o.lines - vim.o.cmdheight - height - 2
  row = math.max(0, math.min(row, maxrow))
  col = math.max(0, math.min(col, vim.o.columns - width - 2))
  return row, col
end

--- Remove the live label mappings, restoring buffer-local ones they shadowed.
local function unmap()
  local m = state.maps
  state.maps = nil
  if not (m and api.nvim_buf_is_valid(m.buf)) then
    return
  end
  for _, lhs in ipairs(m.keys) do
    pcall(vim.keymap.del, "x", lhs, { buffer = m.buf })
    local saved = m.saved[lhs]
    if saved then
      api.nvim_buf_call(m.buf, function()
        vim.fn.mapset("x", false, saved)
      end)
    end
  end
end

--- Map each label in visual mode to "wrap the selection in that block".
local function map_labels(buf, labels, wraps)
  -- the mappings capture their block: remap whenever labels or blocks differ
  local parts = { buf }
  for i, w in ipairs(wraps) do
    parts[#parts + 1] = (labels[i] or "") .. "=" .. w.label
  end
  local sig = table.concat(parts, "\0")
  if state.maps and state.maps.sig == sig then
    return
  end
  unmap()
  local m = { buf = buf, sig = sig, keys = {}, saved = {} }
  for i, w in ipairs(wraps) do
    local lhs = labels[i]
    if lhs then
      local old = vim.fn.maparg(lhs, "x", false, true)
      if old and old.buffer == 1 then
        m.saved[lhs] = old
      end
      vim.keymap.set("x", lhs, function()
        local s, e = vim.fn.line("v"), vim.fn.line(".")
        if s > e then
          s, e = e, s
        end
        api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
        require("puml.actions").wrap_range(s, e, w.label)
      end, { buffer = buf, nowait = true, silent = true, desc = "puml: wrap selection in " .. w.label })
      table.insert(m.keys, lhs)
    end
  end
  state.maps = m
end

function M.close()
  state.sig = nil
  unmap()
  if state.win and api.nvim_win_is_valid(state.win) then
    pcall(api.nvim_win_close, state.win, true)
  end
  state.win = nil
end

--- Keys selection labels are drawn from.
function M.keys()
  local pc = config.options.picker or {}
  return pc.selection_keys or config.defaults.picker.selection_keys
end

--- The blocks the selection s..e of `buf` can be wrapped in (nil if none).
--- Also the reason when there are none (only for selections inside a diagram).
local function blocks(buf, s, e)
  local ctx = require("puml.menu").context(buf, { s, e })
  if not ctx.wrap_ok then
    return nil, ctx.d and not ctx.blank and ctx.wrap_reason or nil
  end
  return ctx.wraps
end

--- Show (or move) the hint float beside lines s..e.
local function show(s, e, lines, width, title, footer, highlight)
  local height = #lines
  local row, col = M.place(s, e, width, height)
  if not (state.buf and api.nvim_buf_is_valid(state.buf)) then
    state.buf = api.nvim_create_buf(false, true)
    vim.bo[state.buf].bufhidden = "hide"
  end
  api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
  require("puml.picker").setup_highlights()
  api.nvim_buf_clear_namespace(state.buf, ns, 0, -1)
  highlight(state.buf)
  local cfg = {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    border = "rounded",
    title = title,
    title_pos = "center",
    footer = footer or "",
    footer_pos = "right",
  }
  if state.win and api.nvim_win_is_valid(state.win) then
    api.nvim_win_set_config(state.win, cfg)
  else
    cfg.style, cfg.focusable, cfg.noautocmd, cfg.zindex = "minimal", false, true, 50
    state.win = api.nvim_open_win(state.buf, false, cfg)
  end
end

--- Whether the hint is on (it can be turned off by a later setup()).
function M.enabled()
  local pc, km = config.options.picker or {}, config.options.keymaps
  -- labels only mean something with the labelled picker and a menu key to fall back on
  return pc.selection_hint ~= false and pc.ui ~= "select" and km and km.menu and true or false
end

function M.update(buf)
  if not M.enabled() then
    return M.close()
  end
  if not VISUAL[api.nvim_get_mode().mode] or api.nvim_get_current_buf() ~= buf then
    return M.close()
  end
  local s, e = vim.fn.line("v"), vim.fn.line(".")
  if s > e then
    s, e = e, s
  end
  -- called on every key (on_key): nothing to do if neither selection, text nor view changed
  local view = vim.fn.winsaveview()
  local sig = table.concat({ buf, api.nvim_get_current_win(), api.nvim_get_mode().mode, s, e,
    vim.b[buf].changedtick, view.topline, view.leftcol, vim.o.columns, vim.o.lines }, ":")
  if sig == state.sig and (state.win == nil or api.nvim_win_is_valid(state.win)) then
    return
  end
  state.sig = sig
  local wraps, why = blocks(buf, s, e)
  if not wraps and not why then
    M.close()
    state.sig = sig -- remember "nothing to show" for this selection too
    return
  end
  local picker = require("puml.picker")
  if not wraps then
    -- inside a diagram but nothing fits the grammar: say why, passively
    unmap()
    local line = " ✗ " .. why .. " "
    local w = math.min(vim.fn.strdisplaywidth(line), vim.o.columns - 4)
    show(s, e, { line }, w, " can't wrap ", nil, function(b)
      api.nvim_buf_set_extmark(b, ns, 0, 0, { end_col = #line, hl_group = "DiagnosticWarn" })
    end)
    return
  end
  local chars = M.keys()
  local list = {}
  for i, w in ipairs(wraps) do
    list[i] = { text = w.label }
  end
  local labels = picker.assign(list, chars) -- same labels the picker gives out
  -- " l  loop      repeat while a condition holds ": label, block, description
  local lw = 0
  for _, w in ipairs(wraps) do
    lw = math.max(lw, vim.fn.strdisplaywidth(w.label))
  end
  local lines, width, desc_col = {}, 0, 4 + lw + 2
  local ph = {} -- per line: placeholder byte ranges
  for i, w in ipairs(wraps) do
    local left = " " .. (labels[i] or " ") .. "  " .. w.label
    local desc, ranges = "", {}
    if w.desc then
      desc, ranges = picker.markup(picker.desc(w.desc))
    end
    local pad = desc ~= "" and string.rep(" ", desc_col - vim.fn.strdisplaywidth(left)) or ""
    lines[i] = left .. pad .. desc .. " "
    ph[i] = vim.tbl_map(function(r)
      return { #left + #pad + r[1], #left + #pad + r[2] }
    end, ranges)
    width = math.max(width, vim.fn.strdisplaywidth(lines[i]))
  end
  local live = api.nvim_get_mode().mode == "V"
  if live then
    map_labels(buf, labels, wraps)
  else
    unmap()
  end
  local footer = live and " key: wrap " or (" " .. config.options.keymaps.menu .. " + key ")
  local title = " wrap " .. (e - s + 1) .. " line" .. (e > s and "s" or "") .. " "
  width = math.max(width, vim.fn.strdisplaywidth(footer) + 2, vim.fn.strdisplaywidth(title) + 2)
  show(s, e, lines, width, title, footer, function(b)
    for i = 1, #lines do
      api.nvim_buf_set_extmark(b, ns, i - 1, 0, { end_col = 3, hl_group = picker.HL.label })
      local dc = #(" " .. (labels[i] or " ") .. "  " .. wraps[i].label) -- byte col where the padding starts
      if #lines[i] > dc then
        api.nvim_buf_set_extmark(b, ns, i - 1, dc, { end_col = #lines[i], hl_group = picker.HL.detail })
      end
      for _, r in ipairs(ph[i]) do
        api.nvim_buf_set_extmark(b, ns, i - 1, r[1], { end_col = r[2], hl_group = picker.HL.placeholder, priority = 4200 })
      end
    end
  end)
end

function M.attach(buf)
  local group = api.nvim_create_augroup("puml_hint_" .. buf, { clear = true })
  -- always attached; whether the hint shows is decided on each update (M.enabled),
  -- so turning it off/on in a later setup() takes effect right away
  vim.b[buf].puml_hint = true -- read by the on_key handler below
  local function refresh()
    -- after the mode/cursor change has settled
    vim.schedule(function()
      if api.nvim_buf_is_valid(buf) then
        M.update(buf)
      end
    end)
  end
  api.nvim_create_autocmd({ "ModeChanged", "CursorMoved", "WinScrolled", "TextChanged" }, {
    group = group,
    buffer = buf,
    callback = refresh,
  })
  -- ModeChanged/CursorMoved are not always triggered: e.g. which-key runs `gv` through
  -- nvim_feedkeys and then waits for the next key in its own getchar() loop, so neither
  -- they nor SafeState fire. Every key goes through on_key, also fed ones.
  if not M._on_key then
    M._on_key = vim.on_key(function()
      local b = api.nvim_get_current_buf()
      if vim.b[b].puml_hint then
        vim.schedule(function()
          if api.nvim_buf_is_valid(b) and api.nvim_get_current_buf() == b then
            M.update(b)
          end
        end)
      end
    end, api.nvim_create_namespace("puml_hint_keys"))
  end
  api.nvim_create_autocmd({ "BufLeave", "WinLeave" }, { group = group, buffer = buf, callback = M.close })
end

return M
