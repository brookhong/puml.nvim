# puml.nvim

Write PlantUML in Neovim and focus on the **logic and connectivity**. PlantUML handles the rendering, and you see the result live in a vertical split.

```
alt cache miss                 │          ╔══════╤═════╪═══════════════╪══════════════╪═══╗
  User -> API: request         │          ║ ALT  │  cache miss         │              │   ║
  API -> DB: query             │          ╟──────┘     │   request     │              │   ║
else                           │          ║            │──────────────>│              │   ║
                               │          ║            │               │    query     │   ║
end                            │          ║            │               │─────────────>│   ║
DB --> API: rows               │          ╠════════════╪═══════════════╪══════════════╪═══╣
                               │          ╚════════════╪═══════════════╪══════════════╪═══╝
   source buffer               │                  live preview (vertical split)
```

## Features

- **Live preview** in a vertical split, re-rendered on save, on change and when the cursor moves to another diagram.
  - **text** mode: PlantUML's Unicode/ASCII output (`-tutxt` / `-ttxt`). This is great for sequence diagrams.
  - **image** mode: renders PNG/SVG and shows the **image path** (open it with `gx`).
  - **auto** mode (default): sequence diagrams use text and every other diagram type uses image. You can configure this per type.
- **All diagram types**: sequence, class, activity, usecase, component/deployment, state, object, mindmap, wbs, gantt. The type is detected from the source.
- **Insert elements** from a per-type catalog (participants, messages, classes, relations, actions, notes …). Elements are inserted as snippets via `vim.snippet`, so you can `<Tab>` through the placeholders. Only what fits the grammar where the new line goes is offered:
  - **Inside a group or block:** no participant declarations, `box`, `== divider ==`, `title`/`skinparam`/… or `start`/swimlanes.
  - **Inside a `box`:** only participant declarations.
  - **Inside a class body:** only fields and methods. Fields and methods are never offered outside one.
  - **Inside a note, legend, `<style>`, object body or multi-line action:** nothing.
  - **Concurrent regions (`--`):** only inside a composite state.
  - **Attached notes and `detach`/`kill`:** only after something they can attach to.
  - **Completion** suggests snippets by the same rules. `:PumlInsert <item>` refuses an item that doesn't fit.
  - **Verified:** every item offered at every line of the sample diagrams was rendered with PlantUML, and none is a syntax error.
- **Connect** two nodes: pick *from* and *to* among the names already declared or used, then pick an arrow style (sync/reply/async, extension/composition/…), an optional direction, and a label.
- **Wrap** a visual selection in a block (`<leader>u` on the selection): `loop`, `alt/else`, `opt`, `par`, `group`, `box` (sequence); `if/else`, `while`, `repeat`, `fork`, `partition` (activity); `package`, `node`, `rectangle`, `together` … (structural diagrams).
- **One mapping**, `<leader>u`, opens a menu that only lists the actions available at the cursor or for the selection.
- **Text objects** (opt-in) for the enclosing block (`loop…end`, `if…endif`, `{…}`, `note…end note`, …).
- **Errors as diagnostics**, mapped back to the right buffer line.
- **Templates** for new diagrams, plus **export** to png/svg/txt/pdf/…. Each template uses every element of its diagram type, with section comments, so you start from a diagram that renders and delete what you don't need.
- **Markdown**: works inside ```` ```plantuml ```` / ```` ```puml ```` fences.
- **Completion**: an nvim-cmp source (`puml`) for names and snippets, and an omnifunc for names.
- Local `plantuml` command **or** a PlantUML server (picoweb / plantuml-server) via curl.

## Requirements

- Neovim >= 0.10
- `plantuml` on `$PATH` (or `java -jar plantuml.jar`), **or** a PlantUML server plus `curl`

Run `:checkhealth puml` to verify the setup.

## Install

lazy.nvim:

```lua
{
  dir = "~/works/puml.nvim", -- or "you/puml.nvim"
  ft = { "plantuml", "markdown" },
  cmd = { "Puml", "PumlNew", "PumlMenu", "PumlCatalog" },
  opts = {},
}
```

## Usage

