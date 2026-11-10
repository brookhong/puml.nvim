" Minimal PlantUML syntax highlighting (used when no other plantuml syntax is installed)
if exists("b:current_syntax")
  finish
endif

syntax case ignore

syntax match pumlDirective /^\s*@\(start\|end\)\w*/
syntax match pumlPreproc /^\s*!\w\+/
syntax keyword pumlKeyword participant actor boundary control entity database collections queue
syntax keyword pumlKeyword class interface abstract enum annotation package namespace object map
syntax keyword pumlKeyword component node cloud artifact folder frame storage rectangle usecase state card agent port
syntax keyword pumlKeyword as of on over left right top bottom up down
syntax keyword pumlBlock loop alt else opt par break critical group end box ref
syntax keyword pumlBlock if then elseif endif while endwhile repeat fork again merge split switch case endswitch partition
syntax keyword pumlStatement start stop detach kill return activate deactivate destroy create autonumber
syntax keyword pumlStatement title header footer caption legend endlegend skinparam hide show note
syntax match pumlArrow /[<*o#x|}+^]*[-.=~]\+\(\[[^\]]*\]\)\?\(up\|down\|left\|right\|u\|d\|l\|r\)\?[-.=~]*[>*o#x|{+^]\+/
syntax match pumlArrow /\s\zs[-.]\{2,}\ze\s/
syntax match pumlStereotype /<<[^>]*>>/
syntax match pumlColor /#\w\+/
syntax region pumlString start=/"/ skip=/\\"/ end=/"/ oneline
syntax match pumlLabel /:\s*\zs.*$/ contains=pumlString
syntax match pumlActivity /^\s*:.*;\s*$/
syntax match pumlComment /^\s*'.*$/
syntax region pumlComment start=/\/'/ end=/'\//

hi def link pumlDirective PreProc
hi def link pumlPreproc PreProc
hi def link pumlKeyword Keyword
hi def link pumlBlock Conditional
hi def link pumlStatement Statement
hi def link pumlArrow Operator
hi def link pumlStereotype Type
hi def link pumlColor Constant
hi def link pumlString String
hi def link pumlLabel String
hi def link pumlActivity Function
hi def link pumlComment Comment

let b:current_syntax = "plantuml"
