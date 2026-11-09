# Browser Architecture — Working name: **vimzen**

A keyboard-first browser: vim-modal input, zen-minimal chrome, instant media-tab
access, AI-driven tab organization, and fzf-style fuzzy finding over history,
tabs, and commands.

> Scope of this doc: **features, UX, module design, and technical decisions**.
> Stack decision ratified: **Tauri (Rust core) + CEF (`cef-rs`) + Svelte 5 + bits-ui + Tailwind CSS**.
> See §2 for engine mapping and §9 for layer layout.

---

## 1. Design Principles

1. **Keyboard is the primary interface.** Every action is reachable without a
   mouse. Mouse works, but is never required.
2. **Content owns the screen.** Chrome (UI) is transient: it appears when
   summoned, then gets out of the way.
3. **Modes, not menus.** Interaction state is explicit (NORMAL / INSERT /
   SEARCH / HINT / COMMAND) and always visible in the status line.
4. **AI assists, never blocks.** Grouping is fast, undoable, and silent on
   failure. Browsing never waits on a network call.
5. **Privacy by default.** The AI feature sends the minimum metadata
   (titles + domains), redacts aggressively, and supports local models.

Reference projects to study: qutebrowser (modal browsing done right), Vieb
(Electron vim browser), nyxt (extensibility), Zen Browser (zen UI, tab groups).

---

## 2. Engine & Tech Stack Contract

### 2.1 Ratified Tech Stack

- **Core & OS Shell:** **Tauri v3 (Rust)**
- **Web Rendering Engine:** **CEF (Chromium Embedded Framework) via `cef-rs`**
  - Fulfills R1–R10 natively, particularly `CefKeyboardHandler::OnPreKeyEvent` for modal key interception.
- **Frontend Chrome:** **Svelte 5 (Runes) + TypeScript**
  - Fine-grained reactivity, zero virtual DOM diffing, sub-frame input updates.
- **UI Component Language & Primitives:** **`bits-ui` (headless) + Tailwind CSS**
  - Keyboard-first accessible primitives for comboboxes, command palettes, and transient overlays.
  - Dense 12px monospace typography, 24px status line, terminal aesthetic.
- **Icon Strategy & Typography:** **Devicon Icon Font / CSS via `<i>` tags**
  - Zero-JS overhead, no component wrapper churn: `<i class="devicon-... colored"></i>`.
  - Global stylesheet (`devicon/devicon.min.css`) imported once in the root chrome layout; icons rendered directly via semantic `<i>` elements for tabs, status slots, and picker rows.

### 2.2 Engine Capabilities Mapping (R1–R10)

| # | Requirement | CEF / Rust Implementation | Needed for |
|---|-------------|---------------------------|------------|
| R1 | Per-tab JS injection & lifecycle | `CefBrowser` / `CefFrame::ExecuteJavaScript` | all DOM-level interactions |
| R2 | Page events (`urlChanged`, `titleChanged`, `loadState`) | `CefDisplayHandler`, `CefLoadHandler` | tab model, status line |
| R3 | Per-tab **audible** state & events | `CefAudioHandler` / audio stream notifications | media tab (§5) |
| R4 | Per-tab audio muting | `CefBrowserHost::SetAudioMuted` | media tab ranking |
| R5 | Find-in-page with match counts | `CefBrowserHost::Find` + `CefFindHandler` | `/` search & `[idx/total]` count |
| R6 | Back/forward history & reload | `CefBrowser::GoBack`, `GoForward`, `Reload` | navigation keys |
| R7 | Tab group orchestration | Rust data model (`TabManager`) rendering to Svelte | AI grouping (§6) |
| R8 | Tab screenshot capture | `CefBrowserHost::WasHidden`, paint buffer capture | visual grouping preview |
| R9 | Key interception *before* page renderer | `CefKeyboardHandler::OnPreKeyEvent` returning `true` | NORMAL mode blocking |
| R10 | Editable element focus detection | Preload JS hook + `CefMessageRouter` (`cefQuery`) | auto-INSERT mode |

---

## 3. Modal Input System (vim)

The soul of the project. A **mode manager** owns a state machine; a
**keybinding engine** translates raw key events into commands; a **command
registry** executes them.

### 3.1 Modes & state machine

```
                ┌──────────────────────────────────────────┐
                │                                          │
                ▼                                          │
   ┌────────┐  i / click-into-field   ┌────────┐          │
   │ NORMAL │ ───────────────────────▶ │ INSERT │          │
   └───┬────┘ ◀─────────────────────── └────────┘          │
       │        <Esc> (<C-[>)                              │
       │ /                          ┌────────┐             │
       ├──────────────────────────▶ │ SEARCH │ ──<Esc>─────┤
       │ f / F                      └────────┘             │
       ├──────────────────────────▶ ┌────────┐             │
       ├──────────────────────────▶ │  HINT  │ ──<Esc>─────┤
       │ :                          └────────┘             │
       ├──────────────────────────▶ ┌─────────┐            │
       └──────────────────────────▶ │ COMMAND │ ──<Esc>────┘
                                    └─────────┘
```

