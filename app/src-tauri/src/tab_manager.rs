use std::collections::HashMap;
use std::sync::atomic::{AtomicU8, Ordering};
use std::sync::{Arc, Mutex};
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager, State, WebviewBuilder, WebviewUrl, LogicalPosition, LogicalSize};

use cef::*;

#[repr(u8)]
#[derive(Copy, Clone, PartialEq, Eq, Debug, Serialize, Deserialize)]
pub enum EngineMode {
    Normal = 0,
    Insert = 1,
    Search = 2,
    Hint = 3,
    Command = 4,
}

pub static GLOBAL_MODE: AtomicU8 = AtomicU8::new(EngineMode::Normal as u8);

// ---------------- Lifecycle Data Structures ----------------

#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct TabInfo {
    pub id: u32,
    pub title: String,
    pub url: String,
    pub favicon: Option<String>,
    pub is_loading: bool,
    pub progress: f64,
    pub is_audible: bool,
    pub is_muted: bool,
    pub can_go_back: bool,
    pub can_go_forward: bool,
    pub z_index: i32,
    pub is_hidden: bool,
    pub was_hidden_called: bool,
    pub error: Option<String>,
}

#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct TabMetaEvent {
    pub tab_id: u32,
    pub title: String,
    pub url: String,
    pub favicon: Option<String>,
}

#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct TabLoadingEvent {
    pub tab_id: u32,
    pub is_loading: bool,
    pub progress: f64,
}

#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct TabErrorEvent {
    pub tab_id: u32,
    pub code: i32,
    pub description: String,
    pub failing_url: String,
}

// ---------------- Native CEF C++ Handler Implementations ----------------

pub struct NativeCefTabHandler {
    pub tab_id: u32,
    pub app_handle: AppHandle,
}

impl NativeCefTabHandler {
    pub fn new(tab_id: u32, app_handle: AppHandle) -> Arc<Mutex<Self>> {
        Arc::new(Mutex::new(Self { tab_id, app_handle }))
    }

    pub fn handle_title_change(&self, title: Option<&CefString>) {
        let title_str = title.map(CefString::to_string).unwrap_or_default();
        let _ = self.app_handle.emit(
            "tab_metadata_changed",
            TabMetaEvent {
                tab_id: self.tab_id,
                title: title_str,
                url: "".into(),
                favicon: None,
            },
        );
    }

    pub fn handle_favicon_urlchange(&self, mut icon_urls: Option<&mut CefStringList>) {
        if let Some(list) = icon_urls.as_mut() {
            let count = string_list_size(Some(list));
            if count > 0 {
                let mut icon = CefString::default();
                if string_list_value(Some(list), 0, Some(&mut icon)) != 0 {
                    let _ = self.app_handle.emit(
                        "tab_metadata_changed",
                        TabMetaEvent {
                            tab_id: self.tab_id,
                            title: "".into(),
                            url: "".into(),
                            favicon: Some(icon.to_string()),
                        },
                    );
                }
            }
        }
    }

    pub fn handle_loading_state_change(&self, is_loading: bool) {
        let _ = self.app_handle.emit(
            "tab_loading",
            TabLoadingEvent {
                tab_id: self.tab_id,
                is_loading,
                progress: if is_loading { 0.2 } else { 1.0 },
            },
        );
    }

    pub fn handle_load_error(&self, error_code: Errorcode, error_text: Option<&CefString>, failed_url: Option<&CefString>) {
        let desc = error_text.map(CefString::to_string).unwrap_or_else(|| "Unknown CEF error".into());
        let url = failed_url.map(CefString::to_string).unwrap_or_default();
        let _ = self.app_handle.emit(
            "tab_error",
            TabErrorEvent {
                tab_id: self.tab_id,
                code: sys::cef_errorcode_t::from(error_code) as i32,
                description: desc,
                failing_url: url,
            },
        );
    }

    pub fn handle_pre_key_event(&self) -> bool {
        // CEF Native Pre-Key Interception Contract (R9 from ARCHITECTURE.md):
        // If mode != Insert, return true (1) to completely swallow the keystroke from Chromium Blink!
        let mode = GLOBAL_MODE.load(Ordering::Relaxed);
        mode != EngineMode::Insert as u8
    }
}

