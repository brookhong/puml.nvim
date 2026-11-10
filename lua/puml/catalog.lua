-- Catalog of insertable elements, arrows, wrap-blocks and templates per diagram type.
-- Snippet bodies use LSP snippet syntax (expanded with vim.snippet). `\t` = one indent level.
local M = {}

local common = {
  { label = "title", body = "title ${1:Title}" },
  { label = "note (floating)", body = 'note "${1:text}" as ${2:N1}' },
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
    { label = "history", body = "[H]" },
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
local brace = function(kw)
  return { label = kw, open = kw .. " %s {", close = "}", prompt = kw .. " name", default = "name" }
end

M.wraps = {
  sequence = {
    { label = "loop", open = "loop %s", close = "end", prompt = "loop condition" },
    { label = "alt / else", open = "alt %s", mid = { "else" }, close = "end", prompt = "if condition" },
    { label = "opt", open = "opt %s", close = "end", prompt = "opt condition" },
    { label = "par", open = "par", mid = { "else" }, close = "end" },
    { label = "break", open = "break %s", close = "end", prompt = "break condition" },
    { label = "critical", open = "critical %s", close = "end", prompt = "critical section" },
    { label = "group", open = "group %s", close = "end", prompt = "group label" },
    { label = "box", open = 'box "%s"', close = "end box", prompt = "box title" },
    { label = "activate / deactivate", open = "activate %s", close = "deactivate %s", prompt = "participant" },
  },
  activity = {
    { label = "if / else", open = "if (%s?) then (yes)", mid = { "else (no)" }, close = "endif", prompt = "condition" },
    { label = "if (no else)", open = "if (%s?) then (yes)", close = "endif", prompt = "condition" },
    { label = "while", open = "while (%s?) is (yes)", close = "endwhile (no)", prompt = "condition" },
    { label = "repeat", open = "repeat", close = "repeat while (%s?) is (yes)", prompt = "condition" },
    { label = "fork", open = "fork", mid = { "fork again" }, close = "end fork" },
    { label = "split", open = "split", mid = { "split again" }, close = "end split" },
    { label = "partition", open = "partition %s {", close = "}", prompt = "partition name" },
    { label = "group", open = "group %s", close = "end group", prompt = "group name" },
  },
  structural = {
    brace("package"),
    brace("namespace"),
    brace("rectangle"),
    brace("node"),
    brace("folder"),
    brace("frame"),
    brace("cloud"),
    brace("component"),
    { label = "together", open = "together {", close = "}" },
  },
  state = {
    { label = "composite state", open = "state %s {", close = "}", prompt = "state name" },
  },
}

-- Templates for :PumlNew
M.templates = {
  sequence = [[
@startuml
actor User
participant API
database DB

User -> API: request
API -> DB: query
DB --> API: rows
API --> User: response
@enduml]],
  class = [[
@startuml
class Animal {
  +name: String
  +speak(): void
}
class Dog
Animal <|-- Dog
@enduml]],
  activity = [[
@startuml
start
:step;
if (ok?) then (yes)
  :continue;
else (no)
  :handle error;
endif
stop
@enduml]],
  usecase = [[
@startuml
left to right direction
actor User
rectangle System {
  (Login)
}
User --> (Login)
@enduml]],
  component = [[
@startuml
[Frontend] --> [Backend]
database DB
[Backend] --> DB
@enduml]],
  state = [[
@startuml
[*] --> Idle
Idle --> Running : start
Running --> Idle : stop
Running --> [*]
@enduml]],
  object = [[
@startuml
object user {
  name = "Alice"
}
object order
user --> order
@enduml]],
  mindmap = [[
@startmindmap
* Root
** Branch A
*** Leaf
** Branch B
@endmindmap]],
  wbs = [[
@startwbs
* Project
** Phase 1
*** Task
** Phase 2
@endwbs]],
  gantt = [[
@startgantt
Project starts 2025-01-01
[Design] requires 5 days
[Build] requires 10 days
[Build] starts at [Design]'s end
@endgantt]],
  empty = [[
@startuml
${0}
@enduml]],
}

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
  vim.list_extend(list, common)
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

return M