- **NORMAL** — default. Keys are commands; the page never sees them.
- **INSERT** (interactive) — all keys pass through to the page. Entered via
  `i`, or automatically when an editable element gains focus (R10; toggleable
  via config). Exited with `<Esc>` / `<C-[>`.
- **SEARCH** — `/` opens a find bar; typing filters; `<Enter>` confirms and
  returns to NORMAL keeping matches active; `<Esc>` clears.
- **HINT** — `f`/`F` overlay letter labels on clickable elements; typing
  letters narrows; `<Enter>` activates; `<Esc>` cancels.
- **COMMAND** — `:` ex-style command line (`:q`, `:group`, `:tabmove 3`,
  `:open <url>`). Tab-completion against the command registry.

Mode is **global**, not per-tab (simpler mental model; qutebrowser does the
same). Current mode is always shown in the status line.

### 3.2 Keymap — NORMAL mode (Curated V1 Core)

The initial core keymap is lean and deliberate: all blind cycling chords are removed
in favor of a single Telescope-style tab picker (`gt`), closing is done via `:q`/`:qa`,
and tab restore uses an undo flash alert toast. Fast features (media jump, AI grouping,
history search) are deferred to post-shell exploration.

Navigation / scrolling

| Key | Command ID | Action | Count? |
|-----|------------|--------|--------|
| `j` / `k` | `scroll.down` / `scroll.up` | scroll down / up by line | Yes (`10j`) |
| `h` / `l` | `scroll.left` / `scroll.right` | scroll left / right | Yes (`5h`) |
| `gg` / `G` | `scroll.to-top` / `scroll.to-bottom` | jump to top / bottom of page | No |
| `<C-d>` / `<C-u>` | `scroll.page-down-half` / `scroll.page-up-half` | half-page down / up | Yes |
| `<C-f>` / `<C-b>` | `scroll.page-down-full` / `scroll.page-up-full` | full-page down / up | Yes |
| `H` / `L` | `nav.back` / `nav.forward` | history back / forward | Yes (`2H`) |
| `r` / `R` | `nav.reload` / `nav.reload-hard` | reload / hard reload (bypass cache) | No |

Tabs

| Key | Command ID | Action |
|-----|------------|--------|
| `gt` | `tab.telescope-picker` | Open Telescope-style fuzzy tab switcher (`<C-j>`/`<C-k>`, `<Enter>`) |

Search & Input Bar Takeovers (Input Plugins)

| Key | Command ID | Action |
|-----|------------|--------|
| `/` | `input.find` | open find bar (live `[idx/total]` count, `Enter` jumps to 1st) |
| `n` / `N` | `find.next` / `find.prev` | next / previous search match |
| `o` | `input.open` | open address / search bar in current tab |
| `O` | `input.open-new-tab` | open address / search bar in new tab |
| `:` | `input.command` | open Ex-command line (`:q`, `:qa`, `:open`, `:reload`, etc.) |

Mode Transitions & Meta

| Key | Command ID | Action |
|-----|------------|--------|
| `i` | `mode.enter-insert` | enter INSERT mode (keys pass through to page) |
| `<Esc>` / `<C-[>` | `mode.enter-normal` | return to NORMAL mode (clears find, closes overlays) |
| `?` | `ui.toggle-help` | toggle keybinding cheat sheet / which-key popup |

Ex-Commands (`:`)

| Command | Action | Notes |
|---------|--------|-------|
| `:q` | Close active tab | Triggers transient undo flash: *"Closed tab. Press 'u' to undo (4s)"* |
| `:qa` / `:qall` | Close all tabs / exit window | Prompt if downloads or media are active |
| `:open <url\|query>` | Open URL or web search | Handled by `input.open` plugin |
| `:reload` / `:r` | Reload active tab | Soft reload |
| `:help` / `:h` | Open help cheat sheet | Toggles help overlay |

Notes & tradeoffs:
- Tab closing is intentionally vim-aligned (`:q` instead of accidental single-key `d`).
- Closing triggers an interactive undo toast (§10.4): pressing `u` within 4s restores the tab.
- `<Esc>` in NORMAL mode while find matches are active clears find highlights.
- INSERT passes **everything** to the page except `<Esc>` / `<C-[>`.

### 3.3 Keybinding engine requirements

- **Counts:** `{count}{cmd}` — `3gt`, `10j`. Count shown in status line while
  being typed.
- **Multi-key sequences:** `gg`, `gt` with a configurable timeout (default
  1000 ms). Longest-match wait on ambiguity.
- **Chords / modifiers:** full `<C-…>`, `<M-…>` support in the config syntax.
- **User remapping:** every binding lives in the config file, not in code.
  `bind gt tab.next` / `unbind gt`.
