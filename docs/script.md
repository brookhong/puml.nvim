# puml script

A small indentation-based language that compiles to PlantUML sequence and activity
diagrams. It is designed to be easy to write correctly, by hand or by an LLM:

- **Nesting is indentation.** A line ending in `:` opens a block; there are no closing
  keywords (`end`, `endif`, `end fork`, …), so blocks can't be left unbalanced.
- **The same words for both diagram types.** `if/elif/else`, `while`, `do … while`,
  `parallel/branch`, `group`, `note` mean the same thing in a sequence and an activity
  diagram; the compiler picks the right PlantUML keyword.
- **One statement per line.** In activity diagrams a plain line is an action — no `:…;`.
- **Errors come with line numbers**, e.g. `3: else without if`, and nothing is emitted
  until the script is valid.

Files use the `.pus` extension. It works in both directions:

- **Script → PlantUML:** `:PumlScript` in a `.pus` buffer writes `FILE.puml` next to it and
  shows it with its preview; saving the script recompiles it. Errors become diagnostics.
  The file starts with a `' generated from FILE.pus` comment; a `FILE.puml` without it
  (written by hand) is only replaced after asking.
- **PlantUML → script:** `:PumlScript` in a PlantUML buffer converts the diagram under the
  cursor to `FILE.pus` (never overwriting an existing one) and opens it. Lines with no
  script equivalent are kept as `plantuml: LINE`, so converting back gives the same diagram.
  Only the current activity syntax is supported, not the old `(*) -->` one.

`.pus` buffers get syntax highlighting and Python-style indentation (4 spaces; a line
ending in `:` indents the next one, and `elif`/`else`/`branch`/`case` move to their
block as you type them). Other lines keep their indentation, so `=` never changes what
a script means. A line ending in `:` that isn't a known block is highlighted
as an error, and a plain line that isn't highlighted at all is an activity action.

From a shell, the direction follows the input (PlantUML has `@startuml`):

```sh
nvim -l scripts/pus2puml.lua diagram.pus  > diagram.puml   # errors on stderr, exit 1
nvim -l scripts/pus2puml.lua diagram.puml > diagram.pus    # kept lines reported on stderr
```

## Header

The first line names the diagram type and, optionally, the title:

```
sequence: Checkout
activity: Order handling
```

Without a header the type is guessed: messages between names (`A -> B`) mean a sequence
diagram, anything else an activity diagram.

A line starting with `#` is a comment; so is ` # …` (space, hash, space) after a
statement, which means a message or action text can't contain ` # ` (write `#42`, or use
a `plantuml:` line). `plantuml:` lines and the text under `note …:` / `legend …:` are
taken exactly as written, comments and indentation included.

## Shared

| Script | Meaning |
|---|---|
| `if COND [LABEL]:` / `elif COND [LABEL]:` / `else [LABEL]:` | condition (`alt`/`else` in sequence, `if`/`elseif`/`else` in activity; `[LABEL]` = branch label, activity only, default yes/no) |
| `while COND [LABEL] [EXIT]:` | loop that tests first (`loop` in sequence; activity: `while (COND) is (LABEL)` … `endwhile (EXIT)`, default yes/no) |
| `do:` + `while COND [LABEL] [EXIT]` (same indent, no colon) | loop that tests after (`repeat … repeat while (COND) is (LABEL) not (EXIT)`) |
| `while COND [LABEL] -[#red,dashed]-> TEXT` · `while COND -> TEXT` (activity, after `do:`) | the same, with a style and/or text for the arrow back to the loop start, as in PlantUML |
| `parallel:` with `branch:` children | parallel branches (`par` / `fork`) |
| `group NAME:` | a labelled frame |
| `note: TEXT` · `note left: TEXT` · `note right: TEXT` | note on the last statement |
| `title TEXT` · `header TEXT` · `footer TEXT` · `caption TEXT` | diagram-wide text |
| `plantuml: LINE` | passed through verbatim (escape hatch) |
| `pass` | an intentionally empty block (e.g. an empty `else:`) |
| `legend [POSITION]:` with text lines indented under it | a multi-line legend |
| `# comment` on its own line | kept as a PlantUML comment `' comment` |

Loop labels can be left out (`while x?` = `is (yes)`), and `[]` means "no label"
(`while x? [] [no]` → `repeat while (x?) not (no)`).

## Sequence only

| Script | PlantUML |
|---|---|
| `actor NAME ["Label"]` (also `participant boundary control entity database collections queue`) | declaration (`actor "Label" as NAME`) |
| `box "Title":` with declarations inside | `box … end box` |
| `A -> B: text` (`->` sync, `-->` reply, `->>` async, `->x` lost, `<->`) | message; participants are declared on first use |
| `A -> B++: text` · `B --> A--: text` | message that activates / deactivates the target |
| `return TEXT` · `activate A` · `deactivate A` · `create A` · `destroy A` | as in PlantUML |
| `loop COND:` · `opt COND:` · `break COND:` · `critical TEXT:` | groups (`while` = `loop`) |
| `note A: TEXT` · `note over A, B: TEXT` · `note left of A: TEXT` | notes |
| `ref A, B: TEXT` | `ref over A, B: TEXT` |
| `section TEXT` | `== TEXT ==` |
| `delay [TEXT]` · `space` | `...TEXT...` · `\|\|\|` |
| `autonumber` · `hide footbox` | as in PlantUML |

## Activity only

| Script | PlantUML |
|---|---|
| any other line | an action `:line;` |
| `lane NAME` | swimlane `\|NAME\|` |
| `start` · `stop` · `end` · `kill` · `detach` | as in PlantUML (`start` is added if missing, `stop` if the flow doesn't end) |
| `switch WHAT:` with `case VALUE:` children | `switch … case … endswitch` |
| `split:` with `branch:` children | parallel branches that don't join |
| `partition NAME:` | `partition NAME { … }` |
| `-> TEXT` | label on the next arrow |

## Examples

```
sequence: Checkout
actor Customer
boundary UI "Web UI"
database DB

Customer -> UI: open cart
UI -> Checkout++: checkout(cart)
if card accepted:
    Checkout -> PG: charge
    PG --> Checkout: ok
elif coupon:
    Checkout -> DB: apply coupon
else:
    Checkout --> UI: error
loop each item:
    Checkout -> DB: reserve(item)
parallel:
    branch:
        Checkout ->> Events: notify warehouse
    branch:
        Checkout ->> Events: notify customer
Checkout --> UI--: done
```

```
activity: Order handling
lane Customer
place order
lane Shop
if in stock? [yes]:
    reserve items
else [no]:
    back-order
while more items?:
    pack item
do:
    print label
while label unreadable?
parallel:
    branch:
        email customer
    branch:
        update stock
```
