-- Catalog of insertable elements, arrows, wrap-blocks and templates per diagram type.
-- Snippet bodies use LSP snippet syntax (expanded with vim.snippet). `\t` = one indent level.
local M = {}

local common = {
  { label = "title", body = "title ${1:Title}" },
  -- `note "…" as N` is not valid in sequence and activity diagrams
  { label = "note (floating)", body = 'note "${1:text}" as ${2:N1}', not_in = { sequence = true, activity = true } },
  { label = "skinparam", body = "skinparam ${1:monochrome} ${2:true}" },
  { label = "theme", body = "!theme ${1:plain}" },
  { label = "header", body = "header ${1:text}" },
  { label = "footer", body = "footer ${1:text}" },
  { label = "caption", body = "caption ${1:text}" },
  { label = "legend", body = "legend ${1:right}\n\t${0:text}\nendlegend" },
  { label = "comment", body = "' ${0}" },
}

local layout = {
  { label = "left to right direction", body = "left to right direction" },
  { label = "top to bottom direction", body = "top to bottom direction" },
  { label = "hide empty members", body = "hide empty members" },
}

M.items = {
  sequence = {
    { label = "participant", body = "participant ${1:Name}" },
    { label = "participant with alias", body = 'participant "${1:Long Name}" as ${2:Alias}' },
    { label = "actor", body = "actor ${1:User}" },
    { label = "boundary", body = "boundary ${1:Boundary}" },
    { label = "control", body = "control ${1:Control}" },
    { label = "entity", body = "entity ${1:Entity}" },
    { label = "database", body = "database ${1:DB}" },
    { label = "collections", body = "collections ${1:Items}" },
    { label = "queue", body = "queue ${1:Queue}" },
    { label = "message", body = "${1:A} -> ${2:B}: ${0:message}" },
    { label = "reply message", body = "${1:B} --> ${2:A}: ${0:reply}" },
    { label = "async message", body = "${1:A} ->> ${2:B}: ${0:message}" },
    { label = "self message", body = "${1:A} -> ${1}: ${0:action}" },
    { label = "return", body = "return ${0:value}" },
    { label = "loop", body = "loop ${1:condition}\n\t${0}\nend" },
    { label = "alt / else", body = "alt ${1:condition}\n\t${2}\nelse ${3:otherwise}\n\t${0}\nend" },
    { label = "opt", body = "opt ${1:condition}\n\t${0}\nend" },
    { label = "par", body = "par ${1:first}\n\t${2}\nelse ${3:second}\n\t${0}\nend" },
    { label = "break", body = "break ${1:condition}\n\t${0}\nend" },
    { label = "critical", body = "critical ${1:section}\n\t${0}\nend" },
    { label = "group", body = "group ${1:label}\n\t${0}\nend" },
    { label = "box (participants)", body = 'box "${1:Group}" ${2:#LightBlue}\n\tparticipant ${0:A}\nend box' },
    { label = "note left", body = "note left: ${0:text}" },
    { label = "note right", body = "note right: ${0:text}" },
    { label = "note over", body = "note over ${1:A}, ${2:B}: ${0:text}" },
    { label = "note (multi-line)", body = "note over ${1:A}\n\t${0:text}\nend note" },
    { label = "ref over", body = "ref over ${1:A}, ${2:B}: ${0:see other diagram}" },
    { label = "activate", body = "activate ${0:A}" },
    { label = "deactivate", body = "deactivate ${0:A}" },
    { label = "create", body = "create ${0:B}" },
    { label = "destroy", body = "destroy ${0:B}" },
    { label = "autonumber", body = "autonumber" },
    { label = "divider", body = "== ${0:Section} ==" },
    { label = "delay", body = "...${0:later}..." },
    { label = "space", body = "|||" },
    { label = "hide footbox", body = "hide footbox" },
  },
  class = {
    { label = "class", body = "class ${1:Name}" },
    { label = "class with members", body = "class ${1:Name} {\n\t${2:-field: Type}\n\t${0:+method(): void}\n}" },
    { label = "abstract class", body = "abstract class ${1:Name}" },
    { label = "interface", body = "interface ${1:Name}" },
    { label = "enum", body = "enum ${1:Name} {\n\t${0:VALUE}\n}" },
    { label = "annotation", body = "annotation ${1:Name}" },
    { label = "field", body = "${1:-}${2:name}: ${0:Type}" },
    { label = "method", body = "${1:+}${2:name}(${3}): ${0:void}" },
    { label = "package", body = "package ${1:name} {\n\t${0}\n}" },
    { label = "namespace", body = "namespace ${1:name} {\n\t${0}\n}" },
    { label = "extension", body = "${1:Parent} <|-- ${0:Child}" },
    { label = "implementation", body = "${1:Interface} <|.. ${0:Impl}" },
    { label = "composition", body = "${1:Whole} *-- ${0:Part}" },
    { label = "aggregation", body = "${1:Whole} o-- ${0:Part}" },
    { label = "association", body = "${1:A} --> ${0:B}" },
    { label = "dependency", body = "${1:A} ..> ${0:B}" },
    { label = "relation with cardinality", body = '${1:A} "${2:1}" --> "${3:*}" ${4:B} : ${0:label}' },
    { label = "note on class", body = "note ${1|right,left,top,bottom|} of ${2:Class}: ${0:text}" },
  },
  activity = {
    { label = "start", body = "start" },
    { label = "stop", body = "stop" },
    { label = "end", body = "end" },
    { label = "action", body = ":${0:action};" },
    { label = "if / else", body = "if (${1:condition}?) then (${2:yes})\n\t${3}\nelse (${4:no})\n\t${0}\nendif" },
    { label = "if / elseif / else", body = "if (${1:a}?) then (yes)\n\t${2}\nelseif (${3:b}?) then (yes)\n\t${4}\nelse (no)\n\t${0}\nendif" },
    { label = "switch", body = "switch (${1:value}?)\ncase (${2:A})\n\t${3}\ncase (${4:B})\n\t${0}\nendswitch" },
    { label = "while", body = "while (${1:condition}?) is (${2:yes})\n\t${0}\nendwhile (${3:no})" },
    { label = "repeat", body = "repeat\n\t${0}\nrepeat while (${1:condition}?) is (${2:yes})" },
    { label = "fork", body = "fork\n\t${1}\nfork again\n\t${0}\nend fork" },
    { label = "split", body = "split\n\t${1}\nsplit again\n\t${0}\nend split" },
    { label = "swimlane", body = "|${0:Lane}|" },
    { label = "partition", body = "partition ${1:Name} {\n\t${0}\n}" },
    { label = "group", body = "group ${1:Name}\n\t${0}\nend group" },
    { label = "arrow label", body = "-> ${0:label};" },
    { label = "detach", body = "detach" },
    { label = "kill", body = "kill" },
    { label = "note", body = "note ${1|right,left|}: ${0:text}" },
    { label = "connector", body = "(${0:A})" },
  },
  usecase = {
    { label = "actor", body = "actor ${1:User}" },
    { label = "actor with alias", body = 'actor "${1:Long Name}" as ${2:A}' },
    { label = "usecase", body = "(${0:Use case})" },
    { label = "usecase with alias", body = 'usecase "${1:Use case}" as ${2:UC1}' },
    { label = "system boundary", body = "rectangle ${1:System} {\n\t${0}\n}" },
    { label = "package", body = "package ${1:name} {\n\t${0}\n}" },
    { label = "association", body = "${1:User} --> ${0:(Use case)}" },
    { label = "include", body = "${1:(A)} .> ${2:(B)} : include" },
    { label = "extends", body = "${1:(A)} .> ${2:(B)} : extends" },
    { label = "generalization", body = "${1:Parent} <|-- ${0:Child}" },
    { label = "note", body = "note ${1|right,left,top,bottom|} of ${2:X}: ${0:text}" },
  },
  component = {
    { label = "component", body = "[${0:Component}]" },
    { label = "component with alias", body = 'component "${1:Name}" as ${2:C}' },
    { label = "interface", body = '() "${1:Interface}" as ${2:I}' },
    { label = "node", body = "node ${1:Node} {\n\t${0}\n}" },
    { label = "cloud", body = "cloud ${1:Cloud} {\n\t${0}\n}" },
    { label = "database", body = "database ${1:DB}" },
    { label = "queue", body = "queue ${1:Queue}" },
    { label = "artifact", body = "artifact ${1:Artifact}" },
    { label = "storage", body = "storage ${1:Storage}" },
    { label = "package", body = "package ${1:name} {\n\t${0}\n}" },
    { label = "folder", body = "folder ${1:name} {\n\t${0}\n}" },
    { label = "frame", body = "frame ${1:name} {\n\t${0}\n}" },
    { label = "rectangle", body = "rectangle ${1:name} {\n\t${0}\n}" },
    { label = "actor", body = "actor ${1:User}" },
    { label = "port", body = "port ${0:p1}" },
    { label = "link", body = "${1:A} --> ${0:B}" },
    { label = "dependency", body = "${1:A} ..> ${0:B} : use" },
    { label = "note", body = "note ${1|right,left,top,bottom|} of ${2:X}: ${0:text}" },
  },
  state = {
    { label = "state", body = "state ${1:State}" },
    { label = "state with description", body = "${1:State} : ${0:description}" },
    { label = "initial", body = "[*] --> ${0:State}" },
    { label = "final", body = "${1:State} --> [*]" },
    { label = "transition", body = "${1:A} --> ${2:B} : ${0:event}" },
    { label = "composite state", body = "state ${1:Composite} {\n\t[*] --> ${0:Inner}\n}" },
    { label = "concurrent region", body = "--" },
    { label = "choice", body = "state ${1:choice} <<choice>>" },
    { label = "fork", body = "state ${1:fork} <<fork>>" },
    { label = "join", body = "state ${1:join} <<join>>" },
    { label = "history", body = "${1:State} --> ${2:Composite}[H]" },
    { label = "note", body = "note ${1|right,left|} of ${2:State}: ${0:text}" },
  },
  object = {
    { label = "object", body = "object ${1:name}" },
    { label = "object with fields", body = "object ${1:name} {\n\t${0:field = value}\n}" },
    { label = "map", body = "map ${1:Name} {\n\t${2:key} => ${0:value}\n}" },
    { label = "link", body = "${1:a} --> ${0:b}" },
  },
  mindmap = {
    { label = "root", body = "* ${0:root}" },
    { label = "child", body = "** ${0:child}" },
    { label = "grandchild", body = "*** ${0:item}" },
    { label = "left side", body = "left side" },
    { label = "right side", body = "right side" },
    { label = "boxless", body = "**_ ${0:item}" },
  },
  wbs = {
    { label = "root", body = "* ${0:root}" },
    { label = "child", body = "** ${0:child}" },
    { label = "left child", body = "**< ${0:child}" },
    { label = "right child", body = "**> ${0:child}" },
  },
  gantt = {
    { label = "project start", body = "Project starts ${0:2025-01-01}" },
    { label = "task", body = "[${1:Task}] requires ${0:5} days" },
    { label = "task after", body = "[${1:B}] starts at [${0:A}]'s end" },
    { label = "milestone", body = "[${1:Milestone}] happens at [${0:A}]'s end" },
    { label = "completion", body = "[${1:Task}] is ${0:50}% completed" },
    { label = "closed days", body = "saturday are closed\nsunday are closed" },
  },
}