- **Per-site passthrough:** config rule, e.g. `passthrough: ["mail.google.com"]`,
  for sites with their own keybindings; status line shows `PASSTHROUGH`.
- **Repeatability metadata:** commands declare whether a count is meaningful.

### 3.4 Command registry (architectural backbone)

Every action is a command: `{ id: "tab.next", title, modes: [NORMAL], acceptsCount: true, run(ctx) }`.
Keybindings, the `:` command line, a future command palette, and tests all go
through this one registry. UI never calls services directly.

---

## 4. Zen Minimal UI

Goal: **maximum screen estate** — the page is the UI.

### 4.1 UI inventory & visibility rules

| Element | Default | Appears when |
|---------|---------|--------------|
| Web content | always | — |
| Status line (bottom, 1 line) | always | hidden only in full-zen level 3 |
| Command bar (top, 1 line) | hidden | `o`/`t`/`:`/`/` invoked; hides after commit/cancel |
| Tab strip | **hidden** | never as a persistent strip; see overlay below |
| Tab overlay (transient list) | hidden | while `gt`/`gT` is being pressed repeatedly, or on `,t` |
| Fuzzy picker dropdown | hidden | typing in command bar, `,b`, `,h` (§8) |
| Group sidebar (vertical) | hidden | toggled with `,s` — main view for AI groups (§6.4) |
| Link hints overlay | hidden | HINT mode only |
| Bookmarks bar / extension icons | **never** | out of scope by design |

### 4.2 Status line spec (the one persistent element)

Vim-style, left → right:

```
[NORMAL]  3j▏tabs 4/9  ●2-media  ▏devto · Reading …  ▏🔊 2   70%  14:32
 mode     count/       tab pos    title (truncated)   media  zoom  clock
          pending                  or current group   badge
```

- Mode badge is color-coded (NORMAL=blue, INSERT=green, SEARCH=yellow,
  HINT=purple, COMMAND=orange — colors from theme).
- `🔊 N` appears only when N tabs are audible; clicking/`M` jumps there.
- Everything is themeable; line height ≤ 24 px.

### 4.3 Zen levels

`Z` cycles: **1** chrome-visible (debugging) → **2** default (status line
only) → **3** full zen (nothing; status line appears for 2 s on mode change,
tab switch, or command invocation, then fades).

### 4.4 Tab awareness without a tab strip

- Holding/repeating `gt` shows a **transient overlay**: vertical MRU-ordered
  list (title, domain, media icon, group color chip) centered on screen;
  release confirms. (Like Firefox's Ctrl-Tab or vim's `:ls`.)
- Status line always shows `pos/count` so you're never lost.

---

## 5. Feature: Quick Switch to Media Tab

### 5.1 Media signals per tab (maintained by MediaMonitor service)

| Signal | Source | Notes |
|--------|--------|-------|
| `audible` | engine event (R3) | currently producing sound |
| `muted` | engine (R4) | user-muted → deprioritize |
| `mediaKind` | heuristic from title/domain + optional JS probe | `audio` / `video` / `none` |
| `lastAudibleAt` | timestamp on `audibleChanged` | for ranking |
| `lastActiveAt` | tab manager | tiebreaker |

### 5.2 Jump behavior

`M` (NORMAL mode):

1. Build candidate list = tabs with `audible` OR `mediaKind != none`,
   excluding the current tab.
2. Rank: **currently audible & not muted** (most recent first) →
   **paused media** (most recently audible first) → others by recency.
3. Activate the top candidate. Pressing `M` again **cycles** to the next
   candidate (ring order, computed at first press).
4. No candidates → status line flash: `no media tab` (non-blocking, 1.5 s).

### 5.3 Indicators

- 🔊 badge with count in status line.
- 🔊 / ▮▮ icons on entries in the tab overlay and group sidebar.
- Optional config `media.autoPauseOthers: true` — when jumping to a media tab,
  pause media in all other tabs.

### 5.4 Edge cases

- **User-muted playing tab:** ranks below unmuted audible, above paused.
- **Two tabs audible simultaneously:** recency wins; repeat-`M` cycle exposes
  both.
- **Media starts in background tab:** status line badge increments; optional
  subtle pulse animation. Never auto-switch.
- **Video call in progress:** treated as audible; consider a distinct 📹 icon
  later.

---

## 6. Feature: AI-Based Tab Grouping

### 6.1 Trigger model

| Trigger | Default | Behavior |
|---------|---------|----------|
| Manual `:group` / `,g` | always available | runs immediately, shows preview |
| Threshold auto-suggest | on, threshold = 12 ungrouped tabs | status-line prompt: `12 tabs — group them? [y/N]`, expires in 10 s, never steals focus |
| On-demand per-window only | — | grouping is per window, never across windows |

### 6.2 Data flow