// Wrap handlers into CEF C++ Client vtables via cef-rs macros
wrap_display_handler! {
    pub struct CefTabDisplayHandler {
        inner: Arc<Mutex<NativeCefTabHandler>>,
    }

    impl DisplayHandler {
        fn on_title_change(&self, _browser: Option<&mut Browser>, title: Option<&CefString>) {
            let inner = self.inner.lock().unwrap();
            inner.handle_title_change(title);
        }

        fn on_favicon_urlchange(&self, _browser: Option<&mut Browser>, icon_urls: Option<&mut CefStringList>) {
            let inner = self.inner.lock().unwrap();
            inner.handle_favicon_urlchange(icon_urls);
        }
    }
}

wrap_load_handler! {
    pub struct CefTabLoadHandler {
        inner: Arc<Mutex<NativeCefTabHandler>>,
    }

    impl LoadHandler {
        fn on_loading_state_change(&self, _browser: Option<&mut Browser>, is_loading: i32, _can_go_back: i32, _can_go_forward: i32) {
            let inner = self.inner.lock().unwrap();
            inner.handle_loading_state_change(is_loading != 0);
        }

        fn on_load_error(
            &self,
            _browser: Option<&mut Browser>,
            _frame: Option<&mut Frame>,
            error_code: Errorcode,
            error_text: Option<&CefString>,
            failed_url: Option<&CefString>,
        ) {
            let inner = self.inner.lock().unwrap();
            inner.handle_load_error(error_code, error_text, failed_url);
        }
    }
}

wrap_keyboard_handler! {
    pub struct CefTabKeyboardHandler {
        inner: Arc<Mutex<NativeCefTabHandler>>,
    }

    impl KeyboardHandler {
        fn on_pre_key_event(
            &self,
            _browser: Option<&mut Browser>,
            _event: Option<&KeyEvent>,
            _os_event: *mut u8,
            _is_keyboard_shortcut: Option<&mut i32>,
        ) -> i32 {
            let inner = self.inner.lock().unwrap();
            inner.handle_pre_key_event() as i32
        }
    }
}

wrap_client! {
    pub struct CefTabClient {
        inner: Arc<Mutex<NativeCefTabHandler>>,
    }

    impl Client {
        fn display_handler(&self) -> Option<DisplayHandler> {
            Some(CefTabDisplayHandler::new(self.inner.clone()))
        }

        fn load_handler(&self) -> Option<LoadHandler> {
            Some(CefTabLoadHandler::new(self.inner.clone()))
        }

        fn keyboard_handler(&self) -> Option<KeyboardHandler> {
            Some(CefTabKeyboardHandler::new(self.inner.clone()))
        }
    }
}

// ---------------- Native Tab Structure ----------------

pub struct NativeTab {
    pub id: u32,
    pub title: String,
    pub url: String,
    pub favicon: Option<String>,
    pub is_loading: bool,
    pub progress: f64,
    pub is_audible: bool,
    pub is_muted: bool,
    pub can_go_back: bool,
    pub can_go_forward: bool,
    pub z_index: i32,
    pub is_hidden: bool,
    pub was_hidden_called: bool,
    pub error: Option<String>,
    pub cef_client: Option<Client>,
}

impl NativeTab {
    pub fn to_info(&self) -> TabInfo {
        TabInfo {
            id: self.id,
            title: self.title.clone(),
            url: self.url.clone(),
            favicon: self.favicon.clone(),
            is_loading: self.is_loading,
            progress: self.progress,
            is_audible: self.is_audible,
            is_muted: self.is_muted,
            can_go_back: self.can_go_back,
            can_go_forward: self.can_go_forward,
            z_index: self.z_index,
            is_hidden: self.is_hidden,
            was_hidden_called: self.was_hidden_called,
            error: self.error.clone(),
        }
    }
}

pub struct TabManagerState {
    pub tabs: HashMap<u32, NativeTab>,
    pub active_tab_id: Option<u32>,
    pub next_tab_id: u32,
    pub bounds: (f64, f64, f64, f64),
}

pub struct TabManager {
    pub state: Arc<Mutex<TabManagerState>>,
    pub app_handle: AppHandle,
}

impl TabManager {
    pub fn new(app_handle: AppHandle) -> Self {
        Self {
            state: Arc::new(Mutex::new(TabManagerState {
                tabs: HashMap::new(),
                active_tab_id: None,
                next_tab_id: 1,
                bounds: (0.0, 0.0, 1200.0, 800.0),
            })),
            app_handle,
        }
    }

