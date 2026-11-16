-- Live preview in a vertical split: text (ascii/unicode) or image path.
local config = require("puml.config")
local util = require("puml.util")
local render = require("puml.render")

local M = {}

local ns = vim.api.nvim_create_namespace("puml")
---@type table<integer, table> state per source buffer
M.state = {}

local function st(buf)
  M.state[buf] = M.state[buf] or { seq = 0 }
  return M.state[buf]
end

function M.resolve_mode(buf, typ)
  local s = st(buf)
  local p = config.options.preview
  local mode = s.mode or p.mode
  if mode == "auto" then
    mode = p.per_type[typ] or p.auto_default
  end
  return mode
end

local function image_size(path, fmt)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local data = f:read(fmt == "svg" and 2048 or 32) or ""
  f:close()
  if fmt == "png" and #data >= 24 and data:sub(2, 4) == "PNG" then
    local function u32(i)
      local a, b, c, d = data:byte(i, i + 3)
      return ((a * 256 + b) * 256 + c) * 256 + d
    end
    return u32(17) .. "x" .. u32(21) .. " px"
  elseif fmt == "svg" then
    local w, h = data:match('width="([%d%.]+)px"'), data:match('height="([%d%.]+)px"')
    if w and h then
      return w .. "x" .. h .. " px"
    end
  end
end

local function valid_win(w)
  return w and vim.api.nvim_win_is_valid(w)
end

function M.is_open(buf)
  local s = M.state[buf]
  return (s and valid_win(s.win) and s.pbuf and vim.api.nvim_buf_is_valid(s.pbuf) and vim.api.nvim_win_get_buf(s.win) == s.pbuf) == true
end

local function set_lines(pbuf, lines)
  vim.bo[pbuf].modifiable = true
  vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, lines)
  vim.bo[pbuf].modifiable = false
  vim.bo[pbuf].modified = false
end

-- the preview's own keys, right-aligned after the status text (`gx` only when there is an image)
local KEYS = "%=%#Comment# ? menu  q close  r render  m mode "
local KEYS_IMAGE = KEYS .. " gx open "

local function set_winbar(s, text, hl)
  if valid_win(s.win) then
    vim.wo[s.win].winbar = "%#" .. (hl or "WinBar") .. "#" .. text:gsub("%%", "%%%%") .. (s.image and KEYS_IMAGE or KEYS)
  end
end

local function set_diagnostics(buf, d, err)
  if not config.options.diagnostics then
    return
  end
  vim.diagnostic.reset(ns, buf)
  if err and d then
    local row = err.line and (d.base + err.line) or d.s
    row = math.max(1, math.min(row, vim.api.nvim_buf_line_count(buf)))
    vim.diagnostic.set(ns, buf, {
      { lnum = row - 1, col = 0, message = err.message or "PlantUML error", severity = vim.diagnostic.severity.ERROR, source = "plantuml" },
    })
  end
end

local function create_pbuf(buf)
  local pbuf = vim.api.nvim_create_buf(false, true)
  vim.bo[pbuf].bufhidden = "wipe"
  vim.bo[pbuf].buftype = "nofile"
  vim.bo[pbuf].swapfile = false
  vim.bo[pbuf].filetype = "pumlpreview"
  pcall(vim.api.nvim_buf_set_name, pbuf, "puml-preview://" .. buf)
  local o = { buffer = pbuf, nowait = true, silent = true }
  vim.keymap.set("n", "q", function()
    M.close(buf)
  end, vim.tbl_extend("force", o, { desc = "Close preview" }))
  vim.keymap.set("n", "r", function()
    M.render(buf, { force = true })
  end, vim.tbl_extend("force", o, { desc = "Re-render" }))
  vim.keymap.set("n", "m", function()
    M.cycle_mode(buf)
  end, vim.tbl_extend("force", o, { desc = "Cycle preview mode" }))
  for _, k in ipairs({ "?", "<CR>" }) do
    vim.keymap.set("n", k, function()
      require("puml.menu").open(buf)
    end, vim.tbl_extend("force", o, { desc = "puml menu" }))
  end
  vim.keymap.set("n", "gx", function()
    M.open_image(buf)
  end, vim.tbl_extend("force", o, { desc = "Open the preview image" }))
  return pbuf