```
TabManager                AIGroupingService                 Engine adapter
    │ collectMetadata()          │                               │
    ▼                            │                               │
 {id,title,domain,path?} ──────▶ │ 1. redact & filter            │
                                 │    (§6.5 privacy)             │
                                 │ 2. build prompt + JSON schema │
                                 │ 3. call provider ────────────▶ LLM
                                 │ 4. validate response          │
                                 │    (schema + id whitelist)    │
                                 │ 5. diff vs current groups     │
    ◀──── GroupingPlan ───────── │                               │
    │ preview overlay            │                               │
    │ user accepts ───────────────────────────────────────────▶ apply
    │                                                            tab groups
```

**Prompt contract** (system prompt sketch):

> Input: JSON array of tabs `{id, title, domain}`. Output: JSON
> `{groups: [{name, color, tabIds: []}], ungroupedTabIds: []}`.
> Rules: ≤ 8 groups; names ≤ 3 words; use the provided colors enum; a tab
> appears at most once; leave genuinely unrelated tabs ungrouped; never
> invent ids.

**Safety:** the returned `tabIds` are intersected with the actual open-tab id
set — LLM output is untrusted input; invalid entries are dropped, not
corrected.

### 6.3 GroupingPlan & undo

- Before applying, snapshot current group state. `:ungroup` (or `u` in the
  preview overlay) restores it. One level of undo is enough.
- Group model: `{ id, name, color, collapsed, source: "ai" | "manual" }`.
- Renaming a group flips `source` to `manual`; auto-grouping never renames or
  dissolves manual groups — it only groups the remaining ungrouped tabs.

### 6.4 Group UX

- **Group sidebar** (`,s`): vertical list of groups as colored chips; each
  group collapsible; tabs draggable between groups (mouse optional).
- Tab overlay and status line show group color chips.
- `:regroup` re-runs AI on ungrouped tabs only.
- A group collapses to one chip: its tabs stop appearing in `gt` cycling until
  expanded (config: `groups.cycleSkipsCollapsed`, default true).

### 6.5 Privacy, cost, and failure modes (design requirements)

- **Data sent:** title + domain only, by default. URL paths are opt-in
  (`ai.includePaths: false` default); query strings and credentials are
  **always stripped**.
- **Excluded:** incognito tabs, `about:`/`chrome:`-style internal pages, and a
  user exclude-list (`ai.excludeDomains: ["*.bank.com", …]`).
- **Providers:** pluggable `AIProvider` interface — cloud APIs or a local
  model. No API keys in the repo or config file committed anywhere; keys come
  from env vars / OS keychain.
- **Cost control:** single batched call per grouping run; debounce auto
  triggers (≥ 60 s apart); cache `domain → group-name` hints to shrink future
  prompts.
- **Failure:** network/parse/schema errors → status-line note `grouping
  failed`, nothing else happens. Browsing is never blocked or degraded.

---

## 7. History

Global, persistent, **local-only** browsing history. 

> **CEF vs. SQLite Division of Labor:**
> CEF only provides per-tab back/forward navigation entries (`GoBack()`, `GoForward()`,
> `GetNavigationEntries()`). It does **not** provide a global, cross-tab history
> database or search index. Global history is therefore maintained directly in
> **SQLite via `rusqlite` in the Rust core**, completely independent of the CEF rendering process.

### 7.1 What we record

- Logical entity: `Visit { id, url, domain, title, firstVisitAt, lastVisitAt,
  visitCount, typedCount, transition }` with `transition` ∈ typed | link |
  reload | restored.
- Recording hooks EngineAdapter events (`CefLoadHandler::OnLoadEnd` / R2): a committed
  navigation creates or bumps a Visit; `titleChanged` backfills the title.
- **Never recorded:** incognito tabs, internal pages, and domains on the
  exclude list (same list as §6.5).

### 7.2 Storage & SQLite Schema

- Embedded local SQLite database (`history.db`) in the user data directory managed via
  Rust's `rusqlite` crate.
- Writes are performed asynchronously on a dedicated background thread with batched commits,
  guaranteeing zero main-thread or UI-thread jank.
- Retention: `history.retentionDays` (default 90, `0` = keep forever); pruned
  at startup and daily thereafter. Deletes are hard deletes, not tombstones.

```sql
CREATE TABLE IF NOT EXISTS visits (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    url TEXT NOT NULL UNIQUE,
    domain TEXT NOT NULL,
    title TEXT NOT NULL,
    visit_count INTEGER NOT NULL DEFAULT 1,
    typed_count INTEGER NOT NULL DEFAULT 0,
    first_visit_time INTEGER NOT NULL,  -- unix timestamp
    last_visit_time INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_visits_domain ON visits(domain);
CREATE INDEX IF NOT EXISTS idx_visits_frecency ON visits(last_visit_time DESC, visit_count DESC);
```

### 7.3 Access & Commands

