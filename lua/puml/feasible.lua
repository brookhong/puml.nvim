-- Grammar feasibility of wrapping a selection in a block: which wrap blocks make
-- sense for lines s..e of a diagram. PlantUML is lenient (it silently accepts a
-- `loop` cutting an `alt` in half, a `box` around messages, a `package` inside a
-- class body, ...), so these are structural rules of our own.
local parse = require("puml.parse")
local catalog = require("puml.catalog")

local M = {}

local function trim(s)
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function first_word(ll)
  return ll:match("^([%a_]+)")
end

local DECL = {
  participant = true, actor = true, boundary = true, control = true, entity = true,
  database = true, collections = true, queue = true,
}

-- blocks whose content is text or members, not statements: nothing can be wrapped inside
local CLASSLIKE = {
  class = true, abstract = true, interface = true, enum = true, annotation = true, entity = true,
  struct = true, object = true, map = true, json = true, protocol = true, exception = true,
  metaclass = true, stereotype = true, skinparam = true, style = true, sprite = true,
}

-- statements that apply to the whole diagram and must stay at the top level
local function is_global(ll)
  return ll:match("^left%s+to%s+right") or ll:match("^top%s+to%s+bottom") or ll:match("^skinparam")
    or ll:match("^hide%s") or ll:match("^show%s") or ll:match("^title[%s:]") or ll:match("^header")
    or ll:match("^footer") or ll:match("^caption") or ll:match("^scale%s") or ll:match("^!")
    or ll:match("^autonumber") or ll:match("^newpage") or ll:match("^mainframe") or ll == "title"
    or ll:match("^remove%s") or ll:match("^restore%s") or ll:match("^set%s") or ll:match("^allowmixing")
end

-- blocks holding text, not statements: never wrapped into, nor wrapped as part of a group
local TEXT = { note = true, ref = true, legend = true, title = true, header = true, footer = true, style = true }
-- of those, the ones that apply to the whole diagram
local META = { legend = true, title = true, header = true, footer = true, style = true }