end

--- Open the image the preview shows, from any line of the preview.
function M.open_image(buf)
  local s = M.state[buf]
  local path = s and s.image
  if not path then
    return util.notify("no image to open (the preview is not in image mode)", vim.log.levels.WARN)
  end
  if vim.fn.filereadable(path) == 0 then
    return util.notify("image not found: " .. path, vim.log.levels.WARN)
  end
  local _, err = vim.ui.open(path)
  if err then
    util.notify(err, vim.log.levels.ERROR)
  end
end

function M.open(buf)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  local s = st(buf)
  if M.is_open(buf) then
    return
  end
  local src_win = vim.fn.bufwinid(buf)
  if src_win == -1 then
    src_win = vim.api.nvim_get_current_win()
  end
  if not (s.pbuf and vim.api.nvim_buf_is_valid(s.pbuf)) then
    s.pbuf = create_pbuf(buf)
  end
  local w = config.options.preview.width
  local width = w > 1 and math.floor(w) or math.floor(vim.o.columns * w)
  s.win = vim.api.nvim_open_win(s.pbuf, false, { split = "right", win = src_win, width = width })
  local wo = vim.wo[s.win][0]
  wo.number, wo.relativenumber, wo.wrap, wo.list = false, false, false, false
  wo.signcolumn, wo.foldcolumn, wo.spell, wo.cursorline = "no", "0", false, false
  wo.winfixwidth = true
  s.key = nil
  M.render(buf, { force = true })
end

function M.close(buf)
  local s = M.state[buf]
  if s and valid_win(s.win) then
    pcall(vim.api.nvim_win_close, s.win, true)
  end
  if s then
    s.win = nil
  end
end