- In-memory hot cache of top 10,000–20,000 entries loaded at startup (~2MB RAM) for
  instantaneous `<50ms` subsequence matching during `o` and `,h` queries.
- Frecency ranking formula: `(visit_count * 1000) / (current_time - last_visit_time)`.
- `,h` / `:history` → fuzzy picker over history (§8).
- `:clearhistory today|week|all` and `:clearhistory --domain <d>`
  ("forget this site" performs an instant atomic `DELETE FROM visits WHERE domain = ?`).
- History is strictly private: **never sent to the AI provider** — AIGroupingService reads
  live tab metadata (§6.2), never HistoryStore.

---

## 8. Fuzzy Autocomplete (fzf-style)

One picker primitive, many sources — the fzf/Telescope pattern. This is the
search UX for the entire browser; §3.2 wires it to keys.

### 8.1 Architecture: FuzzyPicker + PickerSource

```text
PickerSource { id, title, items(): Item[], onAccept(item, opts) }
Item         { id,
               primary,     # title — displayed and matched against
               secondary,   # url / subtitle — displayed and matched against
               icon?, frecency? }
```

- Sources at ship: **open tabs** (`,b`), **history** (`,h`, and automatic in
  the command bar), **commands** (`:` queries the command registry). Later:
  tab groups, media tabs (§5), bookmarks.
- Command-bar integration: typing after `o` / `O` / `t` live-queries history
  (open tabs deduped in); the best match appears as ghost-text inline
  completion — `<Tab>` or `<Right>` accepts it.

### 8.2 Matching & ranking (fzf semantics)

- Subsequence matching: `dvtr` matches `dev.to · React …`. Non-matching items
  are **excluded**, not merely ranked down.
- Match score: consecutive-run bonus > word-boundary bonus (`/`, `-`, `.`,
  camelCase) > exact-case bonus > tighter match span.
- Final rank = `matchScore × frecency × sourceWeight`. Frecency comes from §7
  (`visitCount`, `typedCount`, recency decay). Source weight: open tab >
  typed history > link history.
- Matched characters are highlighted in the result rows.

### 8.3 Picker UX

- Dropdown under the command bar, ≤ 12 rows — transient per §4 zen rules;
  gone on accept or `<Esc>`.
- Keys inside the picker: `<C-j>` / `<C-k>` (aliases `<C-n>` / `<C-p>`) move ·
  `<Enter>` open here · `<C-Enter>` open in new tab · `<Esc>` close and
  restore the prior mode.
- Selected row shows the full URL + last-visited time in the status line.

### 8.4 Performance budget

- In-memory index over open tabs + the most recent N history entries
  (`history.indexSize`, default 20 000), maintained incrementally from store
  events.
- Keystroke → painted results in < 50 ms; superseded queries are cancelled;
  matching moves off the UI thread if profiling demands it.

---

## 9. Module Architecture & State Distribution Contract

```
┌───────────────────────────────────────────────────────────────────────┐
│ TypeScript / Svelte 5 Chrome (THE BRAIN & ORCHESTRATOR)               │
│ - Keybinding Engine & Modal Parser (NORMAL, INSERT, etc.)             │
│ - Command Registry & All Plugins (open, find, picker, media, groups)  │
│ - Authoritative Tab Metadata store (titles, URLs, group assignments)  │
│ - Ephemeral UI state (combobox cursor, draft text, overlays)          │
│ - Optimistic state machine (mute, pin, groups, tab order)             │
│ - Pending state machine (pendingTabId for anti-tearing switches)      │
├───────────────────────────────────────────────────────────────────────┤
│ Tauri IPC Layer (tauri-specta typed commands + continuous channels)   │
├───────────────────────────────────────────────────────────────────────┤
│ Rust Backend Core & CEF (THE EXECUTOR & SYNCHRONIZER)                 │
│ - TabManager (Native Handle Map: TabId -> CefBrowser & OS NSView/HWND)│
│ - Anti-Tearing Viewport Synchronizer (First-Frame / Presentation Ack) │
│ - Pre-Key Gatekeeper (Microsecond AtomicU8 check in OnPreKeyEvent)    │
│ - Hardware Telemetry Ingestion (CefAudioHandler, CefDisplayHandler)   │
│ - Process Lifecycle & Crash Recovery (OnRenderProcessTerminated)      │
│ - HistoryStore (rusqlite) & BookmarkStore (SQLite)                    │
└───────────────────────────────────────────────────────────────────────┘
```

Rules:
- **TypeScript owns business logic, plugins, and tab metadata:** Tab grouping, keybinding evaluation, command execution, and prompt/picker interactions run entirely in TypeScript for rapid extensibility.
- **Rust owns native handles and OS hardware synchronization:** CEF browser handles, OS subview z-ordering, `AtomicU8` modal flag for `OnPreKeyEvent`, raw audio muting, and SQLite databases.
- **Optimistic vs. Non-Optimistic Updates:** Non-visual or non-viewport changes update in TypeScript instantly (0.00ms latency) and fire-and-forget to Rust. Viewport-altering changes (switching tabs, creating tabs, navigating URLs) use synchronized frame acknowledgment to completely eliminate visual tearing between the chrome status line and the web page rendering.