--- Multi-line spans that are not blocks but must not be split: /' block comments '/
--- and activity actions `:line 1 ⏎ line 2;`. Returns { s, e, kind } (rows of `body`).
local function spans(body, typ)
  local out, i = {}, 1
  while i <= #body do
    local t = trim(body[i])
    if t:sub(1, 2) == "/'" and not t:find("'/", 3, true) then
      local j = i + 1
      while j <= #body and not body[j]:find("'/", 1, true) do
        j = j + 1
      end
      table.insert(out, { s = i, e = math.min(j, #body), kind = "comment" })
      i = j
    elseif typ == "activity" and t:match("^#?[%w#]*:") and not t:match("[;|<>/%]}]%s*$") and not t:lower():match("^note")
      and not t:lower():match("^title") and not t:lower():match("^header") and not t:lower():match("^footer") then
      local j = i + 1
      while j <= #body and not trim(body[j]):match("[;|<>/%]}]$") do
        j = j + 1
      end
      if j <= #body then
        table.insert(out, { s = i, e = j, kind = "action" })
        i = j
      end
    end
    i = i + 1
  end
  return out
end

local function is_mid(ll)
  return ll:match("^else%f[%W]") or ll:match("^elseif") or ll:match("^fork%s+again")
    or ll:match("^split%s+again") or ll:match("^case%s*%(")
    or ll == "--" or ll == "||" -- concurrent regions of a composite state
end

local function blank_or_comment(l)
  local t = trim(l)
  return t == "" or t:match("^'") ~= nil
end

--- Classify the selection s..e (rows relative to `body`; `off` turns them into buffer lines).
--- @return table|nil info, string|nil reason
local function analyse(body, s, e, off, typ)
  -- 0. multi-line comments and actions must be selected whole
  local comment_rows = {}
  for _, sp in ipairs(spans(body, typ)) do
    local what = sp.kind == "comment" and "comment" or ("action `" .. trim(body[sp.s]) .. "`")
    if sp.s <= s and e <= sp.e and not (sp.s == s and sp.e == e) then
      return nil, ("the selection is inside a multi-line %s (line %d)"):format(what, sp.s + off)
    elseif sp.s <= e and s <= sp.e and not (s <= sp.s and sp.e <= e) then
      return nil, ("the selection cuts the multi-line %s (line %d) in half"):format(what, sp.s + off)
    end
    if sp.kind == "comment" then
      for r = sp.s, sp.e do
        comment_rows[r] = true
      end
    end
  end
  local blocks = parse.blocks(body)
  -- 1. the selection must hold whole blocks: no opener without its closer, or the reverse
  for _, b in ipairs(blocks) do
    local has_s, has_e = b.s >= s and b.s <= e, b.e >= s and b.e <= e
    if has_s ~= has_e then
      return nil, ("the selection cuts `%s` (line %d) in half"):format(trim(body[b.s]), b.s + off)
    end
  end
  -- 2. `else` / `fork again` / `case` belong to their block: only with the whole block
  for i = s, e do
    local ll = trim(body[i]):lower()
    if is_mid(ll) then
      local inside = false
      for _, b in ipairs(blocks) do
        if b.s < i and i < b.e and b.s >= s and b.e <= e then
          inside = true
          break
        end
      end
      if not inside then
        return nil, ("`%s` (line %d) belongs to a block outside the selection"):format(trim(body[i]), i + off)
      end
    end
  end
  -- 3. what the selection sits in
  local ctx
  for _, b in ipairs(blocks) do
    if b.s < s and e < b.e and (not ctx or b.s > ctx.s) then
      ctx = b
    end
  end
  if ctx then
    local opener = trim(body[ctx.s]):lower()
    if TEXT[ctx.kind] then
      return nil, "the selection is inside a " .. (ctx.kind == "style" and "<style> block" or ctx.kind)
    elseif ctx.kind == "box" then
      return nil, "a box can only hold participant declarations"
    elseif ctx.kind == "brace" and CLASSLIKE[first_word(opener) or ""] then
      return nil, "the selection is inside the body of `" .. trim(body[ctx.s]):gsub("%s*{%s*$", "") .. "`"
    end
  end
  -- 4. what the selection holds (top-level lines of the selection)
  local info = { statements = 0, decls = 0, messages = 0, dividers = 0, notes = 0, has_box = false, has_start = false, has_global = false, has_lane = false }
  local depth_rows, text_rows, closer_rows = {}, {}, {}
  for _, b in ipairs(blocks) do
    if b.s >= s and b.e <= e then
      closer_rows[b.e] = true -- counted with its opener, not as a statement of its own
      if b.kind == "box" then
        info.has_box = true
      end
      if META[b.kind] and not info.has_global then
        info.has_global = b.s
      end
      local text = TEXT[b.kind] or (b.kind == "brace" and CLASSLIKE[first_word(trim(body[b.s]):lower()) or ""])
      for r = b.s + 1, b.e - 1 do
        depth_rows[r] = true
        if text then
          text_rows[r] = true -- note text, class members, ...: not statements
        end
      end
      if not depth_rows[b.s] and b.kind == "note" then
        info.notes = info.notes + 1
      end
    end
  end
  for i = s, e do
    local l = body[i]
    if not blank_or_comment(l) and not comment_rows[i] and not text_rows[i] then
      local ll = trim(l):lower()
      info.statements = info.statements + 1
      if is_global(ll) and not info.has_global then
        info.has_global = i
      end
      if ll:match("^|") then
        info.has_lane = true
      end
      if ll == "start" then
        info.has_start = true
      end
      if not depth_rows[i] and DECL[first_word(ll) or ""] and not parse.parse_arrow(trim(l)) then
        info.decls = info.decls + 1
      end
      if parse.parse_arrow(trim(l)) then
        info.messages = info.messages + 1
      end
      -- `== section ==` spans the whole diagram (drawn through any group frame)
      if ll:match("^==.*==$") then
        info.dividers = info.dividers + 1
      end
      if not depth_rows[i] and (ll:match("^note.*:") or ll:match("^floating%s+note")) then
        info.notes = info.notes + 1
      end
    end
  end
  if info.statements == 0 then
    return nil, "the selection holds no statements"
  end
  if info.has_global then
    local g = trim(body[info.has_global])
    local gl = g:lower()
    if gl:match("^!") and not (gl:match("^!theme") or gl:match("^!pragma") or gl:match("^!include")) then
      return nil, ("`%s` (line %d) is a preprocessor line; wrapping around it can break !if/!endif and friends"):format(g, info.has_global + off)
    end
    return nil, ("`%s` (line %d) applies to the whole diagram; leave it out"):format(g, info.has_global + off)
  end
  if info.has_lane then
    return nil, "the selection holds a swimlane"
  end
  info.ctx = ctx
  for _, l in ipairs(body) do
    if l:find("(*)", 1, true) then
      info.legacy = true -- old activity syntax
      break
    end
  end
  -- top-level statements of the selection (nested block openers count, their insides not)
  info.top = 0
  for i = s, e do
    if not depth_rows[i] and not closer_rows[i] and not comment_rows[i] and not blank_or_comment(body[i]) then
      info.top = info.top + 1
    end
  end
  return info
end

-- does block `w` fit a selection described by `info` in a `typ` diagram?
local function fits(typ, w, info)
  local label = w.label
  if typ == "sequence" then
    local only_decls = info.decls == info.statements
    if label == "box" then
      return only_decls and not info.has_box and info.ctx == nil, "a box can only hold participant declarations"
    end
    if info.has_box then
      return false, "a box can't be nested in a group"
    end
    if info.dividers > 0 then
      return false, "a `== section ==` divider spans the whole diagram; leave it out of the group"
    end
    if only_decls then
      return false, "a group needs messages, not only declarations"
    end
    if info.decls > 0 then
      return false, "participant declarations don't belong in a group; leave them out (or use `create`)"
    end
    if label:match("^activate") then
      return info.messages > 0, "activation needs a message"
    end
    return true
  elseif typ == "activity" then
    if info.legacy then
      return false, "the old `(*)` activity syntax doesn't mix with if/while/fork blocks"
    end
    if info.has_start then
      return false, "`start` can't be inside a block"
    end
    if info.top <= info.notes then
      return false, "a block needs an action, not only notes"
    end
    return true
  end
  if typ == "class" or typ == "object" or typ == "component" or typ == "usecase" then
    if label == "namespace" and (typ == "component" or typ == "usecase") then
      return false, "namespace is for class diagrams"
    end
    if label == "together" and info.messages > 0 then
      return false, "together only groups declarations, not relations"
    end
    return true
  end
  return true
end

--- Wrap blocks that are feasible for body rows s..e of diagram `d` (buffer rows).
--- @return table[] wraps, string|nil reason (when none)
function M.wraps(d, s, e)
  local all = catalog.wraps_for(d.type)
  if #all == 0 then
    return {}, "no blocks for " .. d.type .. " diagrams"
  end
  if s < d.body_s or e > d.body_e then
    return {}, "the selection is not inside a diagram body"
  end
  local rs, re = s - d.body_s + 1, e - d.body_s + 1
  local info, reason = analyse(d.body, rs, re, d.body_s - 1, d.type)
  if not info then
    return {}, reason
  end
  local out, why = {}, nil
  for _, w in ipairs(all) do
    local ok, r = fits(d.type, w, info)
    if ok then
      table.insert(out, w)
    else
      why = why or r
    end
  end
  return out, (#out == 0) and why or nil
end

---------------------------------------------------------------------------
-- Insertion: which catalog items fit where a new line goes
---------------------------------------------------------------------------

-- what kind of statement an item inserts (items may also set `kind` themselves)
local KIND = {
  sequence = {
    participant = "decl", ["participant with alias"] = "decl", actor = "decl", boundary = "decl",
    control = "decl", entity = "decl", database = "decl", collections = "decl", queue = "decl",
    ["box (participants)"] = "box", divider = "divider", autonumber = "global", ["hide footbox"] = "global",
  },
  class = { field = "member", method = "member" },
  activity = { start = "top", swimlane = "top", detach = "after", kill = "after" },
  component = { port = "after" },
  state = { ["concurrent region"] = "region" },
}
local GLOBAL_ITEMS = {
  title = true, skinparam = true, theme = true, header = true, footer = true, caption = true, legend = true,
  ["left to right direction"] = true, ["top to bottom direction"] = true, ["hide empty members"] = true,
}
-- class-like bodies whose content is members (fields / methods / enum values)
local MEMBERS = { class = true, abstract = true, interface = true, enum = true, annotation = true, entity = true,
  struct = true, protocol = true, exception = true, metaclass = true }

function M.kind(typ, item)
  if item.kind then
    return item.kind
  end
  if GLOBAL_ITEMS[item.label] then
    return "global"
  end
  if item.label == "comment" then
    return "comment"
  end
  -- a note attached to an element: something must come before it (as the first
  -- statement it also throws off PlantUML's diagram-type detection)
  if item.body:match("^note [^\n]* of ") then
    return "after"
  end
  return (KIND[typ] or {})[item.label] or "statement"
end

--- Where the new line at buffer line `p` (inserted before the current line p) would sit:
--- the innermost enclosing block, or a reason nothing can go there.
local function insertion_context(d, p)
  local body = d.body
  local rp = p - d.body_s + 1 -- body-relative
  for _, sp in ipairs(spans(body, d.type)) do
    if sp.s < rp and rp <= sp.e then
      return nil, ("the cursor is inside a multi-line %s (line %d)"):format(sp.kind == "comment" and "comment" or "action", sp.s + d.body_s - 1)
    end
  end
  local ctx
  for _, b in ipairs(parse.blocks(body)) do
    if b.s < rp and rp <= b.e and (not ctx or b.s > ctx.s) then
      ctx = b
    end
  end
  -- anything (but comments) before the new line?
  local before = false
  for i = 1, rp - 1 do
    local t = trim(body[i] or "")
    if t ~= "" and not t:match("^'") and not is_global(t:lower()) then
      before = true
      break
    end
  end
  if not ctx then
    return { top = true, before = before }
  end
  local opener = trim(body[ctx.s])
  local w = first_word(opener:lower()) or ""
  if TEXT[ctx.kind] then
    return nil, "the cursor is inside a " .. (ctx.kind == "style" and "<style> block" or ctx.kind)
  elseif ctx.kind == "brace" and MEMBERS[w] then
    return { members = true, opener = opener }
  elseif ctx.kind == "brace" and CLASSLIKE[w] then
    return nil, "the cursor is inside the body of `" .. opener:gsub("%s*{%s*$", "") .. "`"
  elseif ctx.kind == "box" then
    return { box = true }
  end
  return { block = ctx.kind, state = ctx.kind == "brace" and w == "state", before = true }
end

--- Catalog items that can be inserted as a new line at buffer line `p` of diagram `d`.
--- @return table[] items, string|nil reason (when none)
function M.insertable(d, p)
  local all = catalog.items_for(d.type)
  if #all == 0 then
    return {}, "nothing to insert in " .. d.type .. " diagrams"
  end
  local where, why = insertion_context(d, p)
  if not where then
    return {}, why
  end
  local out = {}
  for _, it in ipairs(all) do
    local k = M.kind(d.type, it)
    local ok
    if k == "comment" then
      ok = true
    elseif k == "after" and not where.before then
      ok = false
    elseif where.members then
      ok = k == "member"
    elseif where.box then
      ok = k == "decl"
    elseif k == "member" then
      ok = false
    elseif k == "region" then
      ok = where.state == true
    elseif where.top then
      ok = true
    else -- inside a group / if / package / composite state ...
      ok = not (k == "global" or k == "box" or k == "divider" or k == "top" or k == "decl")
    end
    if ok then
      table.insert(out, it)
    end
  end
  if #out == 0 then
    return {}, where.members and "nothing to insert here" or "nothing fits here"
  end
  return out
end

return M
