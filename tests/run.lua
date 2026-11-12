-- Run: nvim --headless -u NONE -l tests/run.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.cmd("runtime plugin/puml.lua")
vim.cmd("runtime ftdetect/plantuml.lua")
vim.cmd("filetype plugin on")
vim.o.expandtab, vim.o.shiftwidth = true, 2

local fails, passes = 0, 0
local function eq(name, got, want)
  if vim.deep_equal(got, want) then
    passes = passes + 1
  else
    fails = fails + 1
    print("FAIL " .. name .. "\n  got:  " .. vim.inspect(got) .. "\n  want: " .. vim.inspect(want))
  end
end
local function wait(ms, cond)
  return vim.wait(ms, cond, 20)
end

local parse = require("puml.parse")
local util = require("puml.util")
require("puml").setup({ picker = { ui = "select" }, keymaps = { textobjects = { inner = "iu", outer = "au" } } }) -- tests stub vim.ui.select

-- detect ---------------------------------------------------------------
local cases = {
  sequence = { "actor User", "participant API", "User -> API: hi", "loop x", "end" },
  class = { "class A", "class B", "A <|-- B" },
  activity = { "start", ":do;", "if (x?) then (yes)", "endif", "stop" },
  usecase = { "actor U", "U --> (Login)" },
  component = { "[A] --> [B]", "node N" },
  state = { "[*] --> S1", "S1 --> S2" },
}
for want, body in pairs(cases) do
  eq("detect " .. want, parse.detect(body, "uml"), want)
end
eq("detect default", parse.detect({ "A -> B" }, "uml"), "sequence")
eq("detect mindmap", parse.detect({ "* a" }, "mindmap"), "mindmap")

-- arrows / names ---------------------------------------------------------
eq("arrow simple", parse.parse_arrow("Alice -> Bob: hello"), { from = "Alice", arrow = "->", to = "Bob", label = "hello" })
eq("arrow nospace", parse.parse_arrow("A-->B").arrow, "-->")
eq("arrow class", parse.parse_arrow('Car "1" *-- "4" Wheel : has'), { from = "Car", arrow = "*--", to = "Wheel", label = "has" })
eq("arrow state", parse.parse_arrow("[*] --> Idle").from, "[*]")
eq("arrow dir", parse.parse_arrow("A -left-> B").arrow, "-left->")
eq("arrow color", parse.parse_arrow("A -[#red]-> B").to, "B")
eq("not arrow", parse.parse_arrow("title Hello"), nil)
eq("names", parse.names({
  "actor User",
  'participant "Long API" as API',
  "database DB",
  "User -> API: x",
  "API -> Cache",
  "' Ghost -> Nope",
  "note over User: hi",
}), { "User", "API", "DB", "Cache" })
eq("names class", parse.names({ "abstract class Shape", "class Circle {", "}", "Shape <|-- Circle", "Circle --> Point" }), { "Shape", "Circle", "Point" })

