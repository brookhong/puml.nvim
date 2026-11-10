-- Text objects for PlantUML blocks (loop/alt/if/while/fork/{...}/note ...).
local util = require("puml.util")
local parse = require("puml.parse")

local M = {}

--- Select the block around the cursor. `kind` = "i" (inner) or "a" (around).
function M.select(kind)
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  local d = util.current(buf, row)
  if not d then
    return
  end
  local rel = row - d.body_s + 1
  local blocks = parse.enclosing(d.body, rel)
  local b = blocks[math.min(vim.v.count1, #blocks)]
  local s, e
  if b then
    s, e = b.s + d.body_s - 1, b.e + d.body_s - 1
    if kind == "i" then
      s, e = s + 1, e - 1
    end
  else
    -- no enclosing block: the whole diagram body
    s, e = d.body_s, d.body_e
    if kind == "a" and not d.wrapped then
      s, e = d.s, d.e
    end
  end
  if e < s then
    return -- empty block
  end
  vim.api.nvim_win_set_cursor(0, { s, 0 })
  vim.cmd("normal! V")
  vim.api.nvim_win_set_cursor(0, { e, 0 })
end

return M
