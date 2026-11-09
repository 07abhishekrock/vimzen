# Plan: Rust CEF TabManager Implementation

This plan outlines the architecture, data structures, and implementation steps for the **Rust CEF TabManager** in Vimzen. It aligns with `ARCHITECTURE.md` dividing duties into a **TypeScript orchestrator** and a **Rust native execution & frame synchronizer**.

---

## 1. Objectives & Scope

1. **Native Handle Management:** Hold raw C++ `CefBrowser` pointers and OS child view handles (`NSView` on macOS, `HWND` on Windows).
2. **Anti-Tearing Viewport Synchronizer:** Implement two-phase tab switching gated on compositor presentation to ensure the Chrome status line and the web page swap on the exact same frame.
3. **Microsecond Pre-Key Filter:** Synchronously block keys in `CefKeyboardHandler::OnPreKeyEvent` via an `AtomicU8` mode flag mirror and pipe raw key events to TypeScript.
4. **Hardware Telemetry Forwarding:** Ingest native audio (`CefAudioHandler`), load state (`CefLoadHandler`), and URL/title changes (`CefDisplayHandler`), streaming events over Tauri IPC.
5. **Process Lifecycle & OOM Guard:** Monitor render processes (`CefRequestHandler`) and trigger recovery events on crash or OOM.

---

## 2. Core Rust Data Structures

```rust
use std::collections::HashMap;
use std::sync::atomic::{AtomicU8, Ordering};
use std::sync::Arc;
use cef::{CefBrowser, CefWindowHandle};

#[repr(u8)]
#[derive(Copy, Clone, PartialEq, Eq)]
pub enum EngineMode {
    Normal = 0,
    Insert = 1,
    Search = 2,
    Hint = 3,
    Command = 4,
}

pub static GLOBAL_MODE: AtomicU8 = AtomicU8::new(EngineMode::Normal as u8);

pub struct NativeTab {
    pub id: u32,
    pub browser: CefBrowser,
    pub window_handle: CefWindowHandle, // NSView / HWND
}

pub struct TabManager {
    tabs: HashMap<u32, NativeTab>,
    active_tab_id: Option<u32>,
    pending_switch_id: Option<u32>,
    app_handle: tauri::AppHandle,
}
```

---

## 3. Implementation Steps

### Phase 1: Mode Mirror & Pre-Key Filter
- [ ] **Mode Sync Command:** Implement Tauri command `set_mode(mode: u8)` that updates `GLOBAL_MODE.store(mode, Ordering::Release)`.
- [ ] **Synchronous Interception in `OnPreKeyEvent`:**
  - If `GLOBAL_MODE.load(Ordering::Relaxed) != EngineMode::Insert`, return `true` to swallow the key from Blink DOM.
  - Forward the raw key event (key code, modifiers, character) across an async channel/IPC event to TypeScript (`key_event`).
  - If `Insert`, return `false` to let Chromium process input normally.

### Phase 2: Native Viewport Swapping & OS Child Views
- [ ] **Tab Creation (`create_tab`):**
  - Allocate a unique `tab_id`.
  - Create `CefBrowser` via `CefBrowserHost::CreateBrowser` attached to the main window as a child view.
  - Call `was_hidden(true)` immediately if created in the background.
  - Store in `TabManager.tabs`.
- [ ] **OS Handle Manipulation (macOS NSView / Windows HWND):**
  - Implement helper functions to hide/show and re-order child views (e.g. `[view setHidden:YES]`, `orderFront:nil` / `ShowWindow(hwnd, SW_HIDE)`).

### Phase 3: Anti-Tearing Frame Synchronization (Z-Order Guarded Swap)
- [ ] **Zero-Flicker Z-Order Swap (`switch_tab`):**
  1. Record `pending_switch_id = target_id`.
  2. **Wake Target Underneath (Cover Phase):**
     - Unhide the target tab's native view, but place it *immediately beneath* the currently active tab in the window's Z-order (`orderWindow:NSWindowBelow` on macOS / `SetWindowPos(..., SWP_NOACTIVATE | SWP_SHOWWINDOW)` on Windows).
     - Resume target Chromium compositor: `target_browser.get_host().was_hidden(false)`.
     - *Crucial:* Do NOT hide the current active tab yet. The old tab remains on Z-top showing its last painted frame, preventing any blank or white frame flicker while the target tab warms up its GPU buffers.
  3. **Compositor Presentation Ack:**
     - Await target tab's first frame paint/presentation acknowledgment (via `OnLoadingProgressChange` / compositor paint hook or next vsync interval).
  4. **Promote & Sleep Phase:**
     - Promote target tab's view to Z-top (`orderFront:` / `BringWindowToTop`).
     - Acquire keyboard focus: `target_browser.get_host().set_focus(true)`.
     - Put previous active tab to sleep:
       - Drop focus: `old_browser.get_host().set_focus(false)`.
       - Throttle paints: `old_browser.get_host().was_hidden(true)`.
       - Hide native view (`[old_view setHidden:YES]` / `ShowWindow(old_hwnd, SW_HIDE)`).
  5. Emit Tauri event `tab_activated { id: target_id }` and clear `pending_switch_id`.

### Phase 4: Optimistic Fire-and-Forget Commands
- [ ] **Audio Muting (`set_audio_muted`):**
  - Lookup `tab_id` in `TabManager.tabs`.
  - Call `browser.get_host().set_audio_muted(muted)`.
- [ ] **Tab Destruction (`close_tab`):**
  - Call `browser.get_host().close_browser(true)`.
  - Destroy native child view and remove from `TabManager.tabs`.

### Phase 5: Hardware & Lifecycle Telemetry Ingestion
- [ ] **Audio Stream Handler (`CefAudioHandler`):**
  - Emit `audio_changed { id, is_audible: bool }` on audio start/stop.
- [ ] **Display & Load Handlers:**
  - Stream `title_changed { id, title }`, `address_changed { id, url }`, and `loading_changed { id, is_loading, can_go_back, can_go_forward }`.
- [ ] **Crash & OOM Handler (`CefRequestHandler::OnRenderProcessTerminated`):**
  - Catch `TS_PROCESS_OOM` and `TS_PROCESS_CRASHED`.
  - Emit `tab_crashed { id, reason }` to invoke the TypeScript recovery toast.

---

## 4. Verification & Testing Criteria

1. **No Key Leakage:** Open an interactive text box (e.g., Google search input). In NORMAL mode, spam `j`, `k`, `3gt`. Ensure no characters appear in the text box.
2. **Anti-Tearing Test:** Rapidly cycle tabs with `gt`. Verify that the status line URL/title changes synchronously with the web viewport without visual desync or flashing blank frames.
3. **Background Audio Continuity:** Start a YouTube audio track, switch to another tab. Confirm sound continues while paints halt. Mute from TypeScript and verify near-instant silence.
4. **OOM Recovery:** Simulate render process crash and ensure TypeScript displays the undo/recovery prompt.