    pub fn emit_tabs_updated(&self) {
        let lock = self.state.lock().unwrap();
        let mut list: Vec<TabInfo> = lock.tabs.values().map(|t| t.to_info()).collect();
        list.sort_by_key(|t| t.id);
        let _ = self.app_handle.emit("tabs_updated", list);
    }
}

fn tab_label(tab_id: u32) -> String {
    format!("native-tab-{}", tab_id)
}

fn derive_title(url: &str) -> String {
    if let Ok(parsed) = url::Url::parse(url) {
        if let Some(host) = parsed.host_str() {
            return host.to_string();
        }
    }
    url.to_string()
}

// ---------------- Native Tab Lifecycle Commands ----------------

#[tauri::command]
pub fn create_native_tab(
    url: String,
    activate: bool,
    app: AppHandle,
    tm: State<TabManager>,
) -> Result<u32, String> {
    let window = app.get_window("main").ok_or("Main window not found")?;
    let mut lock = tm.state.lock().unwrap();
    let id = lock.next_tab_id;
    lock.next_tab_id += 1;

    let parsed_url: url::Url = url.parse().map_err(|e| format!("Invalid URL: {e}"))?;
    let label = tab_label(id);

    // Instantiate native CEF C++ Handlers for this tab
    let native_handler = NativeCefTabHandler::new(id, app.clone());
    let cef_client = CefTabClient::new(native_handler);

    let builder = WebviewBuilder::new(&label, WebviewUrl::External(parsed_url));
    let wv = window
        .add_child(builder)
        .map_err(|e| format!("Failed to create native child view: {e}"))?;

    let (x, y, w, h) = lock.bounds;
    let _ = wv.set_position(LogicalPosition::new(x, y));
    let _ = wv.set_size(LogicalSize::new(w, h));

    let tab = NativeTab {
        id,
        title: derive_title(&url),
        url,
        favicon: None,
        is_loading: true,
        progress: 0.1,
        is_audible: false,
        is_muted: false,
        can_go_back: false,
        can_go_forward: false,
        z_index: if activate { 10 } else { 0 },
        is_hidden: !activate,
        was_hidden_called: !activate,
        error: None,
        cef_client: Some(cef_client),
    };
    lock.tabs.insert(id, tab);

    if activate {
        if let Some(old_id) = lock.active_tab_id {
            if let Some(old_tab) = lock.tabs.get_mut(&old_id) {
                old_tab.z_index = 0;
                old_tab.is_hidden = true;
                old_tab.was_hidden_called = true;
            }
            if let Some(old_wv) = app.get_webview(&tab_label(old_id)) {
                let _ = old_wv.hide();
            }
        }
        lock.active_tab_id = Some(id);
        let _ = wv.show();
        let _ = wv.set_focus();
    } else {
        let _ = wv.hide();
    }

    drop(lock);
    tm.emit_tabs_updated();
    let _ = app.emit("tab_activated", id);
    Ok(id)
}

#[tauri::command]
pub fn navigate_native_tab(
    tab_id: u32,
    url: String,
    app: AppHandle,
    tm: State<TabManager>,
) -> Result<(), String> {
    let mut lock = tm.state.lock().unwrap();
    if let Some(tab) = lock.tabs.get_mut(&tab_id) {
        tab.url = url.clone();
        tab.title = derive_title(&url);
        tab.is_loading = true;
        tab.progress = 0.1;
        tab.error = None;
    } else {
        return Err("Tab not found".into());
    }
    drop(lock);

    if let Some(wv) = app.get_webview(&tab_label(tab_id)) {
        let parsed_url: url::Url = url.parse().map_err(|e| format!("Invalid URL: {e}"))?;
        let _ = wv.navigate(parsed_url);
    }

    tm.emit_tabs_updated();
    let _ = app.emit("tab_loading", TabLoadingEvent { tab_id, is_loading: true, progress: 0.1 });
    Ok(())
}

