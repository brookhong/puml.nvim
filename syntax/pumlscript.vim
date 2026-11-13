" puml script (.pus) syntax highlighting. See docs/script.md.
" Highlights what the compiler (lua/puml/script.lua) recognises, so a line that isn't
" highlighted as a keyword, message or declaration is read as an activity action.
if exists("b:current_syntax")
  finish
endif

" ---- plantuml: passthrough lines are highlighted as PlantUML ----------------------
syntax include @pusPlantuml syntax/plantuml.vim
unlet! b:current_syntax
syntax case match

" ---- comments, strings, colours ---------------------------------------------------
syntax match pusComment /^\s*#.*$/ contains=pusTodo
syntax match pusComment /\s\zs#\s.*$/ contains=pusTodo
syntax match pusTodo /\<\%(TODO\|FIXME\|XXX\|NOTE\)\>/ contained
syntax region pusString start=/"/ skip=/\\"/ end=/"/ oneline
syntax match pusColor /#\x\{3,6}\>\|#\a\w*/

" ---- blocks: a line ending in ":" --------------------------------------------------
" anything ending in ":" that isn't a known block is an error: the compiler rejects it
syntax match pusUnknownBlock /^\s*\zs[^#]*[^ #:]\s*:\s*$/
syntax match pusBlock /^\s*\zs\%(if\|elif\|while\|loop\|for\|opt\|break\|critical\|group\|switch\|case\|partition\|box\|legend\)\>\ze.*:\s*$/ nextgroup=pusCond skipwhite
syntax match pusBlock /^\s*\zs\%(else\|do\|parallel\|split\|branch\)\>\ze.*:\s*$/ nextgroup=pusCond skipwhite
syntax match pusBlock /^\s*\zsnote\>\ze[^:]*:\s*$/ nextgroup=pusNoteTarget skipwhite
syntax match pusCond /[^:]*\ze:\s*$/ contained contains=pusBranchLabel,pusString,pusColor nextgroup=pusColon
syntax match pusBranchLabel /\[[^\]]*\]/ contained
syntax match pusColon /:\s*$/ contained
" `while COND` closing a `do:` block (no colon)
syntax match pusBlock /^\s*\zswhile\>\ze\%(.*:\s*$\)\@!/ nextgroup=pusCondLine skipwhite
syntax match pusCondLine /.*$/ contained contains=pusBranchLabel2,pusLoopArrow
syntax match pusBranchLabel2 /\[[^\]]*\]/ contained
" `-[#red,dashed]-> TEXT` / `-> TEXT`: the arrow back to the loop start
syntax match pusLoopArrow /-\[[^\]]*\]->\|\s\zs->\ze\%(\s\|$\)/ contained contains=pusColor nextgroup=pusLoopText
syntax match pusLoopText /.*$/ contained

" ---- header ------------------------------------------------------------------------
syntax match pusHeader /^\%(sequence\|activity\)\>\ze\s*\%(:.*\)\?$/ nextgroup=pusTitle
syntax match pusTitle /\s*:.*$/ contained contains=pusHeaderColon,pusComment
syntax match pusHeaderColon /\s*:\s*/ contained

" ---- statements --------------------------------------------------------------------
syntax match pusStatement /^\s*\zs\%(start\|stop\|end\|kill\|detach\|pass\|space\|autonumber\)\s*$/
syntax match pusStatement /^\s*\zs\%(lane\|section\|delay\|return\|activate\|deactivate\|create\|destroy\|hide\)\>/
syntax match pusMeta /^\s*\zs\%(title\|header\|footer\|caption\|skinparam\)\>/
syntax match pusStatement /^\s*\zsref\>\ze[^:]*:/ nextgroup=pusNames skipwhite
syntax match pusNames /[^:]*/ contained nextgroup=pusTextColon

" notes: `note: TEXT`, `note left: TEXT`, `note over A, B: TEXT`, `note A: TEXT`
syntax match pusNote /^\s*\zsnote\>\ze[^:]*:\s*\S/ nextgroup=pusNoteTarget skipwhite
syntax match pusNoteTarget /[^:]*/ contained contains=pusNoteWord nextgroup=pusTextColon,pusColon
syntax keyword pusNoteWord left right over of contained
syntax match pusTextColon /:\s*/ contained nextgroup=pusText
syntax match pusText /.*$/ contained contains=pusComment

" activity: arrow label `-> TEXT`
syntax match pusArrowLabel /^\s*\zs->/ nextgroup=pusLabelText skipwhite
syntax match pusLabelText /.*$/ contained contains=pusComment

" ---- sequence: declarations and messages --------------------------------------------
syntax match pusDecl /^\s*\zs\%(participant\|actor\|boundary\|control\|entity\|database\|collections\|queue\)\>/ nextgroup=pusDeclName skipwhite
syntax match pusDeclName /"[^"]\+"\|[[:alnum:]_.]\+/ contained
" A -> B++: text
syntax match pusMessage /^\s*\zs\%("[^"]\+"\|[[:alnum:]_.]\+\)\s*\%(<\?-\+>\+[xo]\?\|<-\+\|<\?\.\+>\+\|-\+[xo]\|<-\+>\)\s*\%("[^"]\+"\|[[:alnum:]_.]\+\)\%(++\|--\)\?/ contains=pusArrow,pusName,pusActivation nextgroup=pusTextColon
syntax match pusName /"[^"]\+"\|[[:alnum:]_.]\+/ contained
syntax match pusArrow /<\?-\+>\+[xo]\?\|<-\+>\?\|<\?\.\+>\+\|-\+[xo]/ contained
syntax match pusActivation /\%(++\|--\)\ze\s*\%(:\|$\)/ contained

" ---- plantuml: escape hatch ------------------------------------------------------------
syntax region pusPlantuml matchgroup=pusPassKeyword start=/^\s*plantuml:\s*/ end=/$/ oneline keepend contains=@pusPlantuml

hi def link pusComment Comment
hi def link pusTodo Todo
hi def link pusString String
hi def link pusColor Constant
hi def link pusUnknownBlock Error
hi def link pusBlock Conditional
hi def link pusCond Normal
hi def link pusCondLine Normal
hi def link pusBranchLabel Label
hi def link pusBranchLabel2 Label
hi def link pusLoopArrow Operator
hi def link pusLoopText Label
hi def link pusColon Delimiter
hi def link pusHeader PreProc
hi def link pusTitle Title
hi def link pusHeaderColon Delimiter
hi def link pusStatement Statement
hi def link pusMeta PreProc
hi def link pusNote Keyword
hi def link pusNoteWord Keyword
hi def link pusNoteTarget Identifier
hi def link pusNames Identifier
hi def link pusText String
hi def link pusTextColon Delimiter
hi def link pusArrowLabel Operator
hi def link pusLabelText Label
hi def link pusDecl Type
hi def link pusDeclName Identifier
hi def link pusName Identifier
hi def link pusArrow Operator
hi def link pusActivation Special
hi def link pusPassKeyword PreProc

let b:current_syntax = "pumlscript"