function M.toggle(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if M.is_open(buf) then
    M.close(buf)
  else
    M.open(buf)
  end
end

function M.cycle_mode(buf)
  local s = st(buf)
  local order = { "auto", "text", "image" }
  local cur = s.mode or config.options.preview.mode
  local i = 1
  for k, v in ipairs(order) do
    if v == cur then
      i = k
    end
  end
  M.set_mode(buf, order[i % #order + 1])
end

function M.set_mode(buf, mode)
  local s = st(buf)
  s.mode = mode
  util.notify("preview mode: " .. mode)
  if M.is_open(buf) then
    M.render(buf, { force = true })
  else
    M.open(buf)
  end
end

--- Render the diagram under the cursor of `buf` into its preview window.
function M.render(buf, opts)
  opts = opts or {}
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local s = st(buf)
  if not M.is_open(buf) then
    return
  end
  local d = util.current(buf)
  if not d then
    if not s.key then
      set_lines(s.pbuf, { "", "  Move the cursor into a ```plantuml block to preview it." })
      set_winbar(s, " PlantUML", "WinBar")
    end
    return
  end
  local mode = M.resolve_mode(buf, d.type)
  if mode ~= "image" then
    s.image = nil -- don't offer the previous image while text is rendering
  end
  local key = table.concat(d.input, "\n") .. "\0" .. mode
  if not opts.force and key == s.key then
    return
  end
  s.key = key
  s.seq = s.seq + 1
  local seq = s.seq
  if s.job then
    pcall(function()
      s.job:kill(9)
    end)
  end
  local p = config.options.preview
  local fmt = mode == "text" and p.text_format or p.image_format
  local out
  if mode == "image" then
    local dir = p.image_dir or (vim.fn.stdpath("cache") .. "/puml")
    out = util.output_path(buf, d, fmt, dir)
  end
  -- PlantUML's text output for activity diagrams has no boxes/arrows: draw them ourselves
  -- (PlantUML still runs below, for syntax errors / diagnostics).
  local builtin
  if mode == "text" and d.type == "activity" and p.builtin_text then
    local ok, res = pcall(require("puml.activity_text").render, d.body, { ascii = fmt == "txt" })
    builtin = ok and res or nil
  end
  local label = string.format(" PlantUML · %s · %s%s", d.type, mode, builtin and " (built-in)" or "")
  if builtin then
    set_lines(s.pbuf, builtin)
  end
  set_winbar(s, label .. (builtin and " · checking…" or " · rendering…"), "WinBar")
  s.job = render.render(d.input, fmt, out, function(res)
    if seq ~= s.seq or res.cancelled then
      return
    end
    s.job = nil
    if not M.is_open(buf) then
      return
    end
    set_diagnostics(buf, d, res.err)
    -- the image `gx` opens: this render's, or the last good one after an error
    if mode == "image" then
      s.last_image = not res.err and res.path or s.last_image
      s.image = s.last_image
    else
      s.image = nil
    end
    local stamp = os.date("%H:%M:%S")
    if res.err then
      local row = res.err.line and (d.base + res.err.line)
      set_winbar(s, label .. " · error" .. (row and (" at line " .. row) or "") .. " · " .. stamp, "DiagnosticError")
    else
      set_winbar(s, string.format("%s · %s (%dms)", label, stamp, res.ms), "WinBar")
    end
    if builtin and not res.err then
      set_lines(s.pbuf, builtin)
    elseif mode == "text" then
      local lines = vim.split((res.data or ""):gsub("%s+$", ""), "\n", { plain = true })
      if res.err and (res.data == nil or res.data == "") then
        lines = vim.split(res.err.message or "error", "\n")
      end
      set_lines(s.pbuf, lines)
    else
      local lines = { "" }
      if res.err then
        table.insert(lines, "  Error" .. (res.err.line and (" at line " .. (d.base + res.err.line)) or "") .. ":")
        for _, l in ipairs(vim.split(res.err.message or "", "\n")) do
          table.insert(lines, "    " .. l)
        end
        table.insert(lines, "")
        if s.last_image then
          table.insert(lines, "  Last good image:")
          table.insert(lines, "  " .. s.last_image)
        end
      else
        table.insert(lines, "  Image (" .. d.type .. ", " .. fmt .. "):")
        table.insert(lines, "")
        table.insert(lines, "  " .. res.path)
        table.insert(lines, "")
        local size = image_size(res.path, fmt)
        if size then
          table.insert(lines, "  Size:     " .. size)
        end
        table.insert(lines, "  Rendered: " .. stamp .. " (" .. res.ms .. "ms)")
        table.insert(lines, "")
        table.insert(lines, "  Tip: `gx` (on any line) opens it, `m` cycles preview mode.")
      end
      set_lines(s.pbuf, lines)
    end
  end)
end

--- Debounced render.
function M.schedule(buf, delay)
  local s = st(buf)
  if not M.is_open(buf) then
    return
  end
  s.timer = s.timer or vim.uv.new_timer()
  s.timer:stop()
  s.timer:start(delay or config.options.preview.debounce_ms, 0, function()
    vim.schedule(function()
      if vim.api.nvim_buf_is_valid(buf) then
        M.render(buf)
      end
    end)
  end)
end

--- Setup autocmds for a source buffer (idempotent).
function M.attach(buf)
  local s = st(buf)
  if s.attached then
    return
  end
  s.attached = true
  local group = vim.api.nvim_create_augroup("puml_preview_" .. buf, { clear = true })
  local p = config.options.preview
  if p.auto then
    vim.api.nvim_create_autocmd(p.events, {
      group = group,
      buffer = buf,
      callback = function()
        M.schedule(buf)
      end,
    })
  end
  if p.follow_cursor then
    vim.api.nvim_create_autocmd("CursorMoved", {
      group = group,
      buffer = buf,
      callback = function()
        local cur = M.state[buf]
        if not (cur and M.is_open(buf)) then
          return
        end
        -- cheap check: only re-render when the diagram under cursor changed
        local d = util.current(buf)
        local id = d and (d.s .. ":" .. d.index) or "none"
        if id ~= cur.diagram_id then
          cur.diagram_id = id
          M.schedule(buf, 50)
        end
      end,
    })
  end
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = group,
    buffer = buf,
    callback = function()
      M.close(buf)
      local cur = M.state[buf]
      if cur and cur.timer then
        cur.timer:stop()
        cur.timer:close()
      end
      M.state[buf] = nil
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
end

M.ns = ns
return M