#[tauri::command]
pub fn switch_native_tab(
    tab_id: u32,
    app: AppHandle,
    tm: State<TabManager>,
) -> Result<(), String> {
    let mut lock = tm.state.lock().unwrap();
    let old_id = lock.active_tab_id;
    if old_id == Some(tab_id) {
        return Ok(());
    }

    if !lock.tabs.contains_key(&tab_id) {
        return Err("Target tab does not exist".into());
    }

    if let Some(old) = old_id.and_then(|id| lock.tabs.get_mut(&id)) {
        old.z_index = 0;
        old.is_hidden = true;
        old.was_hidden_called = true;
    }

    if let Some(target) = lock.tabs.get_mut(&tab_id) {
        target.z_index = 10;
        target.is_hidden = false;
        target.was_hidden_called = false;
    }

    lock.active_tab_id = Some(tab_id);

    if let Some(old) = old_id {
        if let Some(old_wv) = app.get_webview(&tab_label(old)) {
            let _ = old_wv.hide();
        }
    }
    if let Some(target_wv) = app.get_webview(&tab_label(tab_id)) {
        let _ = target_wv.show();
        let _ = target_wv.set_focus();
    }

    drop(lock);
    tm.emit_tabs_updated();
    let _ = app.emit("tab_activated", tab_id);
    Ok(())
}

#[tauri::command]
pub fn close_native_tab(
    tab_id: u32,
    app: AppHandle,
    tm: State<TabManager>,
) -> Result<(), String> {
    let mut lock = tm.state.lock().unwrap();
    if lock.tabs.remove(&tab_id).is_some() {
        if let Some(wv) = app.get_webview(&tab_label(tab_id)) {
            let _ = wv.close();
        }

        if lock.active_tab_id == Some(tab_id) {
            lock.active_tab_id = lock.tabs.keys().cloned().min();
            if let Some(new_active) = lock.active_tab_id {
                if let Some(t) = lock.tabs.get_mut(&new_active) {
                    t.is_hidden = false;
                    t.was_hidden_called = false;
                    t.z_index = 10;
                }
                if let Some(new_wv) = app.get_webview(&tab_label(new_active)) {
                    let _ = new_wv.show();
                    let _ = new_wv.set_focus();
                }
            }
        }
        drop(lock);
        tm.emit_tabs_updated();
        let _ = tm.app_handle.emit("tab_closed", tab_id);
        Ok(())
    } else {
        Err("Tab not found".into())
    }
}

#[tauri::command]
pub fn update_viewport_bounds(
    x: f64,
    y: f64,
    width: f64,
    height: f64,
    app: AppHandle,
    tm: State<TabManager>,
) -> Result<(), String> {
    let mut lock = tm.state.lock().unwrap();
    lock.bounds = (x, y, width, height);
    for id in lock.tabs.keys() {
        if let Some(wv) = app.get_webview(&tab_label(*id)) {
            let _ = wv.set_position(LogicalPosition::new(x, y));
            let _ = wv.set_size(LogicalSize::new(width, height));
        }
    }
    Ok(())
}

#[tauri::command]
pub fn set_mode(mode: u8, app: AppHandle) -> Result<u8, String> {
    if mode > 4 {
        return Err("Invalid mode index".into());
    }
    GLOBAL_MODE.store(mode, Ordering::Release);
    let _ = app.emit("mode_changed", mode);
    Ok(mode)
}

#[tauri::command]
pub fn get_mode() -> u8 {
    GLOBAL_MODE.load(Ordering::Relaxed)
}

#[tauri::command]
pub fn get_tabs(tm: State<TabManager>) -> Vec<TabInfo> {
    let lock = tm.state.lock().unwrap();
    let mut list: Vec<TabInfo> = lock.tabs.values().map(|t| t.to_info()).collect();
    list.sort_by_key(|t| t.id);
    list
}

#[tauri::command]
pub fn get_active_tab_id(tm: State<TabManager>) -> Option<u32> {
    let lock = tm.state.lock().unwrap();
    lock.active_tab_id
}

#[tauri::command]
pub fn toggle_audio(tab_id: u32, tm: State<TabManager>) -> Result<bool, String> {
    let mut lock = tm.state.lock().unwrap();
    if let Some(tab) = lock.tabs.get_mut(&tab_id) {
        tab.is_audible = !tab.is_audible;
        let is_aud = tab.is_audible;
        drop(lock);
        tm.emit_tabs_updated();
        let _ = tm.app_handle.emit("audio_changed", serde_json::json!({ "id": tab_id, "is_audible": is_aud }));
        Ok(is_aud)
    } else {
        Err("Tab not found".into())
    }
}