-- Arrow choices for "connect", per type.
M.arrows = {
  sequence = {
    { label = "->   sync", arrow = "->" },
    { label = "-->  reply", arrow = "-->" },
    { label = "->>  async", arrow = "->>" },
    { label = "->x  lost", arrow = "->x" },
    { label = "<->  bidirectional", arrow = "<->" },
    { label = "->o  to circle", arrow = "->o" },
  },
  class = {
    { label = "-->   association", arrow = "-->" },
    { label = "<|--  extension", arrow = "<|--" },
    { label = "<|..  implementation", arrow = "<|.." },
    { label = "*--   composition", arrow = "*--" },
    { label = "o--   aggregation", arrow = "o--" },
    { label = "..>   dependency", arrow = "..>" },
    { label = "--    link", arrow = "--" },
    { label = "..    dashed link", arrow = ".." },
  },
  default = {
    { label = "-->  arrow", arrow = "-->" },
    { label = "..>  dashed arrow", arrow = "..>" },
    { label = "--   line", arrow = "--" },
    { label = "..   dashed line", arrow = ".." },
    { label = "<--> bidirectional", arrow = "<-->" },
    { label = "<|-- generalization", arrow = "<|--" },
  },
}

-- Wrap blocks per type. `%s` in open/close lines is replaced with the user's answer to `prompt`.
-- `desc` is shown next to the label in the hint and the picker.
local brace = function(kw, desc)
  return { label = kw, open = kw .. " %s {", close = "}", prompt = kw .. " name", default = "name", desc = desc }
