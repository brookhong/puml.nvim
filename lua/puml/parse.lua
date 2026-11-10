-- Lightweight, best-effort parsing of PlantUML source: diagram type, declared names, blocks.
local M = {}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function set(list)
  local t = {}
  for _, v in ipairs(list) do
    t[v] = true
  end
  return t
end

-- Iterate over meaningful lines (trimmed), skipping comments.
local function each_line(lines)
  local i, in_comment = 0, false
  return function()
    while true do
      i = i + 1
      local raw = lines[i]
      if raw == nil then
        return nil
      end
      local l = trim(raw)
      if in_comment then
        if l:find("'/", 1, true) then
          in_comment = false
        end
      elseif l:sub(1, 2) == "/'" then
        if not l:find("'/", 3, true) then
          in_comment = true
        end
      elseif l ~= "" and l:sub(1, 1) ~= "'" then
        return i, l
      end
    end
  end
end

---------------------------------------------------------------------------
-- Diagram type detection
---------------------------------------------------------------------------

local seq_decl = set({ "participant", "boundary", "control", "entity", "collections", "queue" })
local seq_kw = set({ "activate", "deactivate", "autonumber", "loop", "alt", "opt", "par", "break", "critical", "return", "destroy", "create", "ref" })
local class_kw = set({ "class", "interface", "abstract", "enum", "annotation", "protocol", "struct", "exception" })
local comp_kw = set({ "component", "node", "cloud", "artifact", "folder", "frame", "storage", "port", "portin", "portout", "agent", "stack", "file" })
local act_kw = set({ "start", "stop", "endif", "endwhile", "detach", "kill", "fork", "repeat", "endswitch", "partition" })

M.types = { "sequence", "class", "activity", "usecase", "component", "state", "object" }

function M.detect(body, tag)
  tag = tag or "uml"
  if tag ~= "uml" then
    return tag -- mindmap, wbs, gantt, json, yaml, salt, ...
  end
  local s = { sequence = 0, class = 0, activity = 0, usecase = 0, component = 0, state = 0, object = 0 }
  for _, l in each_line(body) do
    local ll = l:lower()
    local w = ll:match("^([%a_]+)")
    if w then
      if seq_decl[w] then
        s.sequence = s.sequence + 3
      elseif seq_kw[w] then
        s.sequence = s.sequence + 2
      elseif w == "actor" then
        s.sequence = s.sequence + 1
        s.usecase = s.usecase + 1
      elseif w == "database" then
        s.sequence = s.sequence + 1
        s.component = s.component + 1
      elseif class_kw[w] then
        s.class = s.class + 3
      elseif comp_kw[w] then
        s.component = s.component + 3
      elseif w == "usecase" then
        s.usecase = s.usecase + 3
      elseif w == "state" then
        s.state = s.state + 3
      elseif w == "object" or w == "map" then
        s.object = s.object + 3
      elseif act_kw[w] then
        s.activity = s.activity + 3
      elseif (w == "if" or w == "while" or w == "switch") and ll:match("^%a+%s*%(") then
        s.activity = s.activity + 3
      elseif w == "package" or w == "namespace" then
        s.class = s.class + 1
      elseif w == "rectangle" then
        s.usecase = s.usecase + 1
        s.component = s.component + 1
      end
    end
    if l:match("^:.*[;|<>/%]}]$") then
      s.activity = s.activity + 3
    elseif l:match("^|.+|") then
      s.activity = s.activity + 3
    elseif l:match("^%.%.%.") or l:match("^==.+==$") then
      s.sequence = s.sequence + 2
    end
    if l:find("[*]", 1, true) then
      s.state = s.state + 3
    elseif l:match("^%[[^%]]+%]") or l:match("%-%s*%[[^%]]+%]") then
      s.component = s.component + 2
    end
    if l:match("^%([^%)]+%)") or l:match("[%-%.]>?%s*%([^%)]+%)%s*$") then
      s.usecase = s.usecase + 2
    end
    if l:find("<|", 1, true) or l:find("|>", 1, true) or l:match("%*%-%-") or l:match("o%-%-") or l:match("%-%-o%s") or l:match("%-%-%*") then
      s.class = s.class + 2
    end
  end
  local order = { "sequence", "activity", "class", "state", "usecase", "component", "object" }
  local best, score = "sequence", 0
  for _, t in ipairs(order) do
    if s[t] > score then
      best, score = t, s[t]
    end
  end
  return best