### 9.1 State Distribution & Update Classification Matrix

| State Entity | Authoritative Owner | Update Strategy | IPC Flow | Rationale |
|---|---|---|---|---|
| **Core Modal Mode** (`NORMAL`, `INSERT`) | **TypeScript** | **Sync Flag Mirror** | TS → Rust (`set_mode`) | TS owns modal state machine; Rust mirrors in `AtomicU8` for sub-microsecond pre-key checks. |
| **Tab Mute / Unmute** | **TypeScript** | **Optimistic** | TS (local `$state` 0ms) → Rust (`set_audio_muted`) | No visual tearing. Speaker icon updates instantly; audio pipeline silences in background. |
| **Tab Pinning & Reorder** | **TypeScript** | **Optimistic** | TS (local `$state` 0ms) → Rust | Pure UI layout transition; no CEF re-render needed. |
| **Tab Groups** (`TabGroup[]`) | **TypeScript** | **Optimistic** | TS (local `$state` 0ms) → Rust (persists to SQLite) | Group chips and sidebar reflect edits instantly. |
| **Close Tab (`:q`)** | **TypeScript** | **Optimistic + Grace** | TS (local `$state` 0ms) → Rust (`close_tab`) | Tab drops immediately from tab bar; 4s undo toast mounts; CEF destroys process in background. |
| **Tab Switch (`gt`, `3gt`, picker)** | **TypeScript + Rust** | **Non-Optimistic (Synchronized Ack)** | TS (`pendingTabId`) → Rust (`switch_tab`) → CEF swap/paint → Rust `tab_activated` → TS (`activeTabId`) | **Anti-Tearing:** Prevents status bar title/URL desynchronizing from CEF web viewport during compositor wake-up. |
| **New Tab Creation** | **TypeScript + Rust** | **Non-Optimistic (Synchronized Ack)** | TS generates ID → Rust creates CEF host → Rust `tab_created` → TS mounts | Prevents blank/stale viewport during initial native handle allocation. |
| **Active Open Tabs (`Tab[]` metadata)** | **TypeScript** | **Local First** | TS store updated via engine events | TS holds rich metadata (title, URL, favicon, media heuristics); Rust only holds raw pointers. |
| **Pending Keystrokes & Count** (`3`, `g`) | **TypeScript** | **Local First** | Rust raw key stream → TS parser | Chords, timeouts, and counts evaluate in TS with zero native recompilation needed. |
| **Browsing History** (`Visit[]`) | **Rust** (SQLite) | **Query on demand** | TS queries top 10 on input (`o`, `,h`) | 50,000+ entries stay in SQLite; only search hits cross IPC. |
| **Hardware Audio Stream** | **Rust** (CEF) | **Push Event** | Rust (`CefAudioHandler`) → TS event `audio_changed` | Chromium audio pipeline notifies TS to update status bar `🔊 N` badge and `M` jump ring. |
| **Process Crash / OOM** | **Rust** (CEF) | **Push Event** | Rust (`OnRenderProcessTerminated`) → TS event `tab_crashed` | Rust traps OOM/crashes natively; notifies TS to display recovery toast. |

### 9.2 Core State Entities

```text
TabMetadata { id, url, title, groupId?, pinned, audible, muted, mediaKind,
              lastAudibleAt, lastActiveAt, canGoBack, canGoForward, zoom }
TabGroup    { id, name, color, collapsed, source: ai|manual }
Bookmark    { id, url, title, tags: string[], createdAt }
Mode        = NORMAL | INSERT | SEARCH | HINT | COMMAND
KeyState    { pendingKeys: [], pendingCount: number|null, mode: Mode }
Session     { windows: [{ tabs: TabMetadata[], groups: TabGroup[] }], closedStack: TabMetadata[] }
Visit       { id, url, domain, title, firstVisitAt, lastVisitAt, visitCount,
              typedCount, transition }
PickerState { source, query, matches[], selectedIndex }
```

### 9.3 Synchronized & Optimistic Event Flows

**Anti-Tearing Tab Switch Flow (`3gt` pressed):**
1. Raw OS key arrives at Rust `CefKeyboardHandler::OnPreKeyEvent`.
2. Rust checks `GLOBAL_MODE.load(Ordering::Relaxed)`. Since it is `NORMAL`, Rust returns `true` (Chromium page never sees the key) and forwards raw key to TS via IPC channel.
3. TS `KeybindingEngine` parses sequence `count=3, cmd=tab.select`.
4. TS sets `pendingTabId = 3` (acknowledging user intent immediately without switching the status bar title/URL).
5. TS sends `invoke('switch_tab', { id: 3 })` to Rust.
6. Rust `TabManager`:
   - Calls `old_browser.get_host().was_hidden(true)` and drops focus.
   - Raises target tab's native OS child view (`NSView` / `HWND`) to the front.
   - Calls `target_browser.get_host().was_hidden(false)` and `set_focus(true)`.
   - Listens for the compositor's presentation / first-frame paint.