end

M.wraps = {
  sequence = {
    { label = "loop", open = "loop %s", close = "end", prompt = "loop condition", desc = "repeat while {condition} holds" },
    { label = "alt / else", open = "alt %s", mid = { "else" }, close = "end", prompt = "if condition", desc = "if {condition}, else the other branch" },
    { label = "opt", open = "opt %s", close = "end", prompt = "opt condition", desc = "only if {condition} holds" },
    { label = "par", open = "par", mid = { "else" }, close = "end", desc = "branches run in parallel" },
    { label = "break", open = "break %s", close = "end", prompt = "break condition", desc = "if {condition}: this, then stop" },
    { label = "critical", open = "critical %s", close = "end", prompt = "critical section", desc = "{section} runs without interruption" },
    { label = "group", open = "group %s", close = "end", prompt = "group label", desc = "a frame labelled {label}" },
    { label = "box", open = 'box "%s"', close = "end box", prompt = "box title", desc = "a box titled {title} around them" },
    { label = "activate / deactivate", open = "activate %s", close = "deactivate %s", prompt = "participant", desc = "mark {participant}'s lifeline active" },
  },
  activity = {
    { label = "if / else", open = "if (%s?) then (yes)", mid = { "else (no)" }, close = "endif", prompt = "condition", desc = "if {condition}: yes, else no" },
    { label = "if (no else)", open = "if (%s?) then (yes)", close = "endif", prompt = "condition", desc = "only if {condition} holds" },
    { label = "while", open = "while (%s?) is (yes)", close = "endwhile (no)", prompt = "condition", desc = "loop while {condition}, test first" },
    { label = "repeat", open = "repeat", close = "repeat while (%s?) is (yes)", prompt = "condition", desc = "loop while {condition}, test after" },
    { label = "fork", open = "fork", mid = { "fork again" }, close = "end fork", desc = "parallel branches, then join" },
    { label = "split", open = "split", mid = { "split again" }, close = "end split", desc = "parallel branches, no join" },
    { label = "partition", open = "partition %s {", close = "}", prompt = "partition name", desc = "a frame of steps named {name}" },
    { label = "group", open = "group %s", close = "end group", prompt = "group name", desc = "a frame labelled {name}" },
  },
  structural = {
    brace("package", "a tabbed folder named {name}"),
    brace("namespace", "names inside get {name}. prefix"),
    brace("rectangle", "a plain box named {name}"),
    brace("node", "a machine/device {name} (3D box)"),
    brace("folder", "a folder named {name}"),
    brace("frame", "a frame tagged {name}"),
    brace("cloud", "a cloud named {name}"),
    brace("component", "a component {name} holding these"),
    { label = "together", open = "together {", close = "}", desc = "keep them side by side (layout)" },
  },
  state = {
    { label = "composite state", open = "state %s {", close = "}", prompt = "state name", desc = "a state {name} made of sub-states" },
  },
}

