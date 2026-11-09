mod tab_manager;

use tab_manager::*;
use tauri::Manager;

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .runtime(tauri_runtime_wry::Wry::default())
        .plugin(tauri_plugin_opener::init())
        .setup(|app| {
            let tm = TabManager::new(app.handle().clone());
            app.manage(tm);
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            create_native_tab,
            navigate_native_tab,
            switch_native_tab,
            close_native_tab,
            update_viewport_bounds,
            set_mode,
            get_mode,
            get_tabs,
            get_active_tab_id,
            toggle_audio,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
