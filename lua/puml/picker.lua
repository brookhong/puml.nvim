-- Labelled picker, after foyer.nvim's: every choice wears a one-key label, a
-- single keypress picks it. `/` filters by words. Same signature as
-- vim.ui.select, which it falls back to when `picker.ui = "select"`.
local config = require("puml.config")

local M = {}

local api = vim.api

M.HL = {
  label = "PumlPickerLabel", -- the key badge in front of each choice
  detail = "PumlPickerDetail", -- right-hand column (descriptions, snippet preview)
  placeholder = "PumlPickerPlaceholder", -- what you'll be asked for / fill in: {condition}, Name, ...
  match = "PumlPickerMatch", -- filter matches
  cursor = "PumlPickerHiddenCursor",
}

function M.setup_highlights()
  local dark = vim.o.background ~= "light"
  local defs = {
    [M.HL.label] = dark and { fg = "#1b2b34", bg = "#fac863", ctermfg = 235, ctermbg = 221, bold = true }
      or { fg = "#ffffff", bg = "#d75f00", ctermfg = 231, ctermbg = 166, bold = true },
    [M.HL.detail] = { link = "Comment" },
    [M.HL.match] = { link = "Search" },
  }
  -- placeholders: the colour of Special, in italics, so they stand out of the dim detail
  local sp = api.nvim_get_hl(0, { name = "Special", link = false })
  defs[M.HL.placeholder] = { fg = sp.fg, ctermfg = sp.ctermfg, italic = true }
  for g, attrs in pairs(defs) do
    api.nvim_set_hl(0, g, vim.tbl_extend("force", attrs, { default = true }))
  end
  api.nvim_set_hl(0, M.HL.cursor, { blend = 100, nocombine = true })
end

local HIDE_ON_READ = vim.fn.has("nvim-0.11") == 1
local function read_key()
  if HIDE_ON_READ then
    return vim.fn.getcharstr(-1, { cursor = "hide" })
  end
  return vim.fn.getcharstr()
end

M.read_key = read_key -- overridable (tests)

local function hide_cursor()
  if HIDE_ON_READ then
    return function() end
  end
  local saved = vim.o.guicursor
  vim.o.guicursor = "a:" .. M.HL.cursor
  return function()
    vim.o.guicursor = saved
  end
end

local function cells(s)
  return vim.fn.strdisplaywidth(s)
end

local function words(q)
  return vim.split(q:lower(), "%s+", { trimempty = true })
end

--- Assign one-key labels to `list` ({ text, key? }): an item's own key first,
--- then a letter of its text (word initials before other letters), then
--- whatever is left of `chars`. Items left without a key get none (use `/`).
function M.assign(list, chars)
  local taken, labels = {}, {}
  local function free(c)
    return c and c ~= "" and not taken[c] and c ~= "/" and c ~= " "
  end
  for i, it in ipairs(list) do
    if it.key and free(it.key) then
      labels[i], taken[it.key] = it.key, true
    end
  end
  for i, it in ipairs(list) do
    if not labels[i] then
      local t = it.text:lower()
      local cands = {}
      for w in t:gmatch("%w+") do
        table.insert(cands, w:sub(1, 1))
      end
      for c in t:gmatch("%w") do
        table.insert(cands, c)
      end
      for _, c in ipairs(cands) do
        if free(c) and chars:find(c, 1, true) then
          labels[i], taken[c] = c, true
          break
        end
      end
    end
  end
  for i in ipairs(list) do
    if not labels[i] then
      for c in chars:gmatch(".") do
        if free(c) then
          labels[i], taken[c] = c, true
          break
        end
      end
    end
  end
  return labels
end