-- One-line description per template, for the "New diagram" picker.
M.template_desc = {
  sequence = "messages between participants over time",
  class = "classes, their members and relations",
  activity = "a flow of steps with branches and loops",
  usecase = "actors and what they can do with a system",
  component = "components and how they depend on each other",
  state = "states and the transitions between them",
  object = "instances and their links at one moment",
  mindmap = "ideas branching out from a root",
  wbs = "work breakdown: a project split into tasks",
  gantt = "tasks on a timeline",
  empty = "an empty @startuml … @enduml",
}

-- Templates for :PumlNew: every element of the type, see templates.lua
M.templates = require("puml.templates")

M.template_order = { "sequence", "class", "activity", "usecase", "component", "state", "object", "mindmap", "wbs", "gantt", "empty" }

local structural = { class = true, usecase = true, component = true, object = true }

function M.items_for(typ)
  local user = require("puml.config").options.catalog or {}
  local list = {}
  vim.list_extend(list, user[typ] or {})
  vim.list_extend(list, M.items[typ] or {})
  if structural[typ] then
    vim.list_extend(list, layout)
  end
  if M.items[typ] == nil or typ == "mindmap" or typ == "wbs" or typ == "gantt" then
    return list
  end
  vim.list_extend(list, user.common or {})
  for _, it in ipairs(common) do
    if not (it.not_in and it.not_in[typ]) then
      table.insert(list, it)
    end
  end
  return list
