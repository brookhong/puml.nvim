local M = {}

function M.check()
  local h = vim.health
  local config = require("puml.config").options
  h.start("puml.nvim")
  if vim.fn.has("nvim-0.10") == 1 then
    h.ok("Neovim >= 0.10")
  else
    h.error("Neovim >= 0.10 is required (vim.system, vim.snippet)")
  end
  if config.server and config.server ~= "" then
    h.info("Using PlantUML server: " .. config.server)
    if vim.fn.executable(config.curl) == 1 then
      h.ok("curl found: " .. vim.fn.exepath(config.curl))
    else
      h.error("curl not found (required for server backend)")
    end
  else
    local exe = config.cmd[1]
    if vim.fn.executable(exe) == 1 then
      local r = vim.system(vim.list_extend(vim.deepcopy(config.cmd), { "-version" }), { text = true }):wait(20000)
      local v = (r.stdout or ""):match("PlantUML version ([^\n]+)")
      h.ok("PlantUML: " .. table.concat(config.cmd, " ") .. (v and (" (" .. v .. ")") or ""))
    else
      h.error("'" .. exe .. "' not found; set `cmd` in setup() (e.g. { 'java', '-jar', '/path/plantuml.jar' }) or `server`")
    end
  end
  if pcall(require, "cmp") then
    h.ok("nvim-cmp found; add { name = 'puml' } to your cmp sources")
  else
    h.info("nvim-cmp not found; omnifunc (<C-x><C-o>) completes names")
  end
end

return M