7. Rust emits IPC event `tab_activated { id: 3 }`.
8. TS updates `activeTabId = 3` and clears `pendingTabId`. The status bar and CEF viewport update on the exact same display refresh cycle.

**Optimistic Tab Mute Flow (`M` or click):**
1. TS toggles `tab.muted = true` in local Svelte `$state` in **0.00ms**.
2. Status bar updates speaker icon instantly.
3. TS fires fire-and-forget `invoke('set_audio_muted', { id: tab.id, muted: true })`.
4. Rust calls `browser.get_host().set_audio_muted(true)` in native CEF background.

---

## 10. Extensibility & Plugin Architecture (Bottom Bar & Commands)

The status bar and command inputs follow an inverted control model inspired by
Neovim (`lualine`) and VS Code / Raycast: **Core owns the mode state machine;
plugins render status slots or supply command/combobox logic.**

### 10.1 Keybinding Safety: Inversion of Control
- **Plugins never bind keys directly.** A plugin exposes an `id` and registers into the
  centralized Command Registry (§3.4).
- Keybindings live exclusively in the user's `keymap.toml` or defaults.
- **Static Conflict Detection at startup:**
  1. *Collision errors:* Fatal error if two commands map to the identical key sequence.
  2. *Prefix warning:* Flags ambiguous sequences like `g` vs `gt` (1000ms wait).
  3. *Ex-command collision:* Rejects duplicate `:command` aliases at registration.
- **Dual entry point:** Every `InputPlugin` is triggerable either via direct key shortcut
  or via Ex-command (`:open`, `:find`).

### 10.2 Category 1: ViewPlugin (Passive Status Slots)
Placed in `left`, `center`, or `right` slots of the 26px bar. Subscribes to events or polls:
```ts
interface ViewPlugin {
  id: string;
  position: 'left' | 'center' | 'right';
  order: number;
  render: Component; // Svelte component
  subscribe?: (notify: (data: any) => void) => () => void;
  onClick?: () => void;
}
```
*Core View Plugins:*
- `mode-badge`: Renders `[NORMAL]` / `[INSERT]` (reads core Mode state, does not define it).
- `tab-pos`: `tabs 2/4`
- `media-badge`: `🔊 1` (click triggers `M` jump)
- `url-display`: Title / domain (hybrid or full)
- `load-status`: `⠋ loading` / `✓ loaded` / `⛔ blocked`
- `clock`: Time display

### 10.3 Category 2: InputPlugin (Modal Command Bar & Upward Combobox)
When triggered, hides the passive slots and takes over the bottom bar, optionally
rendering the upward combobox powered by `bits-ui`:
```ts
interface InputPlugin<T = any> {
  id: string;                       // e.g. "input.open"
  commandAliases?: string[];        // e.g. [":open", ":o"]
  prompt: string;                   // e.g. "open", "/", ":"
  queryItems?: (query: string) => Promise<ComboboxItem<T>[]>;
  getHint?: (query: string) => string; // right-aligned live hint (e.g. "[3/12 found]")
  onPreview?: (item: ComboboxItem<T>) => void;
  onSelect: (item: ComboboxItem<T> | null, rawQuery: string) => void;
}
```
*Core Input Plugins:*
- `input.open` (`o`, `O`): Address editing + web search + upward combobox (history, open tabs, search suggestions).
- `input.find` (`/`): Find in page, live `[idx/total]` count, Enter = first match.
- `input.command` (`:`): Ex-command prompt with autocomplete over Command Registry.
- `input.tab-picker` (`,b` / `,t`): Fuzzy tab switcher.
- `input.history` (`,h`): Fuzzy history search.

### 10.4 Category 3: NotificationPlugin (Flash Alerts & Undo Toasts)
Transient status bar overlays that display operational notifications or time-sensitive
action hooks (e.g. undoing a closed tab):
```ts
interface NotificationToast {
  id: string;
  message: string;             // e.g. "Closed: GitHub (tauri-apps)"
  actionKey?: string;          // e.g. "u"
  actionLabel?: string;        // e.g. "undo"
  durationMs: number;          // e.g. 4000
  onAction?: () => void;       // executed if actionKey pressed before timeout
}
```
*Core Usage:*
- **Tab Restore:** `:q` closes a tab and triggers an undo toast: `[Closed tab] Press 'u' to restore (4s)`.
  While active, typing `u` in NORMAL mode re-opens the closed tab from the `closedStack`. Once the toast fades,
  `u` reverts to its idle state.

---

## 11. Roadmap (feature-first milestones)

