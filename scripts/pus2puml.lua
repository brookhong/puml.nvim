-- puml script <-> PlantUML from the shell. The direction follows the input: PlantUML
-- (it has @startuml) is converted to a script, anything else is compiled to PlantUML.
--   nvim -l scripts/pus2puml.lua diagram.pus  > diagram.puml
--   nvim -l scripts/pus2puml.lua diagram.puml > diagram.pus
--   cat diagram.pus | nvim -l scripts/pus2puml.lua -
-- Errors go to stderr as "file:line: message" and the exit code is 1. When converting,
-- lines kept as `plantuml:` are reported on stderr (exit code 0).
-- the plugin root, wherever this is run from
local here = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h:h")
vim.opt.rtp:prepend(here)
local script = require("puml.script")

local path = arg[1]
if not path then
  io.stderr:write("usage: nvim -l scripts/pus2puml.lua FILE.pus|FILE.puml|-\n")
  os.exit(2)
end
local lines
if path == "-" then
  lines = vim.split(io.read("*a"), "\n", { plain = true })
else
  local ok, l = pcall(vim.fn.readfile, path)
  if not ok or (#l == 0 and vim.fn.filereadable(path) == 0) then
    io.stderr:write(path .. ": cannot read\n")
    os.exit(2)
  end
  lines = l
end
local name = path == "-" and "stdin" or path
local is_puml = false
for _, l in ipairs(lines) do
  if vim.trim(l):match("^@start") then
    is_puml = true
    break
  end
end
if is_puml then
  local out, notes, err = script.decompile(lines)
  if not out then
    io.stderr:write(name .. ": " .. err .. "\n")
    os.exit(1)
  end
  if #notes > 0 then
    io.stderr:write(table.concat(script.format_errors(notes, name), "\n") .. "\n")
  end
  io.write(table.concat(out, "\n") .. "\n")
  os.exit(0)
end
local out, errs = script.compile(lines)
if not out then
  io.stderr:write(table.concat(script.format_errors(errs, name), "\n") .. "\n")
  os.exit(1)
end
io.write(table.concat(out, "\n") .. "\n")