-- blocks -------------------------------------------------------------------
local body = {
  "A -> B", -- 1
  "loop retry", -- 2
  "  alt ok", -- 3
  "    B -> A", -- 4
  "  else", -- 5
  "    B -> C", -- 6
  "  end", -- 7
  "end", -- 8
  "note over A", -- 9
  "  text", -- 10
  "end note", -- 11
}
local bl = parse.enclosing(body, 4)
eq("enclosing count", #bl, 2)
eq("innermost", { bl[1].s, bl[1].e }, { 3, 7 })
eq("outer", { bl[2].s, bl[2].e }, { 2, 8 })
eq("note block", { parse.enclosing(body, 10)[1].s, parse.enclosing(body, 10)[1].e }, { 9, 11 })
local act = { "start", "if (a?) then (y)", "  while (b?)", "    :x;", "  endwhile", "else (n)", "  :y;", "endif", "stop" }
local ab = parse.enclosing(act, 4)
eq("activity blocks", { ab[1].kind, ab[2].kind }, { "while", "if" })

-- util.current ---------------------------------------------------------------
local buf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "@startuml", "A -> B", "@enduml", "", "@startuml", "class X", "class Y", "X --> Y", "@enduml",
})
local d1 = util.current(buf, 2)
eq("cur1", { d1.index, d1.count, d1.type, d1.body_s, d1.body_e }, { 1, 2, "sequence", 2, 2 })
local d2 = util.current(buf, 7)
eq("cur2", { d2.index, d2.type, d2.s, d2.e, #d2.input }, { 2, "class", 5, 9, 5 })
eq("cur between", util.current(buf, 4).index, 1)

local nobuf = vim.api.nvim_create_buf(true, false)
vim.api.nvim_buf_set_lines(nobuf, 0, -1, false, { "A -> B" })
local dn = util.current(nobuf, 1)
eq("wrapped", { dn.wrapped, dn.input }, { true, { "@startuml", "A -> B", "@enduml" } })

local md = vim.api.nvim_create_buf(true, false)
vim.bo[md].filetype = "markdown"
vim.api.nvim_buf_set_lines(md, 0, -1, false, { "# t", "```plantuml", "Alice -> Bob", "```", "text", "```puml", "@startuml", "[*] --> S", "@enduml", "```" })
eq("md out", util.current(md, 1), nil)
local dm = util.current(md, 3)
eq("md 1", { dm.index, dm.type, dm.body_s, dm.wrapped, dm.base }, { 1, "sequence", 3, true, 2 })
local dm2 = util.current(md, 8)
eq("md 2", { dm2.index, dm2.type, dm2.s, dm2.body_s, dm2.base }, { 2, "state", 7, 8, 7 })

-- render (real plantuml) ------------------------------------------------------
local render = require("puml.render")
local res
render.render({ "@startuml", "Alice -> Bob: hi", "@enduml" }, "utxt", nil, function(r)
  res = r
end)
wait(30000, function()
  return res ~= nil
end)
eq("render ok", res and res.ok, true)
eq("render has box", res and res.data and res.data:find("Alice", 1, true) ~= nil, true)

res = nil
render.render({ "@startuml", "Alice -> Bob: hi", "foo bar ((", "@enduml" }, "utxt", nil, function(r)
  res = r
end)
wait(30000, function()
  return res ~= nil
end)
eq("render err", res and { res.ok, res.err.line }, { false, 2 })

local png = vim.fn.tempname() .. ".png"
res = nil
render.render({ "@startuml", "class A", "@enduml" }, "png", png, function(r)
  res = r
end)
wait(30000, function()
  return res ~= nil
end)
eq("render png", res and res.ok and vim.fn.getfsize(png) > 100, true)

-- preview -------------------------------------------------------------------------
local preview = require("puml.preview")
vim.api.nvim_set_current_buf(buf)
vim.api.nvim_win_set_cursor(0, { 2, 0 })
preview.open(buf)
local s = preview.state[buf]
wait(30000, function()
  return vim.api.nvim_buf_get_lines(s.pbuf, 0, -1, false)[2] and vim.api.nvim_buf_get_lines(s.pbuf, 0, 1, false)[1]:find("┌") ~= nil
end)
eq("preview text", table.concat(vim.api.nvim_buf_get_lines(s.pbuf, 0, -1, false), "\n"):find("│A│", 1, true) ~= nil, true)
eq("preview win count", #vim.api.nvim_tabpage_list_wins(0), 2)
vim.api.nvim_win_set_cursor(0, { 7, 0 }) -- class diagram -> image mode
preview.render(buf)
wait(30000, function()
  return table.concat(vim.api.nvim_buf_get_lines(s.pbuf, 0, -1, false), "\n"):find("%.png") ~= nil
end)
local ptxt = table.concat(vim.api.nvim_buf_get_lines(s.pbuf, 0, -1, false), "\n")
eq("preview image path", ptxt:find("diagram%-" .. buf .. "%-2%.png") ~= nil, true)
eq("preview image size", ptxt:find("Size:") ~= nil, true)
-- error diagnostic
vim.api.nvim_buf_set_lines(buf, 6, 7, false, { "class Y {{{ ((" })
preview.render(buf, { force = true })
wait(30000, function()
  return #vim.diagnostic.get(buf) > 0
end)
local diags = vim.diagnostic.get(buf)
eq("diagnostic row", diags[1] and diags[1].lnum, 6)
preview.close(buf)
eq("preview closed", preview.is_open(buf), false)

-- wrap ----------------------------------------------------------------------------------
local wb = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(wb)
vim.bo[wb].filetype = "plantuml"
vim.bo[wb].expandtab = true
vim.api.nvim_buf_set_lines(wb, 0, -1, false, { "@startuml", "A -> B: x", "B --> A: y", "@enduml" })
local orig_input, orig_select = vim.ui.input, vim.ui.select
vim.ui.input = function(_, cb)
  cb("retry")
end
require("puml.actions").wrap_range(2, 3, "loop")
eq("wrap loop", vim.api.nvim_buf_get_lines(wb, 0, -1, false), { "@startuml", "loop retry", "  A -> B: x", "  B --> A: y", "end", "@enduml" })
vim.api.nvim_buf_set_lines(wb, 0, -1, false, { "@startuml", "A -> B: x", "@enduml" })
require("puml.actions").wrap_range(2, 2, "alt-else")
eq("wrap alt", vim.api.nvim_buf_get_lines(wb, 0, -1, false), { "@startuml", "alt retry", "  A -> B: x", "else", "  ", "end", "@enduml" })
eq("wrap alt cursor", vim.api.nvim_win_get_cursor(0)[1], 5)

-- placeholder markup ---------------------------------------------------------------------------
do
  local picker = require("puml.picker")
  local function plain(s)
    local p, r = picker.markup(s)
    return { p, vim.tbl_map(function(x) return p:sub(x[1] + 1, x[2]) end, r) }
  end
  eq("markup desc", plain(picker.desc("repeat while {condition} holds")), { "repeat while condition holds", { "condition" } })
  eq("markup snippet", plain(picker.snippet("${1:A} -> ${2:B}: ${0:message}")), { "A -> B: message", { "A", "B", "message" } })
  eq("markup snippet mirror", plain(picker.snippet("${1:A} -> ${1}: ${0:action}")), { "A -> A: action", { "A", "A", "action" } })
  eq("markup snippet choice", plain(picker.snippet("note ${1|left,right|}: ${0:text}")), { "note left: text", { "left", "text" } })
  eq("markup snippet multi-line", plain(picker.snippet("loop ${1:condition}\n\t${0}\nend")), { "loop condition …", { "condition" } })
  eq("markup literal braces stay", plain(picker.snippet("class ${1:Name} {\n\t${0}\n}")), { "class Name { …", { "Name" } })
end

-- labelled picker ----------------------------------------------------------------------------
do
  local picker = require("puml.picker")
  local cfg = require("puml.config").options
  eq("picker mnemonics", picker.assign({ { text = "message" }, { text = "reply message" }, { text = "async message" }, { text = "+ new", key = "+" } }, "abcdefghijklmnopqrstuvwxyz"), { "m", "r", "a", "+" })
  eq("picker mnemonics limited to pool", picker.assign({ { text = "message" } }, "asdf"), { "s" })
  eq("picker explicit key wins", picker.assign({ { text = "insert" }, { text = "inspect", key = "i" } }, "abcdefghijklmnopqrstuvwxyz"), { "n", "i" })
  eq("picker pool fallback", picker.assign({ { text = "aa" }, { text = "aa" }, { text = "aa" } }, "axy"), { "a", "x", "y" })
  cfg.picker.ui = "labels"
  local function run(keys, items, opts)
    local got = "unset"
    vim.api.nvim_feedkeys(vim.keycode(keys), "t", false)
    picker.select(items, opts or {}, function(it)
      got = it
    end)
    return got
  end
  local items = { "participant", "message", "reply message" }
  eq("picker pick by label", run("m", items), "message")
  eq("picker ignores non-labels", run("zr", items), "reply message")
  eq("picker esc", run("<Esc>", items), nil)
  eq("picker filter + CR", run("/reply<CR>", items), "reply message")
  eq("picker filter then label", run("/mess<CR>r", items), "reply message")
  eq("picker explicit key", run("x", items, { key = function(it) return it == "participant" and "x" or nil end }), "participant")
  eq("picker no window left", #vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative ~= "" end, vim.api.nvim_list_wins()), 0)
  -- the menu uses the keymap keys as labels
  vim.api.nvim_buf_set_lines(wb, 0, -1, false, { "@startuml", "A -> B: x", "@enduml" })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  local called
  local orig_connect = require("puml.actions").connect
  require("puml.actions").connect = function() called = true end
  vim.api.nvim_feedkeys("c", "t", false)
  require("puml.menu").open(wb)
  require("puml.actions").connect = orig_connect
  eq("menu label = keymap key", called, true)
  cfg.picker.ui = "select"
end

-- wrap feasibility ---------------------------------------------------------------------------
do
  local feasible = require("puml.feasible")
  local function labels(typ, body, s, e)
    local d = { type = typ, body = body, body_s = 2, body_e = #body + 1 } -- body starts at buffer line 2
    local ws, why = feasible.wraps(d, s + 1, e + 1)
    return #ws > 0 and table.concat(vim.tbl_map(function(w) return w.label end, ws), ",") or why
  end
  local seq = { "actor User", "participant API", "User -> API: a", "loop retry", "API -> User: b", "end",
    "alt ok", "User -> API: c", "else no", "User -> API: d", "end", "note over API", "text", "end note",
    "box Infra", "participant Cache", "end box" }
  eq("feasible: declarations -> box only", labels("sequence", seq, 1, 2), "box")
  eq("feasible: message -> groups, no box", labels("sequence", seq, 3, 3), "loop,alt / else,opt,par,break,critical,group,activate / deactivate")
  eq("feasible: whole loop", labels("sequence", seq, 4, 6):match("^loop,") ~= nil, true)
  eq("feasible: half a loop", labels("sequence", seq, 4, 5), "the selection cuts `loop retry` (line 5) in half")
  eq("feasible: else of outer alt", labels("sequence", seq, 8, 9), "`else no` (line 10) belongs to a block outside the selection")
  eq("feasible: whole alt incl. else", labels("sequence", seq, 7, 11):match("^loop,") ~= nil, true)
  eq("feasible: inside note", labels("sequence", seq, 13, 13), "the selection is inside a note")
  eq("feasible: inside box", labels("sequence", seq, 16, 16), "a box can only hold participant declarations")
  eq("feasible: box in group", labels("sequence", seq, 3, 17), "a box can't be nested in a group")
  local sec = { 'participant "Pricing Calculator UI Author" as pcua', "== Authors onboard ==", "Author -> bsp: create",
    "Author -> pcub: verify", "Author -> bsp: promote" }
  eq("feasible: divider", labels("sequence", sec, 1, 5), "a `== section ==` divider spans the whole diagram; leave it out of the group")
  eq("feasible: declaration + messages", labels("sequence", { sec[1], sec[3], sec[4] }, 1, 3), "participant declarations don't belong in a group; leave them out (or use `create`)")
  eq("feasible: messages under the divider", labels("sequence", sec, 3, 5):match("^loop,") ~= nil, true)
  eq("feasible: create is fine", labels("sequence", { "create participant X", "Author -> X: new" }, 1, 2):match("^loop,") ~= nil, true)
  local act = { "start", ":a;", "if (x?) then (y)", ":b;", "else (n)", ":c;", "endif", "stop" }
  eq("feasible: start", labels("activity", act, 1, 2), "`start` can't be inside a block")
  eq("feasible: action", labels("activity", act, 2, 2), "if / else,if (no else),while,repeat,fork,split,partition,group")
  eq("feasible: if branch + else", labels("activity", act, 4, 5), "`else (n)` (line 6) belongs to a block outside the selection")
  eq("feasible: stop in a block is fine", labels("activity", act, 8, 8):match("^if") ~= nil, true)
  local cls = { "left to right direction", "class A {", "+x: int", "}", "class B", "A <|-- B" }
  eq("feasible: class body", labels("class", cls, 3, 3), "the selection is inside the body of `class A`")
  eq("feasible: whole class + relation", labels("class", cls, 2, 6):match("^package,namespace") ~= nil, true)
  eq("feasible: diagram-wide statement", labels("class", cls, 1, 1), "`left to right direction` (line 2) applies to the whole diagram; leave it out")
  -- text / meta blocks, comments, multi-line actions
  eq("feasible: legend", labels("sequence", { "A -> B: x", "legend", "info", "endlegend" }, 1, 4), "`legend` (line 3) applies to the whole diagram; leave it out")
  eq("feasible: inside legend", labels("sequence", { "legend", "info", "endlegend" }, 2, 2), "the selection is inside a legend")
  eq("feasible: multi-line title", labels("sequence", { "title", "T", "end title", "A -> B" }, 1, 4), "`title` (line 2) applies to the whole diagram; leave it out")
  eq("feasible: inside <style>", labels("sequence", { "<style>", "x { a b }", "</style>", "A -> B" }, 2, 2), "the selection is inside a <style> block")
  eq("feasible: newpage", labels("sequence", { "A -> B: 1", "newpage", "A -> B: 2" }, 1, 3), "`newpage` (line 3) applies to the whole diagram; leave it out")
  eq("feasible: cuts a block comment", labels("sequence", { "/' c", "still '/", "A -> B" }, 2, 3), "the selection cuts the multi-line comment (line 2) in half")
  eq("feasible: whole block comment", labels("sequence", { "/' c", "still '/", "A -> B" }, 1, 3):match("^loop,") ~= nil, true)
  eq("feasible: arrows in note text are not messages", labels("sequence", { "note over A", "A -> B", "end note" }, 1, 3):find("activate") == nil, true)
  eq("feasible: half a multi-line action", labels("activity", { "start", ":first", "second;", "stop" }, 2, 2), "the selection is inside a multi-line action `:first` (line 3)")
  eq("feasible: whole multi-line action", labels("activity", { "start", ":first", "second;", "stop" }, 2, 3):match("^if") ~= nil, true)
  eq("feasible: only a note", labels("activity", { ":a;", "note right: hi" }, 2, 2), "a block needs an action, not only notes")
  eq("feasible: legacy activity", labels("activity", { '(*) --> "a"', '"a" --> (*)' }, 1, 1), "the old `(*)` activity syntax doesn't mix with if/while/fork blocks")
  eq("feasible: state regions", labels("state", { "state S {", "[*] --> A", "--", "[*] --> B", "}" }, 2, 3), "`--` (line 4) belongs to a block outside the selection")
  eq("feasible: together without relations", labels("class", { "class A", "class B", "A --> B" }, 1, 3):find("together") == nil, true)
  eq("feasible: activity `end` counts as a statement", labels("activity", { "start", ":a;", "end" }, 3, 3):match("^if") ~= nil, true)
  eq("feasible: preprocessor", labels("sequence", { "!if %true()", "A -> B", "!endif" }, 1, 3), "`!if %true()` (line 2) is a preprocessor line; wrapping around it can break !if/!endif and friends")
  eq("feasible: :actor: is not an activity action", labels("usecase", { ":User: --> (Login)", "(Logout)" }, 1, 2):match("^package") ~= nil, true)
  eq("feasible: no namespace in component", labels("component", { "[A] --> [B]" }, 1, 1):find("namespace") == nil, true)
end

-- insert feasibility ---------------------------------------------------------------------------
do
  local feasible = require("puml.feasible")
  local function ins(typ, body, p)
    local d = { type = typ, body = body, body_s = 2, body_e = #body + 1 }
    local items, why = feasible.insertable(d, p + 1)
    local set = {}
    for _, it in ipairs(items) do
      set[it.label] = true
    end
    return set, why
  end
  local seq = { "actor User", "loop retry", "User -> API: x", "end", "note over API", "text", "end note", "box Infra", "participant Cache", "end box" }
  local top, inloop, inbox = ins("sequence", seq, 2), ins("sequence", seq, 3), ins("sequence", seq, 9)
  eq("insert: top level has declarations, title, box", { top.participant, top.title, top["box (participants)"], top.divider }, { true, true, true, true })
  eq("insert: in a loop, no declarations / title / box / divider", { inloop.participant, inloop.title, inloop["box (participants)"], inloop.divider, inloop.message, inloop.loop }, { nil, nil, nil, nil, true, true })
  eq("insert: before `end` is still in the loop", ins("sequence", seq, 4).participant, nil)
  eq("insert: in a box only declarations", { inbox.participant, inbox.message, inbox.loop, inbox.comment }, { true, nil, nil, true })
  eq("insert: in a note nothing", select(2, ins("sequence", seq, 6)), "the cursor is inside a note")
  eq("insert: no floating note in sequence", top["note (floating)"], nil)
  local cls = { "class A {", "+x: int", "}", "package P {", "class B", "}", "object o {", "f = 1", "}" }
  local body = ins("class", cls, 2)
  eq("insert: class body only members", { body.field, body.method, body.class, body.package }, { true, true, nil, nil })
  eq("insert: no members outside a class", { ins("class", cls, 4).field, ins("class", cls, 5).field }, { nil, nil })
  eq("insert: in object body nothing", select(2, ins("class", cls, 8)), "the cursor is inside the body of `object o`")
  eq("insert: attached note needs something before it", { ins("class", cls, 1)["note on class"], ins("class", cls, 4)["note on class"] }, { nil, true })
  local act = { "start", ":a;", "if (x?) then (y)", ":b;", "endif", ":multi", "line;", "stop" }
  eq("insert: start/swimlane only at top", { ins("activity", act, 2).start, ins("activity", act, 4).start, ins("activity", act, 4).swimlane }, { true, nil, nil })
  eq("insert: in multi-line action nothing", select(2, ins("activity", act, 7)), "the cursor is inside a multi-line action (line 7)")
  eq("insert: detach needs something before it", { ins("activity", act, 1).detach, ins("activity", act, 2).detach }, { nil, true })
  local st = { "[*] --> A", "state S {", "[*] --> B", "}" }
  eq("insert: concurrent region only in composite", { ins("state", st, 2)["concurrent region"], ins("state", st, 3)["concurrent region"] }, { nil, true })
  -- :PumlInsert refuses what doesn't fit, the menu hides Insert inside a note
  vim.api.nvim_buf_set_lines(wb, 0, -1, false, { "@startuml", "note over A", "text", "end note", "@enduml" })
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  require("puml.actions").insert("message")
  eq("insert: refused inside a note", vim.api.nvim_buf_get_lines(wb, 0, -1, false), { "@startuml", "note over A", "text", "end note", "@enduml" })
  local menu = require("puml.menu")
  local keys = table.concat(vim.tbl_map(function(a) return a.key end, menu.available(menu.context(wb))), "")
  eq("menu: no Insert inside a note", keys:find("i", 1, true) == nil, true)
end

-- selection hint ---------------------------------------------------------------------------------
do
  vim.o.columns = 120
  vim.api.nvim_buf_set_lines(wb, 0, -1, false, { "@startuml", "A -> B: x", "B --> A: y", "@enduml" })
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  local function key(k)
    vim.api.nvim_feedkeys(vim.keycode(k), "x", false)
    vim.api.nvim_exec_autocmds("CursorMoved", { buffer = wb }) -- a UI fires this after each key
    vim.wait(30, function() return false end)
  end
  local function hint()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local c = vim.api.nvim_win_get_config(w)
      if c.relative ~= "" then
        return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, -1, false), c
      end
    end
  end
  local function xmaps()
    return #vim.tbl_filter(function(m)
      return (m.desc or ""):match("^puml: wrap selection")
    end, vim.api.nvim_buf_get_keymap(wb, "x"))
  end
  local cfg = require("puml.config").options
  key("V")
  key("j")
  eq("no hint with vim.ui.select", hint(), nil)
  key("<Esc>")
  cfg.picker.ui = "labels"
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  key("V")
  key("j")
  local lines, c = hint()
  eq("hint shown on selection, with descriptions", lines and lines[1], " l  loop                   repeat while condition holds ")
  -- the placeholder ("condition": what wrapping will ask for) is styled
  local hb = vim.api.nvim_win_get_buf(vim.tbl_filter(function(w) return vim.api.nvim_win_get_config(w).relative ~= "" end, vim.api.nvim_list_wins())[1])
  local styled = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(hb, -1, { 0, 0 }, { 0, -1 }, { details = true })) do
    if m[4].hl_group == "PumlPickerPlaceholder" then
      table.insert(styled, lines[1]:sub(m[3] + 1, m[4].end_col))
    end
  end
  eq("hint styles the placeholder", styled, { "condition" })
  eq("hint title", c and table.concat(vim.tbl_map(function(x) return x[1] end, c.title)), " wrap 2 lines ")
  eq("hint beside the selection", c and c.col >= #"B --> A: y", true)
  eq("hint fits the screen", c and c.col + c.width + 2 <= vim.o.columns, true)
  key("j")
  local why, wc = hint()
  eq("hint says why over @enduml", { why and why[1], wc and table.concat(vim.tbl_map(function(x) return x[1] end, wc.title)) },
    { " ✗ the selection is not inside a diagram body ", " can't wrap " })
  eq("no live labels when nothing fits", xmaps(), 0)
  key("k")
  eq("hint back", hint() ~= nil, true)
  key("<Esc>")
  eq("hint closed after visual", hint(), nil)
  eq("no label maps outside visual", xmaps(), 0)
  vim.ui.input = function(_, cb)
    cb("ok")
  end
  vim.api.nvim_win_set_cursor(0, { 2, 0 })
  key("V")
  key("j")
  eq("label maps while V hint shows (no box around messages)", xmaps(), 8)
  key("l") -- loop
  eq("label wraps directly", vim.api.nvim_buf_get_lines(wb, 0, -1, false), { "@startuml", "loop ok", "  A -> B: x", "  B --> A: y", "end", "@enduml" })
  vim.wait(30, function() return false end)
  eq("label maps removed after", xmaps(), 0)
  -- a buffer-local x mapping shadowed by a label comes back afterwards
  vim.keymap.set("x", "q", "<Nop>", { buffer = wb, desc = "user q" })
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  key("V")
  eq("label shadows user map", (vim.fn.maparg("q", "x", false, true).desc or ""):match("^puml: wrap selection") ~= nil, true)
  key("<Esc>")
  vim.wait(30, function() return false end)
  eq("user map restored", vim.fn.maparg("q", "x", false, true).desc, "user q")
  vim.keymap.del("x", "q", { buffer = wb })
  -- selection keys keep their meaning
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  key("V")
  key("y")
  eq("y still yanks", vim.fn.getreg('"'), "  A -> B: x\n")
  -- `gv` without ModeChanged/CursorMoved (which-key feeds it and waits in getchar())
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  key("V")
  key("<Esc>")
  vim.wait(30, function() return false end)
  local ei = vim.o.eventignore
  vim.o.eventignore = "all"
  vim.api.nvim_feedkeys("gv", "x", false)
  vim.o.eventignore = ei
  vim.wait(30, function() return false end)
  eq("hint on gv without mode events", { vim.api.nvim_get_mode().mode, hint() ~= nil, xmaps() }, { "V", true, 8 })
  key("<Esc>")
  -- charwise: passive hint, no live labels
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  key("v")
  key("j")
  eq("charwise: hint without live labels", { hint() ~= nil, xmaps() }, { true, 0 })
  key("<Esc>")
  -- turning the hint off later (e.g. a second setup()) takes effect without re-attaching
  cfg.picker.selection_hint = false
  vim.api.nvim_win_set_cursor(0, { 3, 0 })
  key("V")
  eq("hint off via config", hint(), nil)
  key("<Esc>")
  cfg.picker.selection_hint = true
  vim.ui.input = orig_input
  cfg.picker.ui = "select"
end

-- activity text renderer ---------------------------------------------------------------------
do
  local at = require("puml.activity_text")
  local body = { "start", ":step;", "if (ok?) then (yes)", "  :continue;", "else (no)", "  :handle error;", "endif", "stop" }
  eq("activity text", at.render(body), {
    "               ●",
    "               │",
    "               ▼",
    "            ╭──────╮",
    "            │ step │",
    "            ╰──────╯",
    "               │",
    "               ▼",
    "            ╱─────╲",
    "           <  ok?  >",
    "            ╲──┬──╱",
    "       ┌───────┴────────┐",
    "       │ yes            │ no",
    "       ▼                ▼",
    "  ╭──────────╮   ╭──────────────╮",
    "  │ continue │   │ handle error │",
    "  ╰──────────╯   ╰──────────────╯",
    "       │                │",
    "       └───────┬────────┘",
    "               │",
    "               ▼",
    "               ◉",
  })
  local ascii = table.concat(at.render(body, { ascii = true }), "\n")
  eq("activity ascii", ascii:find("[\128-\255]") == nil and ascii:find("| handle error |", 1, true) ~= nil, true)
  eq("activity legacy syntax -> plantuml", at.render({ "(*) --> A" }), nil)
  -- branch ending in stop is not merged; while loops back; nested blocks parse
  local t = table.concat(at.render({
    "start", "if (a?) then (y)", ":x;", "stop", "else (n)", ":z;", "endif",
    "while (more?) is (yes)", ":w;", "endwhile (no)",
    "repeat", ":r;", "repeat while (again?) is (yes)",
    "fork", ":f1;", "fork again", ":f2;", "end fork",
    "partition P {", ":p;", "}", "switch (s)", "case (1)", ":c1;", "case (2)", ":c2;", "endswitch", "end",
  }), "\n")
  for _, w in ipairs({ "x", "z", "more?", "w", "again?", "f1", "f2", "P", "p", "c1", "c2", "⊗", "═", "◇", "─no─" }) do
    eq("activity contains " .. w, t:find(w, 1, true) ~= nil, true)
  end
end

-- catalog mindmap ------------------------------------------------------------------------------
do
  local mm = require("puml.catalog").mindmap()
  local text = table.concat(mm, "\n")
  eq("mindmap fences", { mm[1], mm[#mm] }, { "@startmindmap", "@endmindmap" })
  eq("mindmap detect", parse.detect(vim.list_slice(mm, 2, #mm - 1), "mindmap"), "mindmap")
  for _, t in ipairs({ "sequence", "class", "activity", "mindmap", "gantt" }) do
    eq("mindmap has " .. t, text:find("\n%*%* " .. t .. "\n") ~= nil, true)
  end
  local act = text:match("\n%*%* activity\n(.-)\n%*%* ")
  eq("mindmap activity: no connect", act:find("Connect") == nil, true)
  eq("mindmap creole escaped", text:find("<|~-~- extension", 1, true) ~= nil, true)
  eq("mindmap common once", select(2, text:gsub("skinparam", "")), 1)
end

-- menu ----------------------------------------------------------------------------------------
local menu = require("puml.menu")
local function keys(range)
  return table.concat(vim.tbl_map(function(a)
    return a.key
  end, menu.available(menu.context(wb, range))), "")
end
vim.api.nvim_buf_set_lines(wb, 0, -1, false, { "@startuml", "A -> B: x", "B --> A: y", "@enduml" })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
eq("menu sequence: no wrap without selection", keys(), "icpmne")
vim.api.nvim_win_set_cursor(0, { 1, 0 })
eq("menu on @startuml: no wrap", keys(), "icpmne")
eq("menu selection", keys({ 2, 3 }), "w")
eq("menu selection over @enduml", keys({ 3, 4 }), "")
vim.api.nvim_buf_set_lines(wb, 0, -1, false, { "@startuml", "start", ":a;", "stop", "@enduml" })
vim.api.nvim_win_set_cursor(0, { 3, 0 })
eq("menu activity: no connect", keys(), "ipmne")
vim.api.nvim_buf_set_lines(wb, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
eq("menu empty buffer", keys(), "pn")

vim.api.nvim_buf_set_lines(wb, 0, -1, false, { "@startuml", "A -> B: x", "B --> A: y", "@enduml" })
local shown
vim.ui.select = function(items, opts, cb)
  shown = shown or (opts.kind == "puml_menu" and vim.tbl_map(opts.format_item, items))
  cb(items[1]) -- first block (loop)
end
vim.ui.input = function(_, cb)
  cb("r")
end
menu.open(wb, { 2, 3 }) -- only one action -> straight to the block picker
eq("menu wrap range", vim.api.nvim_buf_get_lines(wb, 0, -1, false)[2], "loop r")
eq("menu skipped for single action", not shown, true)
shown = nil
vim.api.nvim_win_set_cursor(0, { 3, 0 })
vim.ui.select = function(items, opts, cb)
  shown = shown or (opts.kind == "puml_menu" and vim.tbl_map(opts.format_item, items))
end
menu.open(wb)
eq("menu label", shown and shown[1], "Insert sequence element")
-- the menu key is the only mapping (text objects are opt-in, enabled for these tests)
local maps = {}
for _, mode in ipairs({ "n", "x" }) do
  for _, m in ipairs(vim.api.nvim_buf_get_keymap(wb, mode)) do
    if (m.desc or ""):match("^puml: menu") then
      table.insert(maps, mode .. " " .. m.lhs)
    elseif (m.desc or ""):match("^puml:") and not (m.desc or ""):match("block$") then
      table.insert(maps, "unexpected " .. m.lhs)
    end
  end
end
table.sort(maps)
eq("only the menu mapping", maps, { "n \\u", "x \\u" }) -- <leader> = "\\" under -u NONE

-- textobj -------------------------------------------------------------------------------
vim.api.nvim_buf_set_lines(wb, 0, -1, false, { "@startuml", "loop x", "  A -> B", "  B -> A", "end", "C -> D", "@enduml" })
vim.api.nvim_win_set_cursor(0, { 3, 0 })
vim.cmd("normal diu")
eq("diu", vim.api.nvim_buf_get_lines(wb, 0, -1, false), { "@startuml", "loop x", "end", "C -> D", "@enduml" })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.cmd("normal dau")
eq("dau", vim.api.nvim_buf_get_lines(wb, 0, -1, false), { "@startuml", "C -> D", "@enduml" })

-- connect -----------------------------------------------------------------------------------
vim.api.nvim_buf_set_lines(wb, 0, -1, false, { "@startuml", "actor User", "participant API", "@enduml" })
vim.api.nvim_win_set_cursor(0, { 3, 0 })
local answers = { "User", "API" }
vim.ui.select = function(items, opts, cb)
  if opts.prompt:match("^Arrow") then
    return cb(items[2])
  end
  cb(table.remove(answers, 1))
end
vim.ui.input = function(_, cb)
  cb("login")
end
require("puml.actions").connect()
eq("connect seq", vim.api.nvim_buf_get_lines(wb, 0, -1, false), { "@startuml", "actor User", "participant API", "User --> API: login", "@enduml" })

vim.api.nvim_buf_set_lines(wb, 0, -1, false, { "@startuml", "class A", "class B", "@enduml" })
vim.api.nvim_win_set_cursor(0, { 3, 0 })
answers = { "B", "A" }
vim.ui.select = function(items, opts, cb)
  if opts.prompt:match("^Arrow") then
    return cb(items[2]) -- <|--
  elseif opts.prompt == "Direction" then
    return cb("up")
  end
  cb(table.remove(answers, 1))
end
vim.ui.input = function(_, cb)
  cb("")
end
require("puml.actions").connect()
eq("connect class", vim.api.nvim_buf_get_lines(wb, 0, -1, false)[4], "B <|-up- A")

-- insert snippet -----------------------------------------------------------------------------
vim.api.nvim_buf_set_lines(wb, 0, -1, false, { "@startuml", "loop x", "  A -> B", "end", "@enduml" })
vim.api.nvim_win_set_cursor(0, { 2, 0 })
vim.ui.select = orig_select
vim.ui.input = orig_input
require("puml.actions").insert("message")
wait(500, function()
  return vim.api.nvim_buf_line_count(wb) == 6
end)
eq("insert snippet", vim.api.nvim_buf_get_lines(wb, 0, -1, false)[3], "  A -> B: message")
vim.cmd("stopinsert")

-- new template -------------------------------------------------------------------------------
local nb = vim.api.nvim_create_buf(true, false)
vim.api.nvim_set_current_buf(nb)
require("puml.actions").new("state")
eq("new template", vim.api.nvim_buf_get_lines(nb, 0, 2, false), { "@startuml", "' ==== diagram-wide settings (delete what you don't need) ====" })
-- every catalog element of a type appears in its template (literal tokens of the snippet)
do
  local c = require("puml.catalog")
  local missing = {}
  for _, typ in ipairs(c.template_order) do
    if typ ~= "empty" then
      for _, it in ipairs(c.items_for(typ)) do
        local t = it.body:gsub("%${%d+|[^}]*}", " "):gsub("%${%d+:?[^}]*}", " "):gsub("%$%d", " ")
        for w in t:gmatch("%S+") do
          if not w:match("^%p$") and not c.templates[typ]:find(w, 1, true) then
            table.insert(missing, typ .. ": " .. it.label .. " (" .. w .. ")")
          end
        end
      end
    end
  end
  eq("templates cover every catalog element", missing, {})
end
eq("new ft", vim.bo[nb].filetype, "plantuml")

-- export ---------------------------------------------------------------------------------------
local dir = vim.fn.tempname()
vim.fn.mkdir(dir, "p")
vim.api.nvim_buf_set_name(nb, dir .. "/flow.puml")
require("puml.config").options.export.dir = nil
local done
local orig_notify = vim.notify
vim.notify = function(m)
  if m:match("^exported") or m:match("failed") then
    done = m
  end
end
require("puml.actions").export("svg")
wait(30000, function()
  return done ~= nil
end)
vim.notify = orig_notify
eq("export", vim.fn.filereadable(dir .. "/flow.svg"), 1)

-- review fixes ----------------------------------------------------------------------------------
do
  -- the preview's keys stay in its winbar next to the status
  local pb = vim.api.nvim_create_buf(true, false)
  vim.api.nvim_set_current_buf(pb)
  vim.bo[pb].filetype = "plantuml"
  vim.api.nvim_buf_set_lines(pb, 0, -1, false, { "@startuml", "A -> B: x", "@enduml" })
  local preview = require("puml.preview")
  preview.open(pb)
  local st = preview.state[pb]
  eq("preview winbar keeps the keys", vim.wo[st.win].winbar:find("? menu  q close", 1, true) ~= nil, true)
  preview.close(pb)
  -- narrow screen: names stay readable, the detail column is shortened instead
  local cfg = require("puml.config").options
  cfg.picker.ui = "labels"
  local cols = vim.o.columns
  vim.o.columns = 40
  local picker = require("puml.picker")
  local orig_read = picker.read_key
  local first
  picker.read_key = function()
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(w).relative ~= "" then
        first = first or vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(w), 0, 1, false)[1]
      end
    end
    return vim.keycode("<Esc>")
  end
  picker.select({ "participant with alias" }, { detail = function() return picker.snippet('participant "${1:Long Name}" as ${2:Alias}') end }, function() end)
  eq("narrow picker keeps the name", first and first:match("^ %S  participant") ~= nil, true)
  eq("narrow picker fits the screen", first and vim.fn.strdisplaywidth(first) <= vim.o.columns - 4, true)
  picker.read_key = orig_read
  vim.o.columns = cols
  cfg.picker.ui = "select"
end

print(string.format("\n%d passed, %d failed", passes, fails))
vim.cmd(fails == 0 and "qa!" or "cq!")
