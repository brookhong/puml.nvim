-- Run: nvim --headless -u NONE -l tests/run.lua
vim.opt.rtp:prepend(vim.fn.getcwd())
vim.cmd("runtime plugin/puml.lua")
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
require("puml").setup({})

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
eq("new template", vim.api.nvim_buf_get_lines(nb, 0, 2, false), { "@startuml", "[*] --> Idle" })
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

print(string.format("\n%d passed, %d failed", passes, fails))
vim.cmd(fails == 0 and "qa!" or "cq!")