| Command | Description |
|---|---|
| `:Puml [file]` | Open `file` (or a new buffer) with the preview. Prompts for a template when empty. In a PlantUML buffer it toggles the preview. |
| `:[range]PumlMenu` | Menu of the actions available at the cursor (or for the range) |
| `:PumlCatalog` | Mindmap of every diagram type → what you can insert / connect / wrap (generated from the catalog, including your `catalog` config) |
| `:PumlPreview` | Toggle the preview split |
| `:PumlRender` | Render now |
| `:PumlMode [auto\|text\|image]` | Set or cycle the preview mode |
| `:PumlInsert [item]` | Insert an element (picker, or by id such as `message`, `alt-else`) |
| `:PumlConnect` | Connect two nodes with an arrow |
| `:[range]PumlWrap [block]` | Wrap lines in a block (`loop`, `alt-else`, `if-else`, `package`, …) |
| `:PumlNew [type]` | Insert a diagram template |
| `:PumlExport [fmt]` | Export the diagram under the cursor next to the file |

**There is one mapping: `<leader>u`** (normal and visual mode). It opens a menu of the actions that make sense at the cursor:

```
╭──────── puml · sequence ────────╮
│ i  Insert sequence element      │
│ c  Connect two nodes            │
│ p  Open preview                 │
│ m  Preview mode (now: auto)     │
│ n  Add another diagram          │
│ e  Export diagram               │
╰── key: pick · /: filter · <Esc> ╯
```

Every menu entry has a fixed label, so `<leader>u i` always inserts, `<leader>u c` always connects, and so on. You can read the label off the screen the first time and type it from memory later. The menu only lists what is available. For example, Connect is hidden in activity diagrams, Render is hidden while the preview is closed, and an empty buffer only offers New diagram and Open preview. Wrapping needs a selection, so it is never in the normal-mode menu. Select lines inside a diagram with `V`, and the blocks you can wrap them in appear **beside the selection**. **Press a label to wrap**:

```
@startuml   ╭ wrap 2 lines ────────────────────────────────────────────────╮
A -> B: x   │ l  loop                   repeat while condition holds         │   ← Vj, then l
B --> A: y  │ e  alt / else             if condition, else the other branch  │
@enduml     │ t  opt                    only if condition holds              │
            │ h  par                    branches run in parallel             │
            │ …                                                              │
            ╰─────────────────────────────────────────────────── key: wrap ──╯
```

Each block has a short description of what it means. The value you will be asked for (_condition_, _name_, _participant_, …) is styled in the description: italic, in the colour of `Special`, via the `PumlPickerPlaceholder` highlight group. The insert picker styles snippet placeholders the same way (`A -> B: message` with _A_, _B_, _message_ styled), so you can tell what you will fill in from the literal syntax. The same descriptions appear in the wrap picker, and the "New diagram" picker describes each diagram type. The list follows the selection as you extend it, and it only offers blocks that fit the grammar at that spot:

- **The selection must hold whole blocks.** If it cuts `loop … end` in half, or includes an `else` / `fork again` / `case` without its block, nothing is offered.
- **Where the selection sits matters.** Nothing is offered inside a note, ref, legend or class body. In sequence diagrams a `box` only holds participant declarations and can't go inside a group.
- **What the selection holds matters.** In sequence diagrams, participant declarations only get `box`, and messages get the groups (`activate` needs a message). In activity diagrams, `start` can't go inside a block. Diagram-wide statements (`left to right direction`, `skinparam`, `title`, …) and swimlanes never get wrapped. `namespace` is only offered in class and object diagrams.

When nothing fits, the hint says why, e.g. ``✗ the selection cuts `loop retry` (line 3) in half``. PlantUML itself accepts most broken nestings without complaint, so these checks are puml.nvim's own. Every combination they allow was also rendered with PlantUML to make sure none of them is a syntax error.

The labels only use keys that are of little use in linewise visual mode: in-line motions such as `h`/`l`/`f`/`t`, word motions, `q`, `m` and `z` (`picker.selection_keys`, default `lhwebftqmzWBEFTQK`). So `j`/`k`/`G`/`{`/`}`/`o`, `y`/`d`/`c`/`>`/`<`/`=`, `:` and text objects all keep working. The label mappings only exist while the hint is shown, and any buffer-local mapping they cover is put back afterwards. In charwise/blockwise visual mode (`v`, `<C-v>`) the hint is passive: there, `<leader>u` + label picks. Turn the hint off with `picker = { selection_hint = false }`.

