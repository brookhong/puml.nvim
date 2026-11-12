-- Built-in text renderer for activity diagrams (new syntax).
-- PlantUML's -tutxt/-ttxt output for activity diagrams only places the labels
-- (no boxes, no arrows), so we draw them ourselves.
--
-- Supported: start/stop/end/kill/detach, :action; (multi-line), -> labels,
-- if/elseif/else/endif, switch/case/endswitch, while/endwhile,
-- repeat/repeat while, fork/fork again/end fork, split, partition/group, title.
-- Notes, swimlanes, skinparams and styling are ignored.
local M = {}

local UNI = {
  h = "─", v = "│", tl = "┌", tr = "┐", bl = "└", br = "┘",
  rtl = "╭", rtr = "╮", rbl = "╰", rbr = "╯",
  td = "┬", tu = "┴", x = "┼",
  down = "▼", right = "►", merge = "◇", bar = "═",
  hl = "<", hr = ">", h1 = "╱", h2 = "╲",
  start = "●", stop = "◉", ["end"] = "⊗",
}
local ASCII = {
  h = "-", v = "|", tl = "+", tr = "+", bl = "+", br = "+",
  rtl = "+", rtr = "+", rbl = "+", rbr = "+",
  td = "+", tu = "+", x = "+",
  down = "v", right = ">", merge = "o", bar = "=",
  hl = "<", hr = ">", h1 = "/", h2 = "\\",
  start = "(*)", stop = "(@)", ["end"] = "(x)",
}

-- canvas ----------------------------------------------------------------------------------

local function chars(s)
  local out = {}
  for ch in s:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
    table.insert(out, ch)
  end
  return out
end

local function width(s)
  return vim.fn.strdisplaywidth(s)
end

local function block(w, h, cx)
  return { w = w, h = h, cx = cx or math.floor((w - 1) / 2), cells = {} }
end

local function put(b, x, y, ch)
  b.cells[y] = b.cells[y] or {}
  b.cells[y][x] = ch
  if x + 1 > b.w then
    b.w = x + 1
  end
  if y + 1 > b.h then
    b.h = y + 1
  end
end

local function text(b, x, y, s)
  for _, ch in ipairs(chars(s)) do
    put(b, x, y, ch)
    local w = width(ch)
    for i = 1, w - 1 do
      put(b, x + i, y, "") -- wide char: following cell is consumed
    end
    x = x + math.max(w, 1)
  end
end

-- (empty when x2 < x1 / y2 < y1)
local function hline(b, x1, x2, y, ch)
  for x = x1, x2 do
    put(b, x, y, ch)
  end
end

local function vline(b, x, y1, y2, ch)
  for y = y1, y2 do
    put(b, x, y, ch)
  end
end

local function blit(dst, src, ox, oy)
  for y, row in pairs(src.cells) do
    for x, ch in pairs(row) do
      put(dst, ox + x, oy + y, ch)
    end
  end
  dst.w = math.max(dst.w, ox + src.w)
  dst.h = math.max(dst.h, oy + src.h)
end