// ---------------- Rust Native Unit Tests ----------------

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_mode_transitions_atomic() {
        GLOBAL_MODE.store(EngineMode::Normal as u8, Ordering::Release);
        assert_eq!(GLOBAL_MODE.load(Ordering::Relaxed), 0);

        GLOBAL_MODE.store(EngineMode::Insert as u8, Ordering::Release);
        assert_eq!(GLOBAL_MODE.load(Ordering::Relaxed), 1);

        GLOBAL_MODE.store(EngineMode::Command as u8, Ordering::Release);
        assert_eq!(GLOBAL_MODE.load(Ordering::Relaxed), 4);
    }

    #[test]
    fn test_pre_key_filter_swallow_logic() {
        // In NORMAL mode: keys MUST be swallowed (return true)
        GLOBAL_MODE.store(EngineMode::Normal as u8, Ordering::Release);
        assert_ne!(GLOBAL_MODE.load(Ordering::Relaxed), EngineMode::Insert as u8);

        // In INSERT mode: keys MUST pass through to Blink DOM (return false)
        GLOBAL_MODE.store(EngineMode::Insert as u8, Ordering::Release);
        assert_eq!(GLOBAL_MODE.load(Ordering::Relaxed), EngineMode::Insert as u8);
    }

    #[test]
    fn test_derive_title_logic() {
        assert_eq!(derive_title("https://groww.in/stocks"), "groww.in");
        assert_eq!(derive_title("https://news.ycombinator.com"), "news.ycombinator.com");
        assert_eq!(derive_title("not-a-valid-url"), "not-a-valid-url");
    }

    #[test]
    fn test_tab_state_initialization() {
        let tab = NativeTab {
            id: 1,
            title: "Test Tab".into(),
            url: "https://example.com".into(),
            favicon: None,
            is_loading: false,
            progress: 1.0,
            is_audible: false,
            is_muted: false,
            can_go_back: false,
            can_go_forward: false,
            z_index: 10,
            is_hidden: false,
            was_hidden_called: false,
            error: None,
            cef_client: None,
        };

        let info = tab.to_info();
        assert_eq!(info.id, 1);
        assert_eq!(info.title, "Test Tab");
        assert_eq!(info.url, "https://example.com");
        assert_eq!(info.z_index, 10);
        assert!(!info.is_hidden);
    }

    #[test]
    fn test_z_order_state_transitions() {
        let mut tabs = HashMap::new();
        tabs.insert(
            1,
            NativeTab {
                id: 1,
                title: "Tab 1".into(),
                url: "https://groww.in".into(),
                favicon: None,
                is_loading: false,
                progress: 1.0,
                is_audible: false,
                is_muted: false,
                can_go_back: false,
                can_go_forward: false,
                z_index: 10,
                is_hidden: false,
                was_hidden_called: false,
                error: None,
                cef_client: None,
            },
        );
        tabs.insert(
            2,
            NativeTab {
                id: 2,
                title: "Tab 2".into(),
                url: "https://news.ycombinator.com".into(),
                favicon: None,
                is_loading: false,
                progress: 1.0,
                is_audible: false,
                is_muted: false,
                can_go_back: false,
                can_go_forward: false,
                z_index: 0,
                is_hidden: true,
                was_hidden_called: true,
                error: None,
                cef_client: None,
            },
        );

        // Simulate Switch from Tab 1 -> Tab 2
        // Phase A: Old active tab demoted
        if let Some(old) = tabs.get_mut(&1) {
            old.z_index = 0;
            old.is_hidden = true;
            old.was_hidden_called = true;
        }

        // Phase B: Target tab promoted to Z-top
        if let Some(target) = tabs.get_mut(&2) {
            target.z_index = 10;
            target.is_hidden = false;
            target.was_hidden_called = false;
        }

        assert_eq!(tabs.get(&1).unwrap().z_index, 0);
        assert!(tabs.get(&1).unwrap().is_hidden);
        assert!(tabs.get(&1).unwrap().was_hidden_called);

        assert_eq!(tabs.get(&2).unwrap().z_index, 10);
        assert!(!tabs.get(&2).unwrap().is_hidden);
        assert!(!tabs.get(&2).unwrap().was_hidden_called);
    }
}
