# vimzen poc — vim bottom-bar + modal input

Pure-web proof of concept for the modal input system and zen status line
(see `../ARCHITECTURE.md` §3, §4). No build, no deps.

## run

```sh
cd browser/poc
python3 -m http.server 8000
# open http://localhost:8000
```

A server is required (not `file://`) so the lab iframes are same-origin —
that simulates what per-tab JS injection gives the real browser.

## what to try

| experiment | how |
|---|---|
| url placement | `,x` → statusline / hybrid / hidden |
| address editing | `o`, then toggle prefill modes in `,x`; try bottom vs top edit bar |
| direct web search | `o`, type `rust borrow checker` → watch the `→ search ddg` hint; Enter |
| mode visuals | `,x` → tint / accent line / fade badge; compare NORMAL vs INSERT |
| reload | `r`, watch the loading state machine on the right of the bar |
| load states | navigate to a big site (slow…), a blocked site (`o` → `github.com`), a lab page (✓) |
| focus arbitration | click the page from NORMAL (first click = INSERT, swallowed); click a form field in form lab (focus forwarded); Esc back |
| counts & sequences | `3j`, `10j`, `gg`, `gt`, `2gt`, `,d` — pending keys show in the bar |
| find | `/needle` on scroll lab — Enter = 1st match, `n`/`N` cycles, `[idx/total]` bottom-right |
| media tab | play audio on media lab, `gt` away, `M` jumps back |
| full-width edit bar | `o` — the input now takes over the entire bottom bar |
| upward suggestion combobox | `o`, type — list grows up from the bar; best match sits next to the bar; `↑`/`C-p` into the list, `↓`/`C-n` back toward input, `Tab` fills, `Enter` accepts |
| tab visibility | `gt`/`gT` shows a transient overlay while cycling; `,t` opens a sticky picker (`j`/`k`, `Enter`, or `1-9`) |

## keys

`j k C-d C-u C-f C-b gg G` scroll · `H L` history · `r` reload ·
`gt gT {N}gt g0 g$` tabs (transient overlay) · `,t` tab picker · `M` media tab ·
`i` insert · `o` open (suggestions: `↑/C-p` `↓/C-n`, `Tab` fill) ·
`/ n N` find with `[idx/total]` · `:` commands · `yy` yank url ·
`,d` debug · `,x` experiments · `?` help · `Esc` normal / cancel / close

## known poc-only limitations (these are the lessons)

- **cross-origin = blind**: no scroll, find, title, Esc-forwarding, or
  auto-insert inside external sites. Real engine fixes this with JS injection
  (R1) and key interception (R9, `CefKeyboardHandler`).
- **X-Frame-Options**: many big sites refuse to frame → poc shows `⛔ blocked`.
  Not a problem for a real engine; the point was designing the error UX.
- **no http status**: `loading → slow → ok/error` is timer + load-event based.
  CEF's load handler gives real status codes (R2).
- **esc while cross-origin INSERT is invisible to the parent** — click the bar.
  This exact gap is why the engine contract requires input interception.
- **autocomplete uses mock data** (open tabs + fake history). The real browser
  fetches Google/DDG suggest in the Rust core — no CORS there — and streams
  items to this same combobox UI. Find counts come from a text-node walk;
  the real engine gives match counts natively (R5).