local function to_lines(b)
  local out = {}
  for y = 0, b.h - 1 do
    local row, parts = b.cells[y] or {}, {}
    for x = 0, b.w - 1 do
      local ch = row[x]
      if ch ~= "" then
        table.insert(parts, ch or " ")
      end
    end
    out[#out + 1] = (table.concat(parts):gsub("%s+$", ""))
  end
  return out
end

-- parser ------------------------------------------------------------------------------------

local function strip(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function paren(s)
  return s and strip(s:match("^%s*%((.*)%)%s*$") or s) or ""
end

local function clean_text(s)
  s = s:gsub("\\n", "\n"):gsub("<[^>]+>", "")
  s = s:gsub("%*%*(.-)%*%*", "%1"):gsub("//(.-)//", "%1"):gsub("__(.-)__", "%1"):gsub('""(.-)""', "%1")
  return s
end

--- Parse activity body lines into a tree. Returns root sequence and title.
function M.parse(lines)
  local root = {}
  local stack = { { seq = root } }
  local title
  local function top()
    return stack[#stack]
  end
  local function add(node)
    table.insert(top().seq, node)
    return node
  end
  local function push(node, seq, extra)
    table.insert(stack, vim.tbl_extend("force", { node = node, seq = seq }, extra or {}))
  end
  local function pop_to(kinds)
    for i = #stack, 2, -1 do
      if kinds[stack[i].node.kind] then
        local f = stack[i]
        for _ = i, #stack do
          table.remove(stack)
        end
        -- chained `elseif` frames are closed together with their outer `if`
        if f.chained then
          return pop_to(kinds)
        end
        return f
      end
    end
  end

  local i, n = 1, #lines
  local skip_until
  while i <= n do
    local raw = lines[i]
    local l = strip(raw)
    local ll = l:lower()
    i = i + 1
    if skip_until then
      if ll:match(skip_until) then
        skip_until = nil
      end
    elseif l == "" or l:match("^'") then
      -- comment
    elseif l:match("^/'") then
      if not l:match("'/%s*$") then
        skip_until = "'/%s*$"
      end
    elseif l:match("^#?[%w#]*:") and not ll:match("^note") and not ll:match("^title") then
      -- :action; possibly spanning several lines
      local body = l:gsub("^#?[%w#]*:", "", 1)
      while not body:match("[;|<>/%]}]%s*$") and i <= n do
        body = body .. "\n" .. strip(lines[i])
        i = i + 1
      end
      body = body:gsub("[;|<>/%]}]%s*$", "")
      add({ kind = "action", text = clean_text(body) })
    elseif ll == "start" then
      add({ kind = "start" })
    elseif ll == "stop" then
      add({ kind = "stop" })
    elseif ll == "end" or ll == "kill" or ll == "detach" then
      add({ kind = "end" })
    elseif l:match("^%-[^%s]*>") then
      local lbl = strip((l:gsub("^%-[^%s]*>", "", 1):gsub(";%s*$", "")))
      if lbl ~= "" then
        add({ kind = "label", text = clean_text(lbl) })
      end
    elseif ll:match("^title%s") then
      title = strip(l:sub(7))
    elseif ll:match("^if%s*%(") then
      local cond = l:match("^%a+%s*%((.*)%)%s*then") or l:match("^%a+%s*%((.*)%)") or ""
      local lbl = l:match("then%s*%((.-)%)%s*$") or ""
      local node = add({ kind = "if", cond = clean_text(cond), branches = { { label = lbl, seq = {} } } })
      push(node, node.branches[1].seq)
    elseif ll:match("^else%s*if%s*%(") or ll:match("^elseif%s*%(") then
      local f = top()
      if f.node and f.node.kind == "if" then
        local cond = l:match("%((.*)%)%s*then") or l:match("%((.*)%)") or ""
        local lbl = l:match("then%s*%((.-)%)%s*$") or ""
        local br = { label = "", seq = {} }
        table.insert(f.node.branches, br)
        local node = { kind = "if", cond = clean_text(cond), branches = { { label = lbl, seq = {} } } }
        table.insert(br.seq, node)
        push(node, node.branches[1].seq, { chained = true })
      end
    elseif ll:match("^else") then
      local f = top()
      if f.node and f.node.kind == "if" then
        local br = { label = paren(l:match("^%a+%s*(.*)$")), seq = {} }
        table.insert(f.node.branches, br)
        f.seq = br.seq
      end
    elseif ll:match("^endif") or ll:match("^end%s+if") then
      pop_to({ ["if"] = true })
    elseif ll:match("^switch%s*%(") then
      local node = add({ kind = "switch", cond = clean_text(l:match("%((.*)%)") or ""), branches = {} })
      push(node, {})
    elseif ll:match("^case%s*%(") then
      local f = top()
      if f.node and f.node.kind == "switch" then
        local br = { label = clean_text(l:match("%((.*)%)") or ""), seq = {} }
        table.insert(f.node.branches, br)
        f.seq = br.seq
      end
    elseif ll:match("^endswitch") then
      pop_to({ switch = true })
    elseif ll:match("^while%s*%(") then
      local cond = l:match("^%a+%s*%((.*)%)%s*is") or l:match("^%a+%s*%((.*)%)") or ""
      local node = add({ kind = "while", cond = clean_text(cond), yes = l:match("is%s*%((.-)%)%s*$") or "", body = {} })
      push(node, node.body)
    elseif ll:match("^endwhile") or ll:match("^end%s+while") then
      local f = pop_to({ ["while"] = true })
      if f then
        f.node.no = paren(l:match("^%a+%s*(.*)$") or "")
      end
    elseif ll:match("^repeat%s*while") or ll:match("^repeatwhile") then
      local f = pop_to({ ["repeat"] = true })
      if f then
        f.node.cond = clean_text(l:match("%((.-)%)") or "")
        f.node.yes = l:match("is%s*%((.-)%)") or ""
        f.node.no = l:match("not%s*%((.-)%)") or ""
      end
    elseif ll:match("^repeat") then
      local node = add({ kind = "repeat", body = {} })
      push(node, node.body)
      local act = l:match("^%a+%s*:(.*)[;|<>/%]}]%s*$")
      if act then
        table.insert(node.body, { kind = "action", text = clean_text(act) })
      end
    elseif ll:match("^fork%s+again") or ll:match("^split%s+again") then
      local f = top()
      if f.node and f.node.kind == "fork" then
        local br = { label = "", seq = {} }
        table.insert(f.node.branches, br)
        f.seq = br.seq
      end
    elseif ll:match("^end%s*fork") or ll:match("^end%s*merge") or ll:match("^end%s*split") then
      pop_to({ fork = true })
    elseif ll == "fork" or ll == "split" then
      local node = add({ kind = "fork", branches = { { label = "", seq = {} } } })
      push(node, node.branches[1].seq)
    elseif ll:match("^partition%s") or ll:match("^group%s") or ll:match("^package%s") or ll:match("^rectangle%s") or ll:match("^card%s") then
      local name = l:gsub("^%a+%s+", "", 1):gsub("%s*{%s*$", ""):gsub("^#%w+%s+", ""):gsub('^"(.*)"$', "%1")
      local node = add({ kind = "partition", title = clean_text(strip(name)), body = {} })
      push(node, node.body)
    elseif ll == "}" or ll:match("^end%s*group") then
      pop_to({ partition = true })
    elseif ll:match("^note") or ll:match("^floating%s+note") then
      if not l:find(":", 1, true) then
        skip_until = "^end%s*note"
      end
    elseif ll:match("^legend") then
      skip_until = "^end%s*legend"
    end
    -- everything else (skinparam, swimlanes |X|, detach arrows, ...) is ignored
  end
  return root, title
end

-- layout --------------------------------------------------------------------------------------

local C
local layout_seq

local function lines_of(s)
  return vim.split(s, "\n", { plain = true })
end

local function action(node)
  local ls = lines_of(node.text)
  local w = 0
  for _, l in ipairs(ls) do
    w = math.max(w, width(l))
  end
  local b = block(w + 4, #ls + 2)
  put(b, 0, 0, C.rtl)
  hline(b, 1, w + 2, 0, C.h)
  put(b, w + 3, 0, C.rtr)
  for k, l in ipairs(ls) do
    put(b, 0, k, C.v)
    text(b, 2, k, l)
    put(b, w + 3, k, C.v)
  end
  put(b, 0, #ls + 1, C.rbl)
  hline(b, 1, w + 2, #ls + 1, C.h)
  put(b, w + 3, #ls + 1, C.rbr)
  return b
end

local function terminal(kind)
  local s = C[kind]
  local b = block(width(s), 1)
  text(b, 0, 0, s)
  b.term = kind ~= "start"
  return b
end

-- hexagon for conditions:  ╱───╲ / <  c  > / ╲───╱
local function hexagon(cond)
  local ls = lines_of(cond ~= "" and cond or " ")
  local w = 0
  for _, l in ipairs(ls) do
    w = math.max(w, width(l))
  end
  local b = block(w + 6, #ls + 2)
  local last = #ls + 1
  put(b, 1, 0, C.h1)
  hline(b, 2, w + 3, 0, C.h)
  put(b, w + 4, 0, C.h2)
  local mid = math.floor((#ls + 1) / 2)
  for k, l in ipairs(ls) do
    if k == mid then
      put(b, 0, k, C.hl)
      put(b, w + 5, k, C.hr)
    else
      put(b, 1, k, C.v)
      put(b, w + 4, k, C.v)
    end
    text(b, 3 + math.floor((w - width(l)) / 2), k, l)
  end
  put(b, 1, last, C.h2)
  hline(b, 2, w + 3, last, C.h)
  put(b, w + 4, last, C.h1)
  b.mid = mid
  return b
end

local function passthrough()
  local b = block(1, 1, 0)
  put(b, 0, 0, C.v)
  return b
end

-- branches side by side under an optional header (if/switch) or a bar (fork)
local function branches(header, list, is_fork)
  local gap = 3
  local cols, x = {}, 0
  for _, br in ipairs(list) do
    local b = layout_seq(br.seq)
    local lw = br.label ~= "" and (width(br.label) + 2) or 0
    local colw = math.max(b.w, b.cx + 1 + lw)
    table.insert(cols, { b = b, x = x, cx = x + b.cx, label = br.label })
    x = x + colw + gap
  end
  local mid = math.floor((cols[1].cx + cols[#cols].cx) / 2)
  local out = block(1, 1)
  local hx = header and (mid - header.cx) or 0
  local shift = math.max(0, -hx)
  if shift > 0 then
    hx, mid = hx + shift, mid + shift
    for _, c in ipairs(cols) do
      c.x, c.cx = c.x + shift, c.cx + shift
    end
  end
  local y = 0
  if header then
    blit(out, header, hx, 0)
    put(out, mid, header.h - 1, C.td)
    y = header.h
  end
  local first, last = cols[1].cx, cols[#cols].cx
  -- split row
  if is_fork then
    hline(out, first - 1, last + 1, y, C.bar)
  elseif #cols == 1 then
    put(out, first, y, C.v)
  else
    hline(out, first, last, y, C.h)
    put(out, first, y, C.tl)
    put(out, last, y, C.tr)
    for k = 2, #cols - 1 do
      put(out, cols[k].cx, y, C.td)
    end
    local at_branch = false
    for _, c in ipairs(cols) do
      at_branch = at_branch or c.cx == mid
    end
    put(out, mid, y, at_branch and C.x or C.tu)
  end
  y = y + 1
  local any_label = false
  for _, c in ipairs(cols) do
    any_label = any_label or c.label ~= ""
  end
  if any_label then
    for _, c in ipairs(cols) do
      put(out, c.cx, y, C.v)
      if c.label ~= "" then
        text(out, c.cx + 2, y, c.label)
      end
    end
    y = y + 1
  end
  for _, c in ipairs(cols) do
    put(out, c.cx, y, C.down)
  end
  y = y + 1
  local maxh = 0
  for _, c in ipairs(cols) do
    blit(out, c.b, c.x, y)
    maxh = math.max(maxh, c.b.h)
  end
  local open = {}
  for _, c in ipairs(cols) do
    if not c.b.term then
      vline(out, c.cx, y + c.b.h, y + maxh, C.v)
      table.insert(open, c.cx)
    end
  end
  y = y + maxh + 1
  if #open == 0 then
    out.term = true
    out.h = y - 1
    out.cx = mid
    return out
  end
  if is_fork then
    hline(out, math.min(open[1], mid) - 1, math.max(open[#open], mid) + 1, y, C.bar)
  elseif #open == 1 and open[1] == mid then
    put(out, mid, y, C.v)
  else
    local lo, hi = math.min(open[1], mid), math.max(open[#open], mid)
    hline(out, lo, hi, y, C.h)
    for _, cx in ipairs(open) do
      put(out, cx, y, cx == lo and C.bl or cx == hi and C.br or C.tu)
    end
    local at_open = vim.tbl_contains(open, mid)
    if not at_open then
      put(out, mid, y, mid == lo and C.tl or mid == hi and C.tr or C.td)
    elseif mid ~= lo and mid ~= hi then
      put(out, mid, y, C.x)
    end
  end
  out.h = y + 1
  out.cx = mid
  return out
end

local function while_loop(node)
  local hdr = hexagon(node.cond)
  local body = layout_seq(node.body)
  local yes, no = node.yes or "", node.no or ""
  local ox = 3
  local cx = ox + math.max(hdr.cx, body.cx)
  local hx, bx = cx - hdr.cx, cx - body.cx
  local out = block(1, 1)
  blit(out, hdr, hx, 0)
  put(out, cx, hdr.h - 1, C.td)
  local hm = hdr.mid
  local y = hdr.h
  put(out, cx, y, C.v)
  if yes ~= "" then
    text(out, cx + 2, y, yes)
  end
  put(out, cx, y + 1, C.down)
  y = y + 2
  blit(out, body, bx, y)
  y = y + body.h
  local right = math.max(hx + hdr.w, bx + body.w, cx + 3 + width(yes))
  local hr = hx + hdr.w -- column after the hexagon's ">"
  local R = math.max(right + 1, hr + width(no) + 3)
  if not body.term then
    put(out, cx, y, C.v)
    y = y + 1
    hline(out, 0, cx, y, C.h)
    put(out, 0, y, C.bl)
    put(out, cx, y, C.br)
    vline(out, 0, hm + 1, y - 1, C.v)
    put(out, 0, hm, C.tl)
    hline(out, 1, hx - 2, hm, C.h)
    put(out, hx - 1, hm, C.right)
  end
  y = y + 1
  hline(out, hr, R - 1, hm, C.h)
  if no ~= "" then
    text(out, hr + 1, hm, no)
  end
  put(out, R, hm, C.tr)
  vline(out, R, hm + 1, y - 1, C.v)
  put(out, R, y, C.br)
  hline(out, cx + 1, R - 1, y, C.h)
  put(out, cx, y, C.tl)
  out.h, out.cx = y + 1, cx
  return out
end

local function repeat_loop(node)
  local body = layout_seq(node.body)
  local hdr = hexagon(node.cond or "")
  local yes, no = node.yes or "", node.no or ""
  local ox = math.max(3, width(yes) + 3)
  local cx = ox + math.max(hdr.cx, body.cx)
  local hx, bx = cx - hdr.cx, cx - body.cx
  local out = block(1, 1)
  put(out, cx, 0, C.merge)
  put(out, 0, 0, C.tl)
  hline(out, 1, cx - 2, 0, C.h)
  put(out, cx - 1, 0, C.right)
  put(out, cx, 1, C.down)
  local y = 2
  blit(out, body, bx, y)
  y = y + body.h
  put(out, cx, y, C.v)
  put(out, cx, y + 1, C.down)
  y = y + 2
  blit(out, hdr, hx, y)
  local hm = y + hdr.mid
  vline(out, 0, 1, hm - 1, C.v)
  put(out, 0, hm, C.bl)
  hline(out, 1, hx - 1, hm, C.h)
  if yes ~= "" then
    text(out, 1, hm, yes)
  end
  y = y + hdr.h
  put(out, cx, y - 1, C.td)
  if no ~= "" then
    put(out, cx, y, C.v)
    text(out, cx + 2, y, no)
    y = y + 1
  end
  out.h, out.cx = y, cx
  return out
end

local function partition(node)
  local body = layout_seq(node.body)
  local pad = 2
  local t = node.title ~= "" and (" " .. node.title .. " ") or ""
  local inner = math.max(body.w, width(t) + 2)
  local w = inner + pad * 2 + 2
  local cx = 1 + pad + body.cx
  local out = block(w, body.h + 2, cx)
  put(out, 0, 0, C.tl)
  hline(out, 1, w - 2, 0, C.h)
  put(out, w - 1, 0, C.tr)
  local tx = 2
  if tx <= cx and cx <= tx + width(t) then
    tx = cx + 2
  end
  text(out, tx, 0, t)
  if tx + width(t) >= w - 1 then
    put(out, tx + width(t), 0, C.h)
    put(out, tx + width(t) + 1, 0, C.tr)
    w = tx + width(t) + 2
  end
  put(out, cx, 0, C.down)
  blit(out, body, 1 + pad, 1)
  local by = body.h + 1
  vline(out, 0, 1, by - 1, C.v)
  vline(out, w - 1, 1, by - 1, C.v)
  put(out, 0, by, C.bl)
  hline(out, 1, w - 2, by, C.h)
  put(out, w - 1, by, C.br)
  if not body.term then
    put(out, cx, by, C.td)
  end
  out.term = body.term
  out.w, out.h = w, by + 1
  return out
end

local function layout_node(node)
  if node.kind == "action" then
    return action(node)
  elseif node.kind == "start" or node.kind == "stop" or node.kind == "end" then
    return terminal(node.kind)
  elseif node.kind == "if" then
    if #node.branches == 1 then
      table.insert(node.branches, { label = "", seq = {} }) -- implicit empty else
    end
    return branches(hexagon(node.cond), node.branches)
  elseif node.kind == "switch" then
    if #node.branches == 0 then
      return hexagon(node.cond)
    end
    return branches(hexagon(node.cond), node.branches)
  elseif node.kind == "fork" then
    return branches(nil, node.branches, true)
  elseif node.kind == "while" then
    return while_loop(node)
  elseif node.kind == "repeat" then
    return repeat_loop(node)
  elseif node.kind == "partition" then
    return partition(node)
  end
end

function layout_seq(seq)
  local items, label = {}, nil
  for _, node in ipairs(seq) do
    if node.kind == "label" then
      label = node.text
    else
      local b = layout_node(node)
      if b then
        table.insert(items, { b = b, label = label })
        label = nil
      end
    end
  end
  if #items == 0 then
    local b = passthrough()
    if label then
      text(b, 2, 0, label)
    end
    return b
  end
  local cx = 0
  for _, it in ipairs(items) do
    cx = math.max(cx, it.b.cx)
  end
  local out = block(1, 1, cx)
  local y = 0
  for k, it in ipairs(items) do
    local prev = items[k - 1]
    if prev or it.label then
      if prev and prev.b.term then
        y = y + 1 -- unreachable after stop/end: no arrow
      else
        put(out, cx, y, C.v)
        if it.label then
          text(out, cx + 2, y, it.label)
        end
        put(out, cx, y + 1, C.down)
        y = y + 2
      end
    end
    blit(out, it.b, cx - it.b.cx, y)
    y = y + it.b.h
  end
  if label and not items[#items].b.term then
    put(out, cx, y, C.v)
    text(out, cx + 2, y, label)
    y = y + 1
  end
  out.h = y
  out.cx = cx
  out.term = items[#items].b.term
  return out
end

--- Render an activity diagram body as text.
--- @param lines string[] diagram body (without @startuml/@enduml)
--- @param opts? { ascii?: boolean }
--- @return string[]|nil lines, nil when the body uses the legacy `(*)` syntax
function M.render(lines, opts)
  opts = opts or {}
  for _, l in ipairs(lines) do
    if l:find("(*)", 1, true) then
      return nil -- legacy activity syntax: PlantUML's own text output handles it
    end
  end
  C = opts.ascii and ASCII or UNI
  local root, title = M.parse(lines)
  local b = layout_seq(root)
  local out = {}
  if title then
    local pad = math.max(0, math.floor((b.w - width(title)) / 2))
    table.insert(out, string.rep(" ", pad) .. title)
    table.insert(out, "")
  end
  for _, l in ipairs(to_lines(b)) do
    table.insert(out, "  " .. l)
  end
  return out
end

return M
