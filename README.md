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
- **Insert elements** from a per-type catalog (participants, messages, classes, relations, actions, notes …). Elements are inserted as snippets via `vim.snippet`, so you can `<Tab>` through the placeholders.
- **Connect** two nodes: pick *from* and *to* among the names already declared or used, then pick an arrow style (sync/reply/async, extension/composition/…), an optional direction, and a label.
- **Wrap** a selection or motion in a block: `loop`, `alt/else`, `opt`, `par`, `group`, `box` (sequence); `if/else`, `while`, `repeat`, `fork`, `partition` (activity); `package`, `node`, `rectangle`, `together` … (structural diagrams).
- **Text objects** `iu` / `au` for the enclosing block (`loop…end`, `if…endif`, `{…}`, `note…end note`, …).
- **Errors as diagnostics**, mapped back to the right buffer line.
- **Templates** for new diagrams, plus **export** to png/svg/txt/pdf/….
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
  cmd = { "Puml", "PumlNew" },
  opts = {},
}
```

## Usage

| Command | Description |
|---|---|
| `:Puml [file]` | Open `file` (or a new buffer) with the preview. Prompts for a template when empty. In a PlantUML buffer it toggles the preview. |
| `:PumlPreview` | Toggle the preview split |
| `:PumlRender` | Render now |
| `:PumlMode [auto\|text\|image]` | Set or cycle the preview mode |
| `:PumlInsert [item]` | Insert an element (picker, or by id such as `message`, `alt-else`) |
| `:PumlConnect` | Connect two nodes with an arrow |
| `:[range]PumlWrap [block]` | Wrap lines in a block (`loop`, `alt-else`, `if-else`, `package`, …) |
| `:PumlNew [type]` | Insert a diagram template |
| `:PumlExport [fmt]` | Export the diagram under the cursor next to the file |

Default buffer-local keymaps (prefix `<leader>u`):

| Key | Action |
|---|---|
| `<leader>up` | toggle preview |
| `<leader>ur` | render now |
| `<leader>um` | cycle preview mode auto → text → image |
| `<leader>ui` | insert element |
| `<leader>uc` | connect nodes |
| `<leader>uw{motion}` / `<leader>uww` / visual `<leader>uw` | wrap in block |
| `<leader>un` | new diagram from template |
| `<leader>ue` | export |
| `iu` / `au` | inner / around enclosing block (e.g. `<leader>uwiu`, `dau`, `viu`) |

In the preview window: `q` closes it, `r` re-renders, `m` cycles the mode, and `gx` on an image path opens the image.

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
    image_format = "png",        -- "png" | "svg"
    image_dir = nil,             -- default: stdpath("cache") .. "/puml"
  },
  export = { format = "png", dir = nil },
  keymaps = {
    prefix = "<leader>u",        -- false to disable
    textobjects = { inner = "iu", outer = "au" },
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
- Name detection and block parsing are best-effort heuristics (no full PlantUML grammar).

## Tests

```sh
nvim --headless -u NONE -l tests/run.lua
```