| Milestone | Delivers | Acceptance check |
|-----------|----------|------------------|
| M1 — Shell & tabs | window, tabs, navigation, address input, history recording (write-path only) | browse 5 sites, open/close/move tabs; visits land in HistoryStore |
| M2 — Modal input | ModeManager, keybinding engine, full §3.2 keymap, hints, find | 30 min of browsing, keyboard only |
| M3 — Zen UI | status line, command bar, tab overlay, zen levels, themes | persistent chrome = one 24 px line |
| M4 — Media tab | MediaMonitor, `M` jump + cycle, 🔊 indicators | 3 media tabs open → `M` cycles correctly, muted deprioritized |
| M5 — AI grouping | provider interface, `:group`, preview, apply/undo, group sidebar | 20 mixed tabs → sensible groups, undo restores, failure is silent |
| M6 — History & fuzzy | HistoryStore UI, retention/pruning, FuzzyPicker + sources (tabs/history/commands), `,b`/`,h`, command-bar autocomplete | <50 ms fuzzy over 20k entries; `:clearhistory --domain` truly forgets |
| M7 — Polish | sessions/restore, per-site passthrough, `?` help popup, auto-suggest threshold | config-driven, survives restart |

M2 is the riskiest/most valuable — get the mode machine and keybinding engine
right early; everything else hangs off the command registry it feeds.

---

## 12. Ratified V1 Implementation Decisions

These 7 architectural decisions govern window layout, memory management, and process composition for the V1 build:

1. **Window Composition & Overlay Model:**
   - **Choice: Transparent / Frameless Overlay (Option C)**.
   - CEF browser instance renders full-window for maximum hardware acceleration and video frame-rate consistency.
   - Svelte chrome (26px bottom status line, upward combobox, Telescope tab picker, and hint overlays) mounts as a high-performance, frameless floating layer above the CEF view.
2. **Icon Rendering Pipeline:**
   - **Choice: Global Devicon CSS + `<i>` Element Tags**.
   - `devicon.min.css` loaded globally in Svelte chrome root layout.
   - Icons rendered purely via standard HTML `<i class="devicon-<name>-<variant> colored"></i>` elements, avoiding multi-file Svelte icon component bundling overhead and keeping the UI layer lean.
3. **Auto-INSERT Behavior:**
   - **Choice: Explicit ONLY for V1 (Option B)**.
   - Clicking an input field focuses it, but does **not** automatically switch modes. The user must explicitly press `i` to enter `INSERT` mode.
   - Keeps navigation deterministic; will be re-evaluated after real-world dogfooding.
4. **CEF Binary Cache & Tooling:**
   - **Choice: Local Shared Cache via `export-cef-dir` (Option A)**.
   - Binaries are extracted once into `$HOME/.local/share/cef`. All local cargo builds link to this shared path, avoiding multi-gigabyte re-downloads during compile iterations.
5. **Configuration & Keybinding Layer:**
   - **Choice: Single Typed TypeScript File (`src/config/keymap.ts`)**.
   - No external TOML/JSON runtime parsing overhead for V1. Full compile-time type safety over `InputPlugin`, `ViewPlugin`, and Command IDs with instant Vite hot-module reloading.
6. **Multi-Tab Process & Memory Architecture:**
   - **Choice: Multiple `CefBrowser` Instances with Native OOM Handling (Option A)**.
   - Each tab is an independent `CefBrowserHost` managed by the Rust `TabManager`. DOM and audio stay alive in background tabs.
   - **Memory Spikes & Telemetry:** CEF's `CefRequestHandler::OnRenderProcessTerminated` catches `TS_PROCESS_OOM` and `TS_PROCESS_CRASHED` to flash recovery toasts (`Tab crashed: Out of Memory. Press 'r' to reload.`).
   - `CefMemoryPressureListener` monitors system-wide memory constraints to proactively throttle or discard stale background tabs.
7. **Web Storage & Cookie Persistence:**
   - Handled natively by CEF via `CefSettings::cache_path` pointing to the OS user data directory.
   - Cookies, HTTP disk cache, IndexedDB, and LocalStorage persist across restarts with `persist_session_cookies = 1`.
   - Ephemeral / Incognito browsing is supported via in-memory `CefRequestContext` (`cache_path = ""`).

---

## 13. Open Decisions (parked for post-V1)

1. `M` for media vs. vim's middle-of-screen scroll — currently: media wins.
2. Leader key: `,g` for grouping implies a `,` leader — confirm vs. plain `:group`.
3. Hint alphabet: home-row `asdfghjkl` (default) vs. `fjdksla;` variants.
4. AI provider default + whether a local model ships as an option at M5.
5. Frecency weights and the default 90-day retention — tune with real usage.
6. Picker navigation default: `<C-j/k>` vs `<C-n/p>` (currently both alias).
7. Encrypt history DB at rest? Parked — local-only, no sync at ship.