end

function M.arrows_for(typ)
  return M.arrows[typ] or M.arrows.default
end

function M.wraps_for(typ)
  if structural[typ] then
    return M.wraps.structural
  end
  return M.wraps[typ] or {}
end

function M.slug(label)
  return (label:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", ""))
end

function M.find(typ, id)
  for _, it in ipairs(M.items_for(typ)) do
    if M.slug(it.label) == id or it.label == id then
      return it
    end
  end
end

--- PlantUML mindmap of diagram type -> available actions/items, generated
--- from this catalog (including user `catalog` config), so it never goes stale.
--- One multi-line box per action (keeps the image small); shared items are shown once.
--- @return string[] lines
function M.mindmap()
  local user = require("puml.config").options.catalog or {}
  local can_connect = require("puml.actions").can_connect
  local shared_list = vim.list_extend(vim.list_extend({}, user.common or {}), common)
  local shared = {}
  for _, it in ipairs(shared_list) do
    shared[it.label] = true
  end
  local out = { "@startmindmap", "* puml.nvim" }
  -- collapse whitespace and escape creole markup (`--` strike, `**` bold, `//`, `__`, `""`)
  local function clean(t)
    return (t:gsub("%s+", " "):gsub('[-*/_"]', "~%0"))
  end
  local function branch(level, title, list, extra)
    if #list == 0 then
      return
    end
    -- multi-line node, a few items per row
    table.insert(out, string.rep("*", level) .. ":<b>" .. title .. "</b> (" .. #list .. ")")
    local row = {}
    local function flush()
      if #row > 0 then
        table.insert(out, table.concat(row, "  ·  "))
        row = {}
      end
    end
    for _, x in ipairs(list) do
      table.insert(row, clean(x.label))
      if #table.concat(row, "  ·  ") > 48 then
        flush()
      end
    end
    flush()
    if extra then
      table.insert(out, extra)
    end
    out[#out] = out[#out] .. ";"
  end
  local types = vim.tbl_filter(function(t)
    return M.templates[t] and t ~= "empty"
  end, M.template_order)
  -- which shared items each type gets (some are left out per type, see `not_in`)
  local users = {} -- shared label -> types using it
  for i, typ in ipairs(types) do
    if i == math.floor(#types / 2) + 1 then
      table.insert(out, "left side")
    end
    table.insert(out, "** " .. typ)
    local items, has_shared = {}, false
    for _, it in ipairs(M.items_for(typ)) do
      if shared[it.label] then
        has_shared = true
        users[it.label] = users[it.label] or {}
        table.insert(users[it.label], typ)
      else
        table.insert(items, it)
      end
    end
    branch(3, "Insert", items, has_shared and "<i>+ common items</i>" or nil)
    if can_connect(typ) then
      branch(3, "Connect", M.arrows_for(typ))
    end
    branch(3, "Wrap", M.wraps_for(typ))
  end
  -- shared items grouped by the set of types that get them
  local groups, order = {}, {}
  for _, it in ipairs(shared_list) do
    local ts = users[it.label]
    if ts then
      local key = table.concat(ts, ", ")
      if not groups[key] then
        groups[key] = {}
        table.insert(order, key)
      end
      table.insert(groups[key], it)
    end
  end
  if #order > 0 then
    table.insert(out, "** common items")
    for _, key in ipairs(order) do
      branch(3, "Insert in " .. key, groups[key])
    end
  end
  table.insert(out, "@endmindmap")
  return out
end

return M