end

---------------------------------------------------------------------------
-- Names (participants, classes, components, ...)
---------------------------------------------------------------------------

local decl_kw = set({
  "participant", "actor", "boundary", "control", "entity", "database", "collections", "queue",
  "class", "interface", "abstract", "enum", "annotation", "protocol", "struct", "exception",
  "component", "node", "cloud", "artifact", "folder", "frame", "storage", "agent", "stack", "file",
  "usecase", "rectangle", "package", "namespace", "state", "object", "map", "card", "person",
  "hexagon", "label", "process", "action", "circle", "collections", "port", "portin", "portout",
})

local function name_from_decl(rest)
  rest = rest:gsub("^class%s+", "") -- "abstract class X"
  rest = rest:gsub("%s*{%s*$", "")
  local alias = rest:match("%s+as%s+([%w_%.]+)")
  if alias then
    -- `X as "Long name"` -> the alias is the quoted part; prefer the identifier
    local first = rest:match('^([%w_%.]+)%s+as%s+"')
    return first or alias
  end
  local q = rest:match('^(".-")')
  if q then
    return q
  end
  local b = rest:match("^(%[.-%])") or rest:match("^(%(.-%))") or rest:match("^(:.-:)")
  if b then
    return b
  end
  return rest:match("^([%w_%.]+)")
end

