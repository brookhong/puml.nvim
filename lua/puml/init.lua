local config = require("puml.config")
local util = require("puml.util")

local M = {}

M._setup_done = false

function M.setup(opts)
  config.setup(opts)
  M._setup_done = true
  if config.options.cmp then
    require("puml.complete").register_cmp()
  end
  -- re-attach to already-open buffers with the new options
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      local ft = vim.bo[buf].filetype
      if ft == "plantuml" or util.is_markdown(buf) then
        M.attach(buf, true)
      end
    end
  end
end

local function map(buf, mode, lhs, rhs, desc, extra)
  vim.keymap.set(mode, lhs, rhs, vim.tbl_extend("force", { buffer = buf, silent = true, desc = "puml: " .. desc }, extra or {}))
end

--- Attach keymaps/autocmds/options to a PlantUML (or markdown) buffer.
function M.attach(buf, force)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if vim.b[buf].puml_attached and not force then
    return
  end
  vim.b[buf].puml_attached = true
  if config.options.cmp then
    require("puml.complete").register_cmp()
  end
  local preview = require("puml.preview")
  local actions = require("puml.actions")
  preview.attach(buf)

  if vim.bo[buf].filetype == "plantuml" then
    vim.bo[buf].omnifunc = "v:lua.require'puml.complete'.omnifunc"
  end

  local km = config.options.keymaps
  if km and km.prefix then
    local p = km.prefix
    map(buf, "n", p .. "p", function() preview.toggle(buf) end, "toggle preview")
    map(buf, "n", p .. "r", function() preview.render(buf, { force = true }) end, "render now")
    map(buf, "n", p .. "m", function() preview.cycle_mode(buf) end, "cycle preview mode (auto/text/image)")
    map(buf, "n", p .. "i", function() actions.insert() end, "insert element")
    map(buf, "n", p .. "c", function() actions.connect() end, "connect two nodes")
    map(buf, "n", p .. "w", actions.wrap_operator, "wrap {motion} in block", { expr = true })
    map(buf, "n", p .. "ww", function() local r = vim.fn.line("."); actions.wrap_range(r, r) end, "wrap line in block")
    map(buf, "x", p .. "w", actions.wrap_visual, "wrap selection in block")
    map(buf, "n", p .. "n", function() actions.new() end, "new diagram from template")
    map(buf, "n", p .. "e", function() actions.export() end, "export diagram")
  end
  local to = km and km.textobjects
  if to then
    local cmd = ":<C-u>lua require('puml.textobj').select('%s')<CR>"
    if to.inner then
      map(buf, { "o", "x" }, to.inner, cmd:format("i"), "inner block")
    end
    if to.outer then
      map(buf, { "o", "x" }, to.outer, cmd:format("a"), "around block")
    end
  end
end

--- :Puml [file]  — open a diagram (or a fresh one) together with its preview.
function M.open(file)
  local preview = require("puml.preview")
  if file and file ~= "" then
    vim.cmd.edit(vim.fn.fnameescape(file))
    local buf = vim.api.nvim_get_current_buf()
    if vim.bo[buf].filetype ~= "plantuml" and not util.is_markdown(buf) then
      vim.bo[buf].filetype = "plantuml"
    end
    M.attach(buf)
    local empty = vim.api.nvim_buf_line_count(buf) == 1 and vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] == ""
    preview.open(buf)
    if empty then
      require("puml.actions").new()
    end
    return
  end
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype == "plantuml" or util.is_markdown(buf) then
    M.attach(buf)
    return preview.toggle(buf)
  end
  vim.cmd.enew()
  buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].filetype = "plantuml"
  M.attach(buf)
  preview.open(buf)
  require("puml.actions").new()
end

return M
