-- puml script: an indentation-based language that compiles to PlantUML sequence
-- and activity diagrams. See docs/script.md.
--
--   local out, errs = require("puml.script").compile(lines)
--   -- out: PlantUML lines (nil when there are errors), errs: { { line = n, msg = "..." } }
local M = {}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- `#` starts a comment at the start of a line, or after whitespace when followed by a
-- space (so colours like `#LightBlue` are kept). `plantuml:` lines are kept verbatim.
local function strip_comment(l)
  local t = trim(l)
  if t:sub(1, 1) == "#" then
    return ""
  end
  if t:match("^plantuml:") then
    return l
  end
  return (l:gsub("%s+#%s.*$", ""):gsub("%s+#$", ""))
end

---------------------------------------------------------------------------
-- indentation tree
---------------------------------------------------------------------------

--- Parse lines into a tree of { text, line, block = bool, children = {} }.
local function tree(lines, errs)
  local root = { children = {}, indent = -1 }
  local stack = { root }
  local pending = {} -- full-line comments, kept (as PlantUML comments) before the next statement
  for n, raw in ipairs(lines) do
    local full = trim(raw)
    local expanded = raw:gsub("\t", "    ")
    local ind = #expanded:match("^ *")
    -- under `note …:` / `legend …:` everything indented is text, taken as it is
    local top = stack[#stack]
    while top ~= root and ind <= top.indent and full ~= "" do
      table.remove(stack)
      top = stack[#stack]
    end
    if top.raw and full ~= "" then
      top.text_base = top.text_base or ind
      table.insert(top.children, { text = string.rep(" ", math.max(0, ind - top.text_base)) .. full, line = n, children = {} })
      goto continue
    end
    if full:sub(1, 1) == "#" then
      table.insert(pending, trim(full:sub(2)))
    end
    local l = strip_comment(expanded)
    if trim(l) ~= "" then
      local indent = #l:match("^ *")
      local text = trim(l)
      while indent <= stack[#stack].indent do
        table.remove(stack)
      end
      local parent = stack[#stack]
      if parent ~= root and not parent.block then
        table.insert(errs, { line = n, msg = "unexpected indentation (the line above doesn't end with `:`)" })
      end
      -- a sibling must line up with an earlier sibling, not land between two levels
      if parent.child_indent and indent ~= parent.child_indent then
        table.insert(errs, { line = n, msg = "inconsistent indentation" })
      end
      parent.child_indent = parent.child_indent or indent
      local node = { text = text, line = n, indent = indent, children = {}, comments = pending }
      pending = {}
      node.block = text:sub(-1) == ":" and not text:match("^plantuml:")
      if node.block then
        node.head = trim(text:sub(1, -2))
        node.raw = node.head:match("^note%f[^%w_]") ~= nil or node.head:match("^legend%f[^%w_]") ~= nil
      end
      table.insert(parent.children, node)
      table.insert(stack, node)
    end
    ::continue::
  end
  root.trailing = pending
  return root
end

local function put_comments(n, put)
  for _, c in ipairs(n.comments or {}) do
    put(c ~= "" and ("' " .. c) or "'")
  end
end

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------

local DECL = { participant = true, actor = true, boundary = true, control = true, entity = true,
  database = true, collections = true, queue = true }
local PASS_SEQ = { "^return%f[^%w_]", "^activate%s", "^deactivate%s", "^create%s", "^destroy%s", "^autonumber%f[^%w_]", "^hide%s", "^skinparam%s" }
local PASS_ANY = { "^title%s", "^header%s", "^footer%s", "^caption%s", "^skinparam%s", "^!" }

local NAME = '"[^"]+"' -- quoted names are matched separately from bare ones

--- Split `A -> B++: text` into parts, nil when the line isn't a message.
local function message(t)
  local function name_at(s, i)
    local q = s:match("^" .. NAME, i)
    if q then
      return q, i + #q
    end
    local w = s:match("^[%w_%.]+", i)
    if w then
      return w, i + #w
    end
  end
  local a, i = name_at(t, 1)
  if not a then
    return nil
  end
  local sp = t:match("^%s*", i)
  i = i + #sp
  local arrow = t:match("^<?%-+>*[xo]?", i) or t:match("^<?%.+>*", i)
  if not arrow or not arrow:find("[<>]") then
    return nil
  end
  i = i + #arrow
  i = i + #t:match("^%s*", i)
  local b, j = name_at(t, i)
  if not b then
    return nil
  end
  local act = t:match("^%+%+", j) or t:match("^%-%-", j) or ""
  j = j + #act
  local rest = t:sub(j)
  local label = rest:match("^%s*:%s*(.*)$")
  if not label and trim(rest) ~= "" then
    return nil
  end
  return { from = a, arrow = arrow, to = b, act = act, label = label }
end

--- `COND [LABEL] -[#red]-> TEXT` / `COND [LABEL] -> TEXT` -> `COND [LABEL]` and the
--- arrow back to the loop start (PlantUML syntax), or nil
local function split_arrow(s)
  local c, a = s:match("^(.-)%s+(%-%[[^%]]*%]%->.*)$")
  if not c then
    c, a = s:match("^(.-)%s+(%->%s.*)$")
  end
  if not c then
    c, a = s:match("^(.-)%s+(%->)$")
  end
  if c then
    return trim(c), trim(a)
  end
  return s, nil
end

--- `COND [LABEL] [EXIT]` -> cond, label, exit (labels nil when not given; `[]` = none)
local function cond_labels(s)
  local c, l, x = s:match("^(.-)%s*%[([^%]]*)%]%s*%[([^%]]*)%]$")
  if c then
    return trim(c), trim(l), trim(x)
  end
  c, l = s:match("^(.-)%s*%[([^%]]*)%]$")
  if c then
    return trim(c), trim(l), nil
  end
  return trim(s), nil, nil
end

--- `COND [LABEL]` -> cond, label
local function cond_label(s)
  local c, l = s:match("^(.-)%s*%[(.-)%]$")
  if c then
    return trim(c), trim(l)
  end
  return trim(s), nil
end

local function kw(head, word)
  return head == word or head:sub(1, #word + 1) == word .. " "
end

local function rest_of(head, word)
  return trim(head:sub(#word + 1))
end

---------------------------------------------------------------------------
-- sequence
---------------------------------------------------------------------------

local function seq_notes(t)
  -- note: T / note left: T / note right: T (on the last message)
  local side, txt = t:match("^note%s*(%a*)%s*:%s*(.*)$")
  if side and (side == "" or side == "left" or side == "right") then
    return ("note %s: %s"):format(side == "" and "right" or side, txt)
  end
  if t:match("^note%s+over%s") or t:match("^note%s+left%s+of%s") or t:match("^note%s+right%s+of%s") then
    return t
  end
  -- note A: T -> note right of A: T
  local who, txt2 = t:match("^note%s+([^:]+):%s*(.*)$")
  if who then
    return ("note right of %s: %s"):format(trim(who), txt2)
  end
end

local function emit_seq(nodes, out, depth, errs)
  local pad = string.rep("  ", depth)
  local function put(s)
    table.insert(out, pad .. s)
  end
  local i = 1
  while i <= #nodes do
    local n = nodes[i]
    local t, h = n.text, n.head
    put_comments(n, put)
    local function body(d)
      emit_seq(n.children, out, d or depth + 1, errs)
    end
    if t == "pass" then
      -- an intentionally empty block
    elseif n.block then
      if #n.children == 0 and not kw(h, "note") and not kw(h, "legend") then
        table.insert(errs, { line = n.line, msg = "`" .. t .. "` opens a block but nothing is indented under it (use `pass` for an empty one)" })
      end
      if kw(h, "if") then
        put("alt " .. (cond_label(rest_of(h, "if"))))
        body()
        while nodes[i + 1] and nodes[i + 1].block and (kw(nodes[i + 1].head, "elif") or kw(nodes[i + 1].head, "else")) do
          i = i + 1
          local m = nodes[i]
          put_comments(m, put)
          local w = kw(m.head, "elif") and "elif" or "else"
          local c = cond_label(rest_of(m.head, w))
          put(c ~= "" and ("else " .. c) or "else")
          emit_seq(m.children, out, depth + 1, errs)
          if w == "else" then
            break
          end
        end
        put("end")
      elseif kw(h, "elif") or kw(h, "else") then
        table.insert(errs, { line = n.line, msg = "`" .. h:match("^%a+") .. "` without `if` right above it" })
      elseif kw(h, "while") or kw(h, "loop") or kw(h, "for") then
        put("loop " .. (cond_labels(rest_of(h, h:match("^%a+")))))
        body()
        put("end")
      elseif h == "do" then
        local nxt = nodes[i + 1]
        if nxt and not nxt.block and kw(nxt.text, "while") then
          local cl, arrow = split_arrow(rest_of(nxt.text, "while"))
          if arrow then
            table.insert(errs, { line = nxt.line, msg = "an arrow style on `while` only works in activity diagrams" })
          end
          put("loop " .. (cond_labels(cl)))
          body()
          put_comments(nxt, put)
          put("end")
          i = i + 1
        else
          table.insert(errs, { line = n.line, msg = "`do:` needs `while CONDITION` after its block, at the same indentation" })
        end
      elseif kw(h, "opt") or kw(h, "break") or kw(h, "critical") or kw(h, "group") then
        put(h)
        body()
        put("end")
      elseif h == "parallel" then
        local first = true
        for _, b in ipairs(n.children) do
          put_comments(b, put)
          if b.block and kw(b.head, "branch") then
            put((first and "par" or "else") .. (rest_of(b.head, "branch") ~= "" and (" " .. rest_of(b.head, "branch")) or ""))
            emit_seq(b.children, out, depth + 1, errs)
            first = false
          else
            table.insert(errs, { line = b.line, msg = "only `branch:` blocks go inside `parallel:`" })
          end
        end
        put("end")
      elseif kw(h, "box") then
        put(h)
        for _, c in ipairs(n.children) do
          local w = c.text:match("^(%a+)")
          if c.block or not DECL[w or ""] then
            table.insert(errs, { line = c.line, msg = "a box holds participant declarations only" })
          end
        end
        body()
        put("end box")
      elseif kw(h, "legend") then
        put(h)
        for _, c in ipairs(n.children) do
          put("  " .. c.text)
        end
        put("endlegend")
      elseif kw(h, "note") then
        local head = seq_notes(h .. ": x")
        if not head then
          table.insert(errs, { line = n.line, msg = "unknown note form: " .. t })
        else
          put((head:gsub(":%s*x$", "")))
          for _, c in ipairs(n.children) do
            put("  " .. c.text)
          end
          put("end note")
        end
      else
        table.insert(errs, { line = n.line, msg = "unknown block in a sequence diagram: `" .. t .. "`" })
      end
    else
      if #n.children > 0 then
        -- reported by tree() already
      end
      local msg = message(t)
      local w = t:match("^(%a+)")
      if msg then
        local arrow = msg.from .. " " .. msg.arrow .. " " .. msg.to .. (msg.act ~= "" and (" " .. msg.act) or "")
        put(arrow .. (msg.label and (" : " .. msg.label) or ""))
      elseif DECL[w or ""] then
        -- actor NAME ["Label"] [#color]
        local name, label, tail = t:match('^%a+%s+([%w_%.]+)%s+(' .. NAME .. ')%s*(.*)$')
        if name then
          put(("%s %s as %s%s"):format(w, label, name, tail ~= "" and (" " .. tail) or ""))
        else
          put(t)
        end
      elseif t:match("^plantuml:") then
        put(trim(t:sub(10)))
      elseif t:match("^note[%s:]") then
        local s = seq_notes(t)
        if s then
          put(s)
        else
          table.insert(errs, { line = n.line, msg = "unknown note form: " .. t })
        end
      elseif t:match("^ref%s") then
        put("ref over " .. (t:gsub("^ref%s+", "")))
      elseif t:match("^section%s") then
        put("== " .. rest_of(t, "section") .. " ==")
      elseif t == "delay" or t:match("^delay%s") then
        put("..." .. rest_of(t, "delay") .. "...")
      elseif t == "space" then
        put("|||")
      elseif t:match("^while%s") then
        table.insert(errs, { line = n.line, msg = "`while` without `:` must follow a `do:` block" })
      else
        local ok = false
        for _, p in ipairs(PASS_SEQ) do
          ok = ok or t:match(p) ~= nil
        end
        for _, p in ipairs(PASS_ANY) do
          ok = ok or t:match(p) ~= nil
        end
        if ok then
          put(t)
        else
          table.insert(errs, { line = n.line, msg = "not a sequence statement: `" .. t .. "` (a message is `A -> B: text`)" })
        end
      end
    end
    i = i + 1
  end
end

---------------------------------------------------------------------------
-- activity
---------------------------------------------------------------------------

local TERMINAL = { stop = true, ["end"] = true, kill = true, detach = true }

local function emit_act(nodes, out, depth, errs)
  local pad = string.rep("  ", depth)
  local function put(s)
    table.insert(out, pad .. s)
  end
  local i = 1
  while i <= #nodes do
    local n = nodes[i]
    local t, h = n.text, n.head
    put_comments(n, put)
    local function body()
      emit_act(n.children, out, depth + 1, errs)
    end
    if t == "pass" then
      -- an intentionally empty block
    elseif n.block then
      if #n.children == 0 and not kw(h, "note") and not kw(h, "legend") then
        table.insert(errs, { line = n.line, msg = "`" .. t .. "` opens a block but nothing is indented under it (use `pass` for an empty one)" })
      end
      if kw(h, "if") then
        local c, l = cond_label(rest_of(h, "if"))
        put(("if (%s) then (%s)"):format(c, l or "yes"))
        body()
        while nodes[i + 1] and nodes[i + 1].block and (kw(nodes[i + 1].head, "elif") or kw(nodes[i + 1].head, "else")) do
          i = i + 1
          local m = nodes[i]
          put_comments(m, put)
          if kw(m.head, "elif") then
            local c2, l2 = cond_label(rest_of(m.head, "elif"))
            put(("elseif (%s) then (%s)"):format(c2, l2 or "yes"))
          else
            local _, l3 = cond_label(rest_of(m.head, "else"))
            l3 = l3 or (rest_of(m.head, "else") ~= "" and rest_of(m.head, "else") or nil)
            put(("else (%s)"):format(l3 or "no"))
          end
          emit_act(m.children, out, depth + 1, errs)
          if kw(m.head, "else") then
            break
          end
        end
        put("endif")
      elseif kw(h, "elif") or kw(h, "else") then
        table.insert(errs, { line = n.line, msg = "`" .. h:match("^%a+") .. "` without `if` right above it" })
      elseif kw(h, "while") then
        local cl, arrow = split_arrow(rest_of(h, "while"))
        if arrow then
          table.insert(errs, { line = n.line, msg = "an arrow style works on the `while` closing a `do:` block, not on `while …:`" })
        end
        local c, l, x = cond_labels(cl)
        put(("while (%s)%s"):format(c, l == "" and "" or (" is (" .. (l or "yes") .. ")")))
        body()
        put(x == "" and "endwhile" or ("endwhile (" .. (x or "no") .. ")"))
      elseif h == "do" then
        local nxt = nodes[i + 1]
        if nxt and not nxt.block and kw(nxt.text, "while") then
          local cl, arrow = split_arrow(rest_of(nxt.text, "while"))
          local c, l, x = cond_labels(cl)
          put("repeat")
          body()
          put_comments(nxt, put)
          put(("repeat while (%s)%s%s%s"):format(c, l == "" and "" or (" is (" .. (l or "yes") .. ")"),
            (x and x ~= "") and (" not (" .. x .. ")") or "", arrow and (" " .. arrow) or ""))
          i = i + 1
        else
          table.insert(errs, { line = n.line, msg = "`do:` needs `while CONDITION` after its block, at the same indentation" })
        end
      elseif kw(h, "switch") then
        put(("switch (%s)"):format(rest_of(h, "switch")))
        for _, c in ipairs(n.children) do
          put_comments(c, put)
          if c.block and kw(c.head, "case") then
            put(("case (%s)"):format(rest_of(c.head, "case")))
            emit_act(c.children, out, depth + 1, errs)
          else
            table.insert(errs, { line = c.line, msg = "only `case VALUE:` blocks go inside `switch:`" })
          end
        end
        put("endswitch")
      elseif h == "parallel" or h == "split" then
        local open, again, close = "fork", "fork again", "end fork"
        if h == "split" then
          open, again, close = "split", "split again", "end split"
        end
        local first = true
        for _, b in ipairs(n.children) do
          put_comments(b, put)
          if b.block and kw(b.head, "branch") then
            put(first and open or again)
            emit_act(b.children, out, depth + 1, errs)
            first = false
          else
            table.insert(errs, { line = b.line, msg = "only `branch:` blocks go inside `" .. h .. ":`" })
          end
        end
        put(close)
      elseif kw(h, "partition") then
        put(("partition %s {"):format(rest_of(h, "partition")))
        body()
        put("}")
      elseif kw(h, "group") then
        put(h)
        body()
        put("end group")
      elseif kw(h, "legend") then
        put(h)
        for _, c in ipairs(n.children) do
          put("  " .. c.text)
        end
        put("endlegend")
      elseif kw(h, "note") then
        local side = rest_of(h, "note")
        put("note " .. (side ~= "" and side or "right"))
        for _, c in ipairs(n.children) do
          put("  " .. c.text)
        end
        put("end note")
      else
        table.insert(errs, { line = n.line, msg = "unknown block in an activity diagram: `" .. t
          .. "` (an action doesn't end with `:`)" })
      end
    else
      local side, txt = t:match("^note%s*(%a*)%s*:%s*(.*)$")
      if TERMINAL[t] or t == "start" then
        put(t)
      elseif t:match("^lane%s") then
        put("|" .. rest_of(t, "lane") .. "|")
      elseif t:match("^%->") then
        put("-> " .. trim(t:sub(3)):gsub(";$", "") .. ";")
      elseif side and (side == "" or side == "left" or side == "right") then
        put(("note %s: %s"):format(side == "" and "right" or side, txt))
      elseif t:match("^plantuml:") then
        put(trim(t:sub(10)))
      elseif t:match("^while%s") then
        table.insert(errs, { line = n.line, msg = "`while` without `:` must follow a `do:` block" })
      else
        local pass = false
        for _, p in ipairs(PASS_ANY) do
          pass = pass or t:match(p) ~= nil
        end
        if pass then
          put(t)
        else
          put(":" .. t:gsub(";+$", "") .. ";")
        end
      end
    end
    i = i + 1
  end
end

--- Does the (top-level) flow already start / end?
local function has_start(nodes)
  for _, n in ipairs(nodes) do
    if n.text == "start" then
      return true
    end
  end
end

--- The last statement of the flow, skipping trailing notes, legends, titles, passthroughs.
local function ends(nodes)
  for k = #nodes, 1, -1 do
    local n = nodes[k]
    local t = n.text
    local meta = t:match("^plantuml:") or t:match("^note[%s:]") or t:match("^legend[%s:]") or t:match("^title%s")
      or t:match("^header%s") or t:match("^footer%s") or t:match("^caption%s") or t:match("^skinparam%s")
    if not meta then
      return not n.block and TERMINAL[t] ~= nil
    end
  end
  return false
end

---------------------------------------------------------------------------
-- entry point
---------------------------------------------------------------------------

local function guess(nodes)
  local function walk(list)
    for _, n in ipairs(list) do
      if (not n.block and message(n.text)) or walk(n.children) then
        return true
      end
    end
  end
  return walk(nodes) and "sequence" or "activity"
end

--- Compile script lines to PlantUML lines.
--- @return string[]|nil out, table[] errors { line, msg }, string type
function M.compile(lines)
  local errs = {}
  local root = tree(lines, errs)
  local nodes = root.children
  local typ, title, header_comments
  local first = nodes[1]
  if first then
    local w, rest = first.text:match("^(%a+)%s*:?%s*(.*)$")
    if (w == "sequence" or w == "activity") and (first.text == w or first.text:match("^%a+%s*:")) then
      typ, title = w, rest ~= "" and rest or nil
      if #first.children > 0 then
        table.insert(errs, { line = first.line, msg = "the header line takes no indented block" })
      end
      table.remove(nodes, 1)
      header_comments = first.comments
    end
  end
  typ = typ or guess(nodes)
  local out = { "@startuml" }
  for _, c in ipairs(header_comments or {}) do
    table.insert(out, c ~= "" and ("' " .. c) or "'")
  end
  if title then
    table.insert(out, "title " .. title)
  end
  if typ == "sequence" then
    emit_seq(nodes, out, 0, errs)
  else
    -- `start` after the leading lanes / settings, unless the script has one
    local body = {}
    emit_act(nodes, body, 0, errs)
    -- `start` and `stop` are added together, only for a script that has no `start`:
    -- one that does manages its own ending
    local auto = not has_start(nodes)
    if auto then
      local k = 1
      while body[k] and (body[k]:match("^|") or body[k]:match("^'") or body[k]:match("^title ") or body[k]:match("^header ")
        or body[k]:match("^footer ") or body[k]:match("^caption ") or body[k]:match("^skinparam ") or body[k]:match("^!")) do
        k = k + 1
      end
      table.insert(body, k, "start")
    end
    vim.list_extend(out, body)
    if auto and not ends(nodes) then
      table.insert(out, "stop")
    end
  end
  for _, c in ipairs(root.trailing or {}) do
    table.insert(out, c ~= "" and ("' " .. c) or "'")
  end
  table.insert(out, "@enduml")
  table.sort(errs, function(a, b)
    return a.line < b.line
  end)
  if #errs > 0 then
    return nil, errs, typ
  end
  return out, errs, typ
end

--- Errors as "line: message" strings.
function M.format_errors(errs, name)
  return vim.tbl_map(function(e)
    return ("%s%d: %s"):format(name and (name .. ":") or "", e.line, e.msg)
  end, errs)
end

---------------------------------------------------------------------------
-- PlantUML -> script
---------------------------------------------------------------------------

-- Would this activity action text be read as something else in a script? Then it is
-- passed through instead. (Only what the activity compiler treats specially counts:
-- `:create order;` is a plain action.)
local function looks_like_keyword(t)
  local w = t:match("^(%a+)") or ""
  return t:sub(-1) == ":" or t:match("^%->") or t:match("^#") or t:match("^plantuml:") or t:match("^!")
    or ({ start = 1, stop = 1, ["end"] = 1, kill = 1, detach = 1, pass = 1 })[t]
    or (w == "lane" and t:match("^lane%s"))
    or t:match("^note%s*%a*%s*:")
    or (({ title = 1, header = 1, footer = 1, caption = 1, skinparam = 1, ["while"] = 1 })[w] and t:match("^%a+%s"))
    or t:match("%s#%s") or t:match("%s#$") -- would be cut as a comment
end

--- Script labels of a loop: `[LABEL] [EXIT]`, leaving out what the compiler adds by
--- itself (`is (yes)`, and `endwhile (no)` when `exit_default` is "no"); `[]` = no label.
--- is / exit: the label, or false when PlantUML has none.
local function loop_labels(is, exit, exit_default)
  local l = is
  if is == false then
    l = "" -- no `is (…)`: an explicit empty label
  end
  local x
  if exit == false then
    -- no exit label: only spelled out when the compiler would add one (`endwhile (no)`)
    x = exit_default and "" or nil
  elseif exit ~= exit_default then
    x = exit
  end
  if x ~= nil then
    return (" [%s] [%s]"):format(l == nil and "yes" or l, x)
  end
  if l ~= "yes" then
    return (" [%s]"):format(l)
  end
  return ""
end

--- `X (label)` helpers
local function paren(s)
  return s and trim(s):match("^%((.*)%)$") or (s and trim(s)) or nil
end

--- Convert PlantUML lines (one sequence or activity diagram) to script lines.
--- @return string[]|nil out, table[] notes { line, msg } (lines passed through as `plantuml:`), string|nil error
function M.decompile(lines, typ)
  local notes = {}
  local body, diagrams, done = {}, 0, false
  for n, l in ipairs(lines) do
    local t = trim(l)
    if t:match("^@start") then
      diagrams = diagrams + 1
      if diagrams == 1 then
        body = {}
      end
    elseif t:match("^@end") then
      done = true
    elseif not done and not t:match(M.MARKER_PATTERN) then
      table.insert(body, { text = t, line = n })
    end
  end
  if diagrams > 1 then
    table.insert(notes, { line = 1, msg = ("only the first of %d diagrams was converted"):format(diagrams) })
  end
  if not typ then
    local texts = vim.tbl_map(function(b)
      return b.text
    end, body)
    for _, t in ipairs(texts) do
      if t:find("(*)", 1, true) then
        return nil, notes, "the old `(*) -->` activity syntax can't be converted; only the current one"
      end
    end
    typ = require("puml.parse").detect(texts, "uml")
  end
  if typ ~= "sequence" and typ ~= "activity" then
    return nil, notes, "only sequence and activity diagrams can be converted (this is " .. typ .. ")"
  end
  local out = {}
  local depth = 0
  local stack = {} -- { kind, base }
  local title
  local function put(s, d)
    table.insert(out, string.rep("    ", d or depth) .. s)
  end
  local function pass_through(b, why)
    put("plantuml: " .. b.text)
    table.insert(notes, { line = b.line, msg = why or "kept as PlantUML" })
  end
  local function open(kind, line, extra)
    put(line)
    table.insert(stack, { kind = kind, base = depth, started = false })
    depth = depth + 1 + (extra or 0)
  end
  local function top(kind)
    local e = stack[#stack]
    return e and (not kind or e.kind == kind) and e or nil
  end
  -- the block opened last has nothing in it yet (blank lines don't count)
  local function empty_block()
    for k = #out, 1, -1 do
      if trim(out[k]) ~= "" then
        return out[k]:match(":$") ~= nil and #out[k]:match("^ *") < depth * 4
      end
    end
  end
  local function close(kind)
    local e = top(kind)
    if not e then
      return false
    end
    if empty_block() then
      put("pass")
    end
    table.remove(stack)
    depth = e.base
    return true
  end
  local function mid(line, inner)
    local e = stack[#stack]
    if empty_block() then
      put("pass")
    end
    put(line, e.base + (inner and 1 or 0))
    depth = e.base + 1 + (inner and 1 or 0)
  end

  local i = 1
  local seen = false -- a statement (not a comment / blank line) was converted
  while i <= #body do
    local b = body[i]
    local t = b.text
    local ll = t:lower()
    if t ~= "" and t:sub(1, 1) ~= "'" and not ll:match("^title%s") then
      seen = true
    end
    if t == "" then
      if out[#out] ~= "" and #out > 0 then
        table.insert(out, "")
      end
    elseif t:sub(1, 1) ~= "'" and (t:match("%s#%s") or t:match("%s#$")) then
      pass_through(b, "kept as PlantUML: ` # ` would start a comment in a script")
    elseif t:sub(1, 1) == "'" then
      put("# " .. trim(t:sub(2)))
    elseif ll:match("^title%s") and not title and not seen then
      title = trim(t:sub(6)) -- into the header line
    elseif ll:match("^legend") then
      put(t .. ":")
      i = i + 1
      while body[i] and not body[i].text:lower():match("^end%s*legend") do
        put(body[i].text, depth + 1)
        i = i + 1
      end
    elseif ll:match("^note") and not t:find(":", 1, true) and not ll:match("^note.*\"") then
      -- multi-line note: `note over A` ... `end note`
      local head = t
      if typ == "activity" then
        head = (t:gsub("^note%s+right$", "note")):gsub("^note%s+left$", "note left")
      end
      put(head .. ":")
      i = i + 1
      while body[i] and not body[i].text:lower():match("^end%s*note") do
        put(body[i].text, depth + 1)
        i = i + 1
      end
    elseif typ == "sequence" then
      local w = ll:match("^(%a+)") or ""
      local msg = (function()
        -- `A -> B ++ : text`
        local a, rest = t:match('^("[^"]+")%s*(.*)$')
        if not a then
          a, rest = t:match("^([%w_%.]+)%s*(.*)$")
        end
        if not a then
          return nil
        end
        local arrow, rest2 = rest:match("^(<?%-+>*[xo]?)%s*(.*)$")
        if not arrow or not arrow:find("[<>]") then
          return nil
        end
        local bq, rest3 = rest2:match('^("[^"]+")%s*(.*)$')
        if not bq then
          bq, rest3 = rest2:match("^([%w_%.]+)%s*(.*)$")
        end
        if not bq then
          return nil
        end
        local act, rest4 = rest3:match("^(%+%+)%s*(.*)$")
        if not act then
          act, rest4 = rest3:match("^(%-%-)%s*(.*)$")
        end
        rest4 = rest4 or rest3
        local label = rest4:match("^:%s*(.*)$")
        if not label and rest4 ~= "" then
          return nil
        end
        return a .. " " .. arrow .. " " .. bq .. (act or "") .. (label and (": " .. label) or "")
      end)()
      if msg then
        put(msg)
      elseif DECL[w] then
        local label, name, tail = t:match('^%a+%s+("[^"]+")%s+as%s+([%w_%.]+)%s*(.*)$')
        if label then
          put(("%s %s %s%s"):format(w, name, label, tail ~= "" and (" " .. tail) or ""))
        else
          put(t)
        end
      elseif w == "box" then
        open("box", t .. ":")
      elseif ll:match("^end%s*box") then
        close("box")
      elseif w == "alt" then
        open("alt", "if " .. trim(t:sub(4)) .. ":")
      elseif w == "else" and top("alt") then
        local c = trim(t:sub(5))
        mid(c ~= "" and ("elif " .. c .. ":") or "else:")
      elseif w == "par" then
        local lbl = trim(t:sub(4))
        open("par", "parallel:", 1)
        put(lbl ~= "" and ("branch " .. lbl .. ":") or "branch:", depth - 1)
      elseif w == "else" and top("par") then
        local lbl = trim(t:sub(5))
        mid(lbl ~= "" and ("branch " .. lbl .. ":") or "branch:", true)
      elseif w == "loop" or w == "opt" or w == "break" or w == "critical" or w == "group" then
        open(w, t .. ":")
      elseif ll == "end" or ll:match("^end%s+group") then
        if not close() then
          pass_through(b, "`end` without a block")
        end
      elseif ll:match("^ref%s+over%s") and t:find(":", 1, true) then
        put("ref " .. trim(t:sub(9)))
      elseif t:match("^==.*==$") then
        put("section " .. trim(t:sub(3, -3)))
      elseif t:match("^%.%.%..*%.%.%.$") then
        local d = trim(t:sub(4, -4))
        put(d ~= "" and ("delay " .. d) or "delay")
      elseif t == "..." then
        put("delay")
      elseif t == "|||" then
        put("space")
      elseif ll:match("^note") then
        put(t)
      else
        local ok = false
        for _, p in ipairs(PASS_SEQ) do
          ok = ok or ll:match(p) ~= nil
        end
        for _, p in ipairs(PASS_ANY) do
          ok = ok or ll:match(p) ~= nil
        end
        if ok then
          put(t)
        else
          pass_through(b)
        end
      end
    else -- activity
      local function cl(c, l, default)
        l = paren(l)
        return c .. ((l and l ~= "" and l ~= default) and (" [" .. l .. "]") or "")
      end
      if t:match("^:") then
        -- action, possibly over several lines
        local text = t:sub(2)
        while not text:match(";%s*$") and body[i + 1] do
          i = i + 1
          text = text .. "\\n" .. body[i].text
        end
        text = text:gsub(";%s*$", "")
        if looks_like_keyword(text) then
          put("plantuml: :" .. text .. ";")
        else
          put(text)
        end
      elseif t:match("^|.*|$") then
        put("lane " .. t:sub(2, -2))
      elseif ({ start = 1, stop = 1, ["end"] = 1, kill = 1, detach = 1 })[ll] then
        put(ll)
      elseif ll:match("^if%s*%(") then
        local c, l = t:match("^%a+%s*(%b())%s*then%s*(.*)$")
        if not c then
          c = t:match("^%a+%s*(%b())")
        end
        open("if", "if " .. cl(paren(c), l, "yes") .. ":")
      elseif ll:match("^elseif%s*%(") or ll:match("^else%s+if%s*%(") then
        local c, l = t:match("(%b())%s*then%s*(.*)$")
        mid("elif " .. cl(paren(c or t:match("%b()")), l, "yes") .. ":")
      elseif ll:match("^else") and top("if") then
        local l = paren(t:match("^%a+%s*(.*)$"))
        mid((l and l ~= "" and l ~= "no") and ("else [" .. l .. "]:") or "else:")
      elseif ll:match("^endif") or ll:match("^end%s+if") then
        close("if")
      elseif ll:match("^while%s*%(") then
        local c = t:match("^%a+%s*(%b())")
        local is = t:match("%)%s*is%s*(%b())")
        open("while", "while " .. paren(c) .. ":")
        -- the exit label is only known at `endwhile`: the line is rewritten then
        local e = stack[#stack]
        e.line, e.cond, e.is = #out, paren(c), is and paren(is) or false
      elseif ll:match("^endwhile") or ll:match("^end%s+while") then
        local e = top("while")
        if e then
          local exit = t:match("^%a+%s*%a*%s*(%b())")
          exit = exit and paren(exit) or false
          local labels = loop_labels(e.is, exit, "no")
          out[e.line] = string.rep("    ", e.base) .. "while " .. e.cond .. labels .. ":"
        end
        close("while")
      elseif ll == "repeat" then
        open("repeat", "do:")
      elseif ll:match("^repeat%s*while") then
        local rw, arrow = split_arrow(t)
        local c = rw:match("^%a+%s*%a+%s*(%b())") or rw:match("%b()")
        local is = rw:match("%)%s*is%s*(%b())")
        local nt = rw:match("%)%s*not%s*(%b())")
        local e = top("repeat")
        if e then
          close("repeat")
          put("while " .. (paren(c) or "") .. loop_labels(is and paren(is) or false, nt and paren(nt) or false, nil)
            .. (arrow and (" " .. arrow) or ""))
        else
          pass_through(b, "`repeat while` without `repeat`")
        end
      elseif ll:match("^switch%s*%(") then
        open("switch", "switch " .. paren(t:match("%b()")) .. ":", 1)
        depth = depth - 1
      elseif ll:match("^case%s*%(") and top("switch") then
        local e = top("switch")
        if e.started and empty_block() then
          put("pass")
        end
        put("case " .. paren(t:match("%b()")) .. ":", e.base + 1)
        e.started = true
        depth = e.base + 2
      elseif ll:match("^endswitch") then
        close("switch")
      elseif ll == "fork" or ll == "split" then
        open(ll, (ll == "fork" and "parallel:" or "split:"), 1)
        put("branch:", depth - 1)
      elseif (ll:match("^fork%s+again") and top("fork")) or (ll:match("^split%s+again") and top("split")) then
        mid("branch:", true)
      elseif ll:match("^end%s*fork") or ll:match("^end%s*merge") then
        close("fork")
      elseif ll:match("^end%s*split") then
        close("split")
      elseif ll:match("^partition%s") then
        open("partition", (t:gsub("%s*{%s*$", "")) .. ":")
        if not t:match("{%s*$") then
          table.insert(notes, { line = b.line, msg = "partition without `{`" })
        end
      elseif t == "}" and top("partition") then
        close("partition")
      elseif ll:match("^group%s") then
        open("group", t .. ":")
      elseif ll:match("^end%s*group") then
        close("group")
      elseif t:match("^%->") then
        put("-> " .. trim(t:sub(3)):gsub(";$", ""))
      elseif ll:match("^note%s+right%s*:") then
        put("note: " .. trim(t:match(":(.*)$")))
      elseif ll:match("^note%s+left%s*:") then
        put("note left: " .. trim(t:match(":(.*)$")))
      else
        local ok = false
        for _, p in ipairs(PASS_ANY) do
          ok = ok or ll:match(p) ~= nil
        end
        if ok then
          put(t)
        else
          pass_through(b)
        end
      end
    end
    i = i + 1
  end
  while #stack > 0 do
    table.insert(notes, { line = #lines, msg = "`" .. stack[#stack].kind .. "` was never closed" })
    close()
  end
  while out[#out] == "" do
    table.remove(out)
  end
  table.insert(out, 1, typ .. (title and (": " .. title) or ""))
  return out, notes
end

---------------------------------------------------------------------------
-- indentation (indentexpr for .pus buffers)
---------------------------------------------------------------------------

--- Indent for line `lnum` (default v:lnum). Indentation is the nesting, so this only
--- decides where indentation is implied and otherwise keeps it (-1), which makes `=`
--- safe: one level deeper right after a line ending in `:`; `elif`/`else` line up with
--- their `if`, `branch` / `case` sit one level under their `parallel`/`split` / `switch`.
function M.indent(lnum)
  lnum = lnum or vim.v.lnum
  local prev = vim.fn.prevnonblank(lnum - 1)
  if prev == 0 then
    return 0
  end
  local sw = vim.fn.shiftwidth()
  local cur_ind = vim.fn.indent(lnum)
  local cur = trim(vim.fn.getline(lnum))
  local w = cur:match("^(%a+)")
  -- the lines this one can belong to: walking up, each line less indented than all the
  -- lines below it (its enclosing blocks, innermost first)
  local function owners(pattern, extra)
    local found, min = {}, math.huge
    for l = lnum - 1, 1, -1 do
      local t = trim(vim.fn.getline(l))
      if t ~= "" and not t:match("^#") then
        local li = vim.fn.indent(l)
        if li < min then
          min = li
          if t:match(pattern) then
            table.insert(found, li + extra)
          end
        end
      end
    end
    return found
  end
  local function settle(cands, fallback)
    for _, c in ipairs(cands) do
      if c == cur_ind then
        return cur_ind -- already lines up with one of them: keep it (`=` must not move it)
      end
    end
    -- while typing: the innermost one that is less indented than where the line starts
    for _, c in ipairs(cands) do
      if c <= cur_ind then
        return c
      end
    end
    return cands[1] or fallback
  end
  if w == "elif" or w == "else" then
    local c = owners("^if[%s:]", 0)
    vim.list_extend(c, owners("^elif[%s:]", 0))
    table.sort(c, function(x, y)
      return x > y
    end)
    return settle(c, -1)
  elseif w == "branch" then
    local c = owners("^parallel%s*:", sw)
    vim.list_extend(c, owners("^split%s*:", sw))
    table.sort(c, function(x, y)
      return x > y
    end)
    return settle(c, -1)
  elseif w == "case" then
    return settle(owners("^switch[%s:]", sw), -1)
  end
  local ptext = trim(strip_comment(vim.fn.getline(prev)))
  if ptext:sub(-1) == ":" and not ptext:match("^plantuml:") then
    return vim.fn.indent(prev) + sw
  end
  return -1
end

---------------------------------------------------------------------------
-- editor integration
---------------------------------------------------------------------------

local ns = vim.api.nvim_create_namespace("puml_script")

-- first comment of a .puml written by :PumlScript; such a file may be overwritten
M.MARKER = "' generated from %s by :PumlScript; edit the script instead"
M.MARKER_PATTERN = "^' generated from .* by :PumlScript"

local function generated(path)
  local ok, head = pcall(vim.fn.readfile, path, "", 3)
  for _, l in ipairs(ok and head or {}) do
    if trim(l):match(M.MARKER_PATTERN) then
      return true
    end
  end
  return false
end

--- Compile script buffer `buf`: errors become diagnostics; on success the PlantUML goes
--- to FILE.puml next to FILE.pus (or a scratch buffer) and is shown with its preview.
--- opts.refresh: only update the PlantUML (and a preview that is already open).
function M.run(buf, opts)
  opts = opts or {}
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local out, errs = M.compile(vim.api.nvim_buf_get_lines(buf, 0, -1, false))
  vim.diagnostic.set(ns, buf, vim.tbl_map(function(e)
    return { lnum = e.line - 1, col = 0, message = e.msg, severity = vim.diagnostic.severity.ERROR, source = "puml script" }
  end, errs))
  if not out then
    require("puml.util").notify(#errs .. " error(s) in the script, see diagnostics", vim.log.levels.WARN)
    return nil, errs
  end
  local name = vim.api.nvim_buf_get_name(buf)
  local target = name ~= "" and (name:gsub("%.pus$", "") .. ".puml") or nil
  if target then
    table.insert(out, 2, M.MARKER:format(vim.fn.fnamemodify(name, ":t")))
    -- never replace a PlantUML file someone wrote by hand without asking (a file converted
    -- with :PumlScript is fine: the script was made from it)
    if vim.fn.filereadable(target) == 1 and not generated(target) and not vim.b[buf].puml_script_from then
      local ans = vim.fn.confirm(vim.fn.fnamemodify(target, ":~:.") .. " was not generated from this script. Overwrite it?", "&Yes\n&No", 2)
      if ans ~= 1 then
        return nil, {}
      end
      vim.b[buf].puml_script_from = target
    end
  end
  local tbuf = vim.b[buf].puml_script_target
  if not (tbuf and vim.api.nvim_buf_is_valid(tbuf)) then
    if target then
      tbuf = vim.fn.bufadd(target)
      vim.fn.bufload(tbuf)
    else
      tbuf = vim.api.nvim_create_buf(true, true)
    end
    vim.b[buf].puml_script_target = tbuf
    vim.bo[tbuf].filetype = "plantuml"
  end
  if vim.bo[tbuf].modified then
    local ans = vim.fn.confirm(vim.api.nvim_buf_get_name(tbuf) .. " has unsaved changes. Replace them?", "&Yes\n&No", 2)
    if ans ~= 1 then
      return nil, {}
    end
  end
  vim.api.nvim_buf_set_lines(tbuf, 0, -1, false, out)
  if target then
    vim.api.nvim_buf_call(tbuf, function()
      vim.cmd("silent noautocmd write!")
    end)
  end
  -- show it in a split next to the script, with the preview (not when only refreshing)
  local show = not opts.refresh
  -- what this script opened, closed again with the script (see close_companions)
  local c = M.companions[buf] or {}
  c.tbuf, c.scratch = tbuf, target == nil
  if vim.fn.bufwinid(tbuf) == -1 and show then
    local win = vim.api.nvim_get_current_win()
    vim.cmd("belowright split")
    vim.api.nvim_win_set_buf(0, tbuf)
    c.win = vim.api.nvim_get_current_win()
    vim.api.nvim_set_current_win(win)
  end
  local preview = require("puml.preview")
  require("puml").attach(tbuf)
  if vim.fn.bufwinid(tbuf) ~= -1 then
    if preview.is_open(tbuf) then
      preview.render(tbuf, { force = true })
    elseif show then
      preview.open(tbuf)
      c.preview = preview.is_open(tbuf) or nil
    end
  end
  M.companions[buf] = c
  return out, errs
end

---@type table<integer, {tbuf: integer, win: integer?, preview: boolean?, scratch: boolean}>
--- per script buffer: the PlantUML buffer, and the split/preview `run` opened for it
M.companions = {}

--- Close the split and preview that `run` opened for script `buf`. Windows the user
--- opened (or reused for another buffer) stay. The last window of a tab page is never
--- closed (that would close the tab).
--- While the PlantUML buffer has unsaved edits nothing is closed, and the record is kept
--- so that closing the script again later (after saving) still closes them; `forget`
--- drops it either way (the script buffer is gone, nothing will ask again).
function M.close_companions(buf, forget)
  local c = M.companions[buf]
  if not c then
    return
  end
  local tbuf = c.tbuf
  if not vim.api.nvim_buf_is_valid(tbuf) then
    M.companions[buf] = nil
    return
  end
  if vim.bo[tbuf].modified and not c.scratch then
    if forget then
      M.companions[buf] = nil
    end
    return
  end
  M.companions[buf] = nil
  local function closable(win)
    if not (win and vim.api.nvim_win_is_valid(win)) then
      return false
    end
    for _, w in ipairs(vim.api.nvim_tabpage_list_wins(vim.api.nvim_win_get_tabpage(win))) do
      if w ~= win and vim.api.nvim_win_get_config(w).relative == "" then
        return true
      end
    end
    return false
  end
  local preview = require("puml.preview")
  local ps = preview.state[tbuf]
  if c.preview and ps and preview.is_open(tbuf) and closable(ps.win) then
    preview.close(tbuf)
  end
  if c.win and closable(c.win) and vim.api.nvim_win_get_buf(c.win) == tbuf then
    pcall(vim.api.nvim_win_close, c.win, false)
  end
  -- a scratch PlantUML buffer holds nothing to keep: it is rebuilt by the next compile
  if c.scratch and #vim.fn.win_findbuf(tbuf) == 0 then
    pcall(vim.api.nvim_buf_delete, tbuf, { force = true })
  end
end

--- `:q` in script `buf`'s window would quit Neovim once its companions are closed, but
--- refuse to (E37/E162) because some other buffer has unsaved changes. QuitPre runs before
--- that check, so closing the companions then would leave the script alone on screen.
local function quit_would_fail(buf)
  if #vim.api.nvim_list_tabpages() > 1 then
    return false -- :q closes the tab (or a window), never quits
  end
  local c = M.companions[buf]
  local ours = {}
  if c then
    ours[c.win or -1] = true
    local ps = require("puml.preview").state[c.tbuf]
    if c.preview and ps and ps.win then
      ours[ps.win] = true
    end
  end
  local cur = vim.api.nvim_get_current_win()
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if w ~= cur and not ours[w] and vim.api.nvim_win_get_config(w).relative == "" then
      return false -- another window stays: :q only closes this one
    end
  end
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if b ~= buf and vim.api.nvim_buf_is_loaded(b) and vim.bo[b].modified and vim.bo[b].buftype ~= "nofile" then
      return true
    end
  end
  return false
end
M._quit_would_fail = quit_would_fail -- tests

--- `:PumlScript` in a PlantUML buffer: convert the diagram under the cursor to FILE.pus
--- next to FILE.puml (or a scratch buffer) and open it in a split.
function M.convert(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local util = require("puml.util")
  local d = util.current(buf)
  if not d then
    return util.notify("no PlantUML diagram under the cursor", vim.log.levels.WARN)
  end
  local lines = vim.api.nvim_buf_get_lines(buf, d.s - 1, d.e, false)
  local pus, notes, err = M.decompile(lines)
  if not pus then
    return util.notify(err, vim.log.levels.WARN)
  end
  local name = vim.api.nvim_buf_get_name(buf)
  local target = (name ~= "" and not util.is_markdown(buf)) and (name:gsub("%.[%w]+$", "") .. ".pus") or nil
  if target and vim.fn.filereadable(target) == 1 then
    -- don't silently overwrite a script that may hold edits
    target = target:gsub("%.pus$", "") .. "-" .. os.date("%H%M%S") .. ".pus"
  end
  local sbuf
  if target then
    vim.fn.writefile(pus, target)
    vim.cmd("belowright split " .. vim.fn.fnameescape(target))
    sbuf = vim.api.nvim_get_current_buf()
  else
    vim.cmd("belowright new")
    sbuf = vim.api.nvim_get_current_buf()
    vim.api.nvim_buf_set_lines(sbuf, 0, -1, false, pus)
    vim.bo[sbuf].filetype = "pumlscript"
  end
  vim.diagnostic.set(ns, sbuf, {})
  -- compiling this script back may replace the file it was made from
  if name ~= "" and not util.is_markdown(buf) then
    vim.b[sbuf].puml_script_from = name
  end
  if #notes > 0 then
    util.notify(("converted; %d line(s) kept as `plantuml:`"):format(#notes))
  end
  return pus, notes
end

--- `:PumlScript`: compile a script buffer, or convert a PlantUML buffer to a script.
function M.command(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  local ft = vim.bo[buf].filetype
  if ft == "plantuml" or require("puml.util").is_markdown(buf) then
    return M.convert(buf)
  end
  return M.run(buf)
end

--- For script buffers: recompile on save (opening the PlantUML + preview the first time,
--- refreshing it after that), and close what that opened once the script is closed.
function M.attach(buf)
  local group = vim.api.nvim_create_augroup("puml_script_" .. buf, { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    buffer = buf,
    callback = function()
      local t = vim.b[buf].puml_script_target
      M.run(buf, { refresh = t ~= nil and vim.api.nvim_buf_is_valid(t) and vim.fn.bufwinid(t) ~= -1 })
    end,
  })
  -- the script left its last window (:q, :bd, :e other): closing windows inside the
  -- autocmd isn't allowed, so do it right after, if the script is still not shown
  vim.api.nvim_create_autocmd("BufWinLeave", {
    group = group,
    buffer = buf,
    callback = function()
      vim.schedule(function()
        if not vim.api.nvim_buf_is_valid(buf) or #vim.fn.win_findbuf(buf) == 0 then
          M.close_companions(buf)
        end
      end)
    end,
  })
  -- `:q` in the script's only window: close the splits first, so that when they were
  -- the only other windows, the same `:q` quits Neovim (unless that quit would fail)
  vim.api.nvim_create_autocmd("QuitPre", {
    group = group,
    buffer = buf,
    callback = function()
      if not vim.bo[buf].modified and #vim.fn.win_findbuf(buf) == 1 and not quit_would_fail(buf) then
        M.close_companions(buf)
      end
    end,
  })
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = function()
      vim.schedule(function()
        M.close_companions(buf, true)
      end)
    end,
  })
end

return M