-- Read a "node" token at position i of s. Returns token, next index.
local function read_node(s, i)
  i = s:find("%S", i) or (#s + 1)
  local c = s:sub(i, i)
  local close = ({ ['"'] = '"', ["["] = "]", ["("] = ")", [":"] = ":" })[c]
  if close then
    local j = s:find(close, i + 1, true)
    if j then
      return s:sub(i, j), j + 1
    end
    return nil, i
  end
  local tok = s:match("^[%w_][%w_%.]*", i)
  if tok then
    return tok, i + #tok
  end
  return nil, i
end

local arrow_pat = "^([<%*o#x|}%+%^\\/]*[%-%.=~][%w%-%.=~%[%]#,]*[>%*o#x|{%+%^\\/]*)"

--- Parse an arrow line. Returns { from, arrow, to, label } or nil.
function M.parse_arrow(line)
  local l = trim(line)
  local left, i = read_node(l, 1)
  if not left then
    return nil
  end
  i = l:find("%S", i) or (#l + 1)
  -- optional cardinality: A "1" --> "*" B
  local card = l:match('^"[^"]*"%s*', i)
  if card and l:sub(i, i) == '"' then
    i = i + #card
  end
  local arrow = l:match(arrow_pat, i)
  if not arrow or not arrow:find("[%-%.=~]") then
    return nil
  end
  i = i + #arrow
  i = l:find("%S", i) or (#l + 1)
  local card2 = l:match('^"[^"]*"%s*', i)
  if card2 then
    i = i + #card2
  end
  local right, j = read_node(l, i)
  if not right then
    return nil
  end
  local label = l:match("^%s*:%s*(.*)$", j)
  return { from = left, arrow = arrow, to = right, label = label }
end

local skip_kw = set({ "note", "skinparam", "title", "header", "footer", "legend", "caption", "hide", "show", "left", "top", "scale", "autonumber", "activate", "deactivate", "return", "newpage" })

--- Collect names declared/used in the diagram body, in order of appearance.
function M.names(body)
  local out, seen = {}, {}
  local function add(n)
    if n and n ~= "" and not seen[n] then
      seen[n] = true
      table.insert(out, n)
    end
  end
  for _, l in each_line(body) do
    local w, rest = l:match("^([%a_]+)%s+(.*)$")
    -- keywords are case-sensitive (lowercase), so `Circle --> Point` is not a declaration
    local lw = w
    if lw and decl_kw[lw] then
      add(name_from_decl(rest))
    elseif not (lw and skip_kw[lw]) and not l:match("^@") then
      local a = M.parse_arrow(l)
      if a then
        add(a.from)
        add(a.to)
      end
    end
  end
  return out
end

---------------------------------------------------------------------------
-- Blocks (loop/alt/if/while/fork/{...}) for text objects and indentation
---------------------------------------------------------------------------

local end_kw = set({ "loop", "alt", "opt", "par", "break", "critical", "group" })

local function opener(ll)
  local w = ll:match("^([%a_]+)")
  if ll:match("{%s*$") then
    return "brace"
  end
  if not w then
    return nil
  end
  if end_kw[w] then
    return "end"
  elseif w == "box" then
    return "box"
  elseif (w == "note" or w == "hnote" or w == "rnote") and not ll:find(":", 1, true) then
    return "note"
  elseif w == "ref" and not ll:find(":", 1, true) then
    return "ref"
  elseif w == "legend" then
    return "legend"
  elseif w == "if" and ll:match("^if%s*%(") then
    return "if"
  elseif w == "while" and ll:match("^while%s*%(") then
    return "while"
  elseif w == "switch" and ll:match("^switch%s*%(") then
    return "switch"
  elseif w == "repeat" and not ll:match("^repeat%s*while") then
    return "repeat"
  elseif w == "fork" and not ll:match("^fork%s+again") then
    return "fork"
  elseif w == "split" and not ll:match("^split%s+again") then
    return "split"
  end
  return nil
end

local function closer(ll)
  if ll:match("^}") then
    return "brace"
  elseif ll:match("^endif") or ll:match("^end%s+if") then
    return "if"
  elseif ll:match("^endwhile") or ll:match("^end%s*while") then
    return "while"
  elseif ll:match("^endswitch") then
    return "switch"
  elseif ll:match("^repeat%s*while") then
    return "repeat"
  elseif ll:match("^end%s*fork") or ll:match("^end%s*merge") then
    return "fork"
  elseif ll:match("^end%s*split") then
    return "split"
  elseif ll:match("^end%s*box") then
    return "box"
  elseif ll:match("^end%s*[hr]?note") then
    return "note"
  elseif ll:match("^end%s*ref") then
    return "ref"
  elseif ll:match("^end%s*legend") then
    return "legend"
  elseif ll:match("^end%s*$") or ll:match("^end%s+group") then
    return "end"
  end
  return nil
end

--- Returns a list of blocks { s = row, e = row, kind = string } (rows relative to `lines`).
function M.blocks(lines)
  local stack, out = {}, {}
  for i, l in each_line(lines) do
    local ll = l:lower()
    local c = closer(ll)
    if c then
      for k = #stack, 1, -1 do
        if stack[k].kind == c then
          local b = stack[k]
          b.e = i
          table.insert(out, b)
          for _ = k, #stack do
            table.remove(stack)
          end
          break
        end
      end
    else
      local o = opener(ll)
      if o then
        table.insert(stack, { s = i, kind = o })
      end
    end
  end
  return out
end

--- Blocks containing `row`, innermost first.
function M.enclosing(lines, row)
  local res = {}
  for _, b in ipairs(M.blocks(lines)) do
    if b.s <= row and row <= b.e then
      table.insert(res, b)
    end
  end
  table.sort(res, function(a, b)
    return (a.e - a.s) < (b.e - b.s)
  end)
  return res
end

M._opener = opener
return M
