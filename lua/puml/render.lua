-- Rendering backends: local PlantUML command or a PlantUML server (via curl).
local config = require("puml.config")

local M = {}

local function parse_cli_error(stderr)
  local lines = vim.split(stderr or "", "\n", { trimempty = true })
  for i, l in ipairs(lines) do
    if l == "ERROR" and lines[i + 1] and lines[i + 1]:match("^%d+$") then
      return { line = tonumber(lines[i + 1]), message = lines[i + 2] or "Syntax error" }
    end
  end
  if #lines > 0 then
    return { message = table.concat(lines, "\n") }
  end
end

local function hex(s)
  return (s:gsub(".", function(c)
    return string.format("%02x", c:byte())
  end))
end

local function write_file(path, data)
  local f = assert(io.open(path, "wb"))
  f:write(data)
  f:close()
end

local function read_file(path)
  local f = io.open(path, "rb")
  if not f then
    return nil
  end
  local d = f:read("*a")
  f:close()
  return d
end

--- Render PlantUML source.
--- @param input string[] lines (must include @start/@end)
--- @param fmt string PlantUML format: "utxt", "txt", "png", "svg", ...
--- @param out string|nil when given, output is written to this path
--- @param cb fun(res: { ok: boolean, data: string|nil, path: string|nil, err: table|nil, ms: integer })
--- @return vim.SystemObj|nil
function M.render(input, fmt, out, cb)
  local opts = config.options
  local text = table.concat(input, "\n") .. "\n"
  local t0 = vim.uv.hrtime()
  local function done(res)
    res.ms = math.floor((vim.uv.hrtime() - t0) / 1e6)
    vim.schedule(function()
      cb(res)
    end)
  end

  if opts.server and opts.server ~= "" then
    local url = opts.server:gsub("/+$", "") .. "/" .. fmt .. "/~h" .. hex(text)
    local target = out or vim.fn.tempname()
    local ok, job = pcall(vim.system, { opts.curl, "-sS", "-D", "-", "-o", target, url }, { text = true }, function(r)
      if r.code ~= 0 then
        return done({ ok = false, err = { message = "curl: " .. (r.stderr or ""):gsub("%s+$", "") } })
      end
      local headers = r.stdout or ""
      local status = tonumber(headers:match("HTTP/[%d%.]+%s+(%d+)") or "0")
      local emsg = headers:match("[Xx]%-[Pp]lant[Uu][Mm][Ll]%-[Dd]iagram%-[Ee]rror:%s*([^\r\n]+)")
      local eline = headers:match("[Xx]%-[Pp]lant[Uu][Mm][Ll]%-[Dd]iagram%-[Ee]rror%-[Ll]ine:%s*(%d+)")
      local data = (not out) and read_file(target) or nil
      if not out then
        os.remove(target)
      end
      if emsg or status >= 400 then
        return done({
          ok = false,
          data = data,
          -- the server reports 1-based lines; normalise to 0-based like the CLI
          err = { line = eline and (tonumber(eline) - 1) or nil, message = emsg or ("HTTP " .. status) },
        })
      end
      done({ ok = true, data = data, path = out })
    end)
    if not ok then
      done({ ok = false, err = { message = "failed to run curl: " .. tostring(job) } })
      return nil
    end
    return job
  end

  local cmd = vim.list_extend(vim.deepcopy(opts.cmd), { "-pipe", "-charset", "UTF-8", "-t" .. fmt })
  local binary = not (fmt == "txt" or fmt == "utxt" or fmt == "svg")
  local ok, job = pcall(vim.system, cmd, { stdin = text, text = not binary }, function(r)
    if r.signal and r.signal ~= 0 then
      return done({ ok = false, cancelled = true })
    end
    local err = r.code ~= 0 and (parse_cli_error(r.stderr) or { message = "plantuml exited with " .. r.code }) or nil
    if out then
      if not err then
        local wok, werr = pcall(write_file, out, r.stdout or "")
        if not wok then
          return done({ ok = false, err = { message = tostring(werr) } })
        end
      end
      return done({ ok = err == nil, path = out, err = err })
    end
    done({ ok = err == nil, data = r.stdout, err = err })
  end)
  if not ok then
    done({ ok = false, err = { message = "failed to run " .. table.concat(opts.cmd, " ") .. ": " .. tostring(job) } })
    return nil
  end
  return job
end

return M