--- Placeholders in detail text are marked "\1text\2" (see M.desc / M.snippet).
--- Returns the plain text and the byte ranges { s, e } (0-based, end exclusive) of the placeholders.
function M.markup(s)
  local plain, ranges = {}, {}
  local len = 0
  for text, mark in (s .. "\1"):gmatch("([^\1\2]*)([\1\2])") do
    table.insert(plain, text)
    len = len + #text
    if mark == "\1" then
      table.insert(ranges, { len })
    elseif ranges[#ranges] and not ranges[#ranges][2] then
      ranges[#ranges][2] = len
    end
  end
  ranges = vim.tbl_filter(function(r)
    return r[2] and r[2] > r[1]
  end, ranges)
  return table.concat(plain), ranges
end

--- Description with `{name}` placeholders -> markup.
function M.desc(s)
  return s and (s:gsub("{([^}]+)}", "\1%1\2")) or nil
end

--- One-line preview of an LSP snippet body, its placeholders as markup:
--- "${1:A} -> ${2:B}: ${0:message}" -> "\1A\2 -> \1B\2: \1message\2".
function M.snippet(body)
  local first = body:match("^[^\n]*")
  local more = first ~= body
  local texts = {}
  local out = first:gsub("%${(%d+)|([^,|}]*)[^}]*}", function(n, c)
    texts[n] = texts[n] or c
    return "\1" .. c .. "\2"
  end):gsub("%${(%d+):([^}]*)}", function(n, d)
    texts[n] = texts[n] or d
    return d ~= "" and ("\1" .. d .. "\2") or ""
  end):gsub("%${(%d+)}", function(n)
    return texts[n] and ("\1" .. texts[n] .. "\2") or ""
  end):gsub("%$(%d+)", function(n)
    return texts[n] and ("\1" .. texts[n] .. "\2") or ""
  end)
  out = out:gsub("%s+$", "")
  return more and (out .. " …") or out
end

--- vim.ui.select-compatible picker.
--- Extra opts: `key(item) -> string|nil` preferred label, `detail(item) -> string|nil` dim right column
--- (placeholders marked with M.markup),
--- `anchor = { line, col0 }` open below that position instead of the cursor,
--- `place(width, height) -> row, col` explicit editor position of the border's corner.
function M.select(items, opts, on_choice)
  opts = opts or {}
  local pc = config.options.picker or {}
  if pc.ui == "select" then
    return vim.ui.select(items, opts, on_choice)
  end
  if #items == 0 then
    return on_choice(nil, nil)
  end
  local fmt = opts.format_item or tostring
  local all = {}
  for i, it in ipairs(items) do
    local text = fmt(it):gsub("\n", " ")
    all[i] = {
      item = it,
      idx = i,
      text = text,
      key = opts.key and opts.key(it) or nil,
      detail = opts.detail and opts.detail(it) or nil,
    }
    if all[i].detail then
      all[i].detail, all[i].ph = M.markup(all[i].detail)
    end
  end
  local chars = opts.chars or pc.characters or config.defaults.picker.characters
  -- labels are given out once over the whole list, so filtering never changes an item's key
  for i, l in pairs(M.assign(all, chars)) do
    all[i].key = l
  end

  -- size and place: just below the cursor (above when it fits only there)
  local text_w, detail_w = 0, 0
  for _, e in ipairs(all) do
    text_w = math.max(text_w, cells(e.text))
    detail_w = math.max(detail_w, e.detail and cells(e.detail) or 0)
  end
  local maxw = vim.o.columns - 4
  -- the names come first: keep at least 12 cells (or their full width) for them and
  -- shorten the detail column instead when the screen is narrow
  local min_text = math.min(text_w, 12)
  text_w = math.max(min_text, math.min(text_w, maxw - 6 - (detail_w > 0 and detail_w + 2 or 0)))
  if detail_w > 0 then
    detail_w = math.max(0, math.min(detail_w, maxw - 6 - text_w - 2))
  end
  local function clip(str, w)
    if cells(str) <= w then
      return str
    end
    return w <= 1 and "" or (vim.fn.strcharpart(str, 0, w - 1) .. "…")
  end
  -- below the cursor, or below `opts.anchor` = { line, col0 } (e.g. the end of a selection)
  local pos = opts.anchor and vim.fn.screenpos(0, opts.anchor[1], opts.anchor[2] + 1)
    or vim.fn.screenpos(0, vim.fn.line("."), vim.fn.col("."))
  local crow = pos.row > 0 and pos.row or math.floor(vim.o.lines / 2)
  local bottom = vim.o.lines - vim.o.cmdheight
  local below, above = bottom - crow - 2, crow - 1 - 2
  local room = math.max(1, math.max(below, above))
  local height = math.min(#all, opts.place and (vim.o.lines - vim.o.cmdheight - 2) or room)
  local row = (height > below and above > below) and (crow - 1 - height - 2) or crow
  local title = " " .. (opts.prompt or "Select"):gsub(":%s*$", "") .. " "

  M.setup_highlights()
  local buf = api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  local ns = api.nvim_create_namespace("puml_picker")
  local win
  local query, typing = "", false

  local function render()
    local list = all
    local ws = words(query)
    if #ws > 0 then
      list = vim.tbl_filter(function(e)
        local hay = (e.text .. " " .. (e.detail or "")):lower()
        for _, w in ipairs(ws) do
          if not hay:find(w, 1, true) then
            return false
          end
        end
        return true
      end, all)
    end
    local labels = M.assign(list, chars)
    local lines, marks = {}, {}
    local shown = {}
    for i = 1, math.min(#list, height) do
      local e = list[i]
      local text = clip(e.text, text_w)
      local left = " " .. (labels[i] or " ") .. "  " .. text
      local line = left
      local detail = e.detail and detail_w > 0 and clip(e.detail, detail_w) or ""
      if detail ~= "" then
        line = left .. string.rep(" ", 4 + text_w - cells(left) + 2) .. detail
      end
      table.insert(lines, line .. " ")
      -- placeholder ranges past the clipped end are dropped when highlighting
      table.insert(marks, { i - 1, labels[i] ~= nil, #left, e, #line - #detail, #detail })
      if labels[i] then
        shown[labels[i]] = e
      end
    end
    if #lines == 0 then
      lines = { "    no match " }
    end
    local more = #list - math.min(#list, height)
    local footer
    if typing then
      footer = " <CR>: pick · <Esc>: clear "
    else
      footer = " key: pick · /: filter · <Esc> "
    end
    if more > 0 then
      footer = " +" .. more .. " more ·" .. footer
    end
    local width = 6 + text_w + (detail_w > 0 and (2 + detail_w) or 0) + 1
    width = math.min(maxw, math.max(width, cells(footer) + 2, cells(title) + 2, 16))
    vim.bo[buf].modifiable = true
    api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    for _, m in ipairs(marks) do
      if m[2] then
        api.nvim_buf_set_extmark(buf, ns, m[1], 0, { end_col = 3, hl_group = M.HL.label })
      end
      if #lines[m[1] + 1] > m[3] then
        api.nvim_buf_set_extmark(buf, ns, m[1], m[3], { end_col = #lines[m[1] + 1], hl_group = M.HL.detail })
        for _, r in ipairs(m[4].ph or {}) do
          -- clipped detail: only placeholders before the "…"
          local last = m[6] - (m[6] < #(m[4].detail or "") and #"…" or 0)
          if r[1] < last then
            api.nvim_buf_set_extmark(buf, ns, m[1], m[5] + r[1], { end_col = m[5] + math.min(r[2], last), hl_group = M.HL.placeholder, priority = 4200 })
          end
        end
      end
      local low = lines[m[1] + 1]:lower()
      for _, w in ipairs(ws) do
        local s = low:find(w, 5, true)
        if s then
          api.nvim_buf_set_extmark(buf, ns, m[1], s - 1, { end_col = s - 1 + #w, hl_group = M.HL.match })
        end
      end
    end
    local wtitle, tpos = title, "center"
    if typing or query ~= "" then
      wtitle, tpos = " /" .. query .. (typing and "▁" or "") .. " ", "left"
    end
    local col = math.max(0, math.min((pos.col > 0 and pos.col or 1) - 1, vim.o.columns - width - 2))
    local prow = row
    if opts.place then
      prow, col = opts.place(width, height)
    end
    local cfg = {
      relative = "editor",
      row = math.max(0, prow),
      col = col,
      width = width,
      height = height,
      border = "rounded",
      title = wtitle,
      title_pos = tpos,
      footer = footer,
      footer_pos = "right",
    }
    if win then
      api.nvim_win_set_config(win, cfg)
    else
      cfg.style, cfg.focusable, cfg.noautocmd, cfg.zindex = "minimal", false, true, 60
      win = api.nvim_open_win(buf, false, cfg)
    end
    return shown, list
  end

  local restore, picked
  local ok, err = pcall(function()
    local shown, list = render()
    restore = hide_cursor()
    local esc, ctrl_c, cr = vim.keycode("<Esc>"), vim.keycode("<C-c>"), vim.keycode("<CR>")
    local bs, ctrl_h, ctrl_u = vim.keycode("<BS>"), vim.keycode("<C-h>"), vim.keycode("<C-u>")
    while true do
      vim.cmd("redraw")
      local rk, key = pcall(M.read_key)
      if not rk or key == ctrl_c then
        break
      end
      if typing then
        if key == esc then
          query, typing = "", false
        elseif key == cr then
          typing = false
          if #list == 1 then
            picked = list[1]
            break
          end
        elseif key == bs or key == ctrl_h then
          if query == "" then
            typing = false
          end
          query = vim.fn.strcharpart(query, 0, vim.fn.strchars(query) - 1)
        elseif key == ctrl_u then
          query = ""
        elseif #key > 0 and key:byte(1) >= 0x20 and key:byte(1) ~= 0x80 then
          query = query .. key
        end
        shown, list = render()
      elseif key == esc then
        if query == "" then
          break
        end
        query = ""
        shown, list = render()
      elseif key == "/" then
        typing = true
        shown, list = render()
      elseif key == cr and #list == 1 then
        picked = list[1]
        break
      elseif shown[key] then
        picked = shown[key]
        break
      end
      -- anything else is a slip of the finger: ignored
    end
  end)
  if restore then
    restore()
  end
  if win and api.nvim_win_is_valid(win) then
    api.nvim_win_close(win, true)
  end
  if api.nvim_buf_is_valid(buf) then
    pcall(api.nvim_buf_delete, buf, { force = true })
  end
  vim.cmd("redraw")
  if not ok then
    error(err, 0)
  end
  if picked then
    on_choice(picked.item, picked.idx)
  else
    on_choice(nil, nil)
  end
end

return M
