import { invoke } from '@tauri-apps/api/core';
import { listen, type UnlistenFn } from '@tauri-apps/api/event';

export interface TabInfo {
  id: number;
  title: string;
  url: string;
  favicon: string | null;
  is_loading: boolean;
  progress: number;
  is_audible: boolean;
  is_muted: boolean;
  can_go_back: boolean;
  can_go_forward: boolean;
  z_index: number;
  is_hidden: boolean;
  was_hidden_called: boolean;
  error: string | null;
}

export interface TabMetaEvent {
  tab_id: number;
  title: string;
  url: string;
  favicon: string | null;
}

export interface TabLoadingEvent {
  tab_id: number;
  is_loading: boolean;
  progress: number;
}

export interface TabErrorEvent {
  tab_id: number;
  code: number;
  description: string;
  failing_url: string;
}

export const isTauri = typeof window !== 'undefined' && '__TAURI_INTERNALS__' in window;

/**
 * TabManager Client SDK
 * Complete Lifecycle & Hardware Event Contract matching ARCHITECTURE.md §2 & §9.
 */
export const tabManager = {
  // ---------------- Tab Mutation Commands ----------------

  /** Spawns a new native top-level OS child view for the given URL. */
  createTab: async (url: string, activate = true): Promise<number> => {
    return await invoke<number>('create_native_tab', { url, activate });
  },

  /** Navigates an existing native tab to a new URL. */
  navigateTab: async (tabId: number, url: string): Promise<void> => {
    await invoke('navigate_native_tab', { tabId, url });
  },

  /** Performs an anti-tearing Z-order swap, raising target tab to Z-top and sleeping the old tab. */
  switchTab: async (tabId: number): Promise<void> => {
    await invoke('switch_native_tab', { tabId });
  },

  /** Closes a native tab, destroys its native OS view, and activates adjacent tab. */
  closeTab: async (tabId: number): Promise<void> => {
    await invoke('close_native_tab', { tabId });
  },

  /** Returns all active tab metadata from the Rust TabManager. */
  getTabs: async (): Promise<TabInfo[]> => {
    return await invoke<TabInfo[]>('get_tabs');
  },

  /** Returns the currently active tab ID. */
  getActiveTabId: async (): Promise<number | null> => {
    return await invoke<number | null>('get_active_tab_id');
  },

  /** Updates global modal mode in Rust's AtomicU8 (0=Normal, 1=Insert, etc.). */
  setMode: async (mode: number): Promise<number> => {
    return await invoke<number>('set_mode', { mode });
  },

  /** Gets current global modal mode from Rust's AtomicU8. */
  getMode: async (): Promise<number> => {
    return await invoke<number>('get_mode');
  },

  /** Toggles audio mute/unmute on the target tab (CefAudioHandler). */
  toggleAudio: async (tabId: number): Promise<boolean> => {
    return await invoke<boolean>('toggle_audio', { tabId });
  },

  /** Resizes viewport bounds across all native views on window resize. */
  updateBounds: async (x: number, y: number, width: number, height: number): Promise<void> => {
    await invoke('update_viewport_bounds', { x, y, width, height });
  },

  // ---------------- Lifecycle Event Listeners ----------------

  /** Fired when page <title> updates, URL commits, or <link rel="icon"> favicon is discovered. */
  onMetadataChanged: async (callback: (event: TabMetaEvent) => void): Promise<UnlistenFn> => {
    return await listen<TabMetaEvent>('tab_metadata_changed', (e) => callback(e.payload));
  },

  /** Fired when loading starts/finishes or progress increments (0.0 to 1.0). */
  onLoadingChanged: async (callback: (event: TabLoadingEvent) => void): Promise<UnlistenFn> => {
    return await listen<TabLoadingEvent>('tab_loading', (e) => callback(e.payload));
  },

  /** Fired on network failures, DNS lookup errors, or page crash. */
  onError: async (callback: (event: TabErrorEvent) => void): Promise<UnlistenFn> => {
    return await listen<TabErrorEvent>('tab_error', (e) => callback(e.payload));
  },

  /** Fired when the full active tab list updates. */
  onTabsUpdated: async (callback: (tabs: TabInfo[]) => void): Promise<UnlistenFn> => {
    return await listen<TabInfo[]>('tabs_updated', (e) => callback(e.payload));
  },

  /** Fired when an active tab has completed its Z-Order promotion. */
  onTabActivated: async (callback: (tabId: number) => void): Promise<UnlistenFn> => {
    return await listen<number>('tab_activated', (e) => callback(e.payload));
  },

  /** Fired when a tab has been closed and destroyed. */
  onTabClosed: async (callback: (tabId: number) => void): Promise<UnlistenFn> => {
    return await listen<number>('tab_closed', (e) => callback(e.payload));
  },

  /** Fired when background or foreground tab audio status changes (CefAudioHandler). */
  onAudioChanged: async (callback: (event: { id: number; is_audible: boolean }) => void): Promise<UnlistenFn> => {
    return await listen<{ id: number; is_audible: boolean }>('audio_changed', (e) => callback(e.payload));
  },
};