Every picker (the menu, insert, connect, wrap, templates) uses the same popup, in which every choice has a **one-key label**, like foyer.nvim's. Labels are mnemonic where possible (`m` message, `r` reply message, `u` User) and don't change while you filter. `/` filters by words, `<CR>` picks the only match left, and `<Esc>` clears the filter or closes the popup. Set `picker = { ui = "select" }` to use `vim.ui.select` (telescope, fzf-lua, …) instead.

Text objects for the enclosing block (`loop…end`, `if…endif`, `{…}`, …) are opt-in: `keymaps = { textobjects = { inner = "iu", outer = "au" } }`.

In the preview window (its winbar lists these keys on the right): `?` or `<CR>` opens the menu, `q` closes the preview, `r` re-renders, `m` cycles the mode, and `gx` on an image path opens the image.

## Configuration

Defaults:

```lua
require("puml").setup({
  cmd = { "plantuml" },          -- e.g. { "java", "-jar", "/path/to/plantuml.jar" }
  server = nil,                  -- e.g. "http://localhost:8080" (plantuml -picoweb:8080)
  curl = "curl",
  preview = {
    auto = true,
    events = { "BufWritePost", "TextChanged", "InsertLeave" },
    debounce_ms = 400,
    follow_cursor = true,
    width = 0.5,                 -- ratio of columns, or absolute columns if > 1
    mode = "auto",               -- "auto" | "text" | "image"
    per_type = { sequence = "text" },
    auto_default = "image",
    text_format = "utxt",        -- "utxt" | "txt"
    builtin_text = true,         -- draw activity diagrams in text mode with the built-in renderer
    image_format = "png",        -- "png" | "svg"
    image_dir = nil,             -- default: stdpath("cache") .. "/puml"
  },
  export = { format = "png", dir = nil },
  keymaps = {
    menu = "<leader>u",          -- the only mapping (n + x); false = none, use :PumlMenu
    textobjects = false,         -- opt-in, e.g. { inner = "iu", outer = "au" }
  },
  picker = {
    ui = "labels",               -- "labels" (one-key popup) | "select" (vim.ui.select)
    selection_hint = true,       -- show the wrap blocks + labels beside a visual selection
    selection_keys = "lhwebftqmzWBEFTQK", -- wrap labels; live keys in V mode, so no motion/operator keys
    characters = "asdfghjklqwertyuiopzxcvbnm1234567890ASDF…", -- allowed labels
  },
  connect = { ask_direction = true },
  markdown = { enabled = true, filetypes = { "markdown" }, fences = { "plantuml", "puml", "uml" } },
  catalog = {},                  -- extra items: { sequence = { { label = "...", body = "..." } }, common = {...} }
  diagnostics = true,
  cmp = true,
})
```

nvim-cmp:

```lua
sources = { { name = "puml" }, ... }
```

### Speed

Each local render starts a JVM (~1–1.5s). For near-instant previews, run a local server and point the plugin at it:

```sh
plantuml -picoweb:8080
```

```lua
require("puml").setup({ server = "http://localhost:8080" })
```

## Notes

- PlantUML's text output is fully supported only for sequence diagrams. Other types produce rough or empty text, which is why auto mode uses image mode for them.
- **Activity diagrams** are the exception: PlantUML's text output only places the labels (no boxes or arrows), so in text mode puml.nvim draws them with a built-in renderer. It covers start/stop/end, actions, `->` labels, if/elseif/else, switch, while, repeat, fork/split and partition/group. Notes and swimlanes are left out. PlantUML still checks the source in the background, so errors still show up as diagnostics. Set `preview.builtin_text = false` to get PlantUML's raw output instead.
- Name detection and block parsing are best-effort heuristics (no full PlantUML grammar).

## Tests

```sh
nvim --headless -u NONE -l tests/run.lua
```
