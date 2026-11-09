import { describe, it, expect, vi, beforeEach } from 'vitest';

// Mock Tauri Core and Event APIs before importing tabManager
const mockInvoke = vi.fn();
const mockListen = vi.fn().mockResolvedValue(() => {});

vi.mock('@tauri-apps/api/core', () => ({
  invoke: (...args: unknown[]) => mockInvoke(...args),
}));

vi.mock('@tauri-apps/api/event', () => ({
  listen: (...args: unknown[]) => mockListen(...args),
}));

import { tabManager } from './tab-manager';

describe('tabManager TypeScript SDK Unit Tests', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('Tab Mutation Commands', () => {
    it('createTab dispatches create_native_tab with default activate=true', async () => {
      mockInvoke.mockResolvedValueOnce(1);
      const tabId = await tabManager.createTab('https://groww.in');

      expect(mockInvoke).toHaveBeenCalledWith('create_native_tab', {
        url: 'https://groww.in',
        activate: true,
      });
      expect(tabId).toBe(1);
    });

    it('createTab respects activate=false when backgrounding', async () => {
      mockInvoke.mockResolvedValueOnce(2);
      const tabId = await tabManager.createTab('https://news.ycombinator.com', false);

      expect(mockInvoke).toHaveBeenCalledWith('create_native_tab', {
        url: 'https://news.ycombinator.com',
        activate: false,
      });
      expect(tabId).toBe(2);
    });

    it('navigateTab calls navigate_native_tab with tabId and url', async () => {
      mockInvoke.mockResolvedValueOnce(undefined);
      await tabManager.navigateTab(1, 'https://github.com');

      expect(mockInvoke).toHaveBeenCalledWith('navigate_native_tab', {
        tabId: 1,
        url: 'https://github.com',
      });
    });

    it('switchTab calls switch_native_tab to trigger Z-order swap', async () => {
      mockInvoke.mockResolvedValueOnce(undefined);
      await tabManager.switchTab(3);

      expect(mockInvoke).toHaveBeenCalledWith('switch_native_tab', {
        tabId: 3,
      });
    });

    it('closeTab calls close_native_tab', async () => {
      mockInvoke.mockResolvedValueOnce(undefined);
      await tabManager.closeTab(2);

      expect(mockInvoke).toHaveBeenCalledWith('close_native_tab', {
        tabId: 2,
      });
    });
  });

  describe('Engine Mode Transitions', () => {
    it('setMode updates modal state in Rust', async () => {
      mockInvoke.mockResolvedValueOnce(1); // INSERT
      const res = await tabManager.setMode(1);

      expect(mockInvoke).toHaveBeenCalledWith('set_mode', { mode: 1 });
      expect(res).toBe(1);
    });

    it('getMode retrieves current modal state', async () => {
      mockInvoke.mockResolvedValueOnce(0); // NORMAL
      const mode = await tabManager.getMode();

      expect(mockInvoke).toHaveBeenCalledWith('get_mode');
      expect(mode).toBe(0);
    });
  });

  describe('Lifecycle Event Listeners', () => {
    it('onMetadataChanged registers listener for tab_metadata_changed', async () => {
      const cb = vi.fn();
      await tabManager.onMetadataChanged(cb);

      expect(mockListen).toHaveBeenCalledWith('tab_metadata_changed', expect.any(Function));
    });

    it('onLoadingChanged registers listener for tab_loading', async () => {
      const cb = vi.fn();
      await tabManager.onLoadingChanged(cb);

      expect(mockListen).toHaveBeenCalledWith('tab_loading', expect.any(Function));
    });

    it('onError registers listener for tab_error', async () => {
      const cb = vi.fn();
      await tabManager.onError(cb);

      expect(mockListen).toHaveBeenCalledWith('tab_error', expect.any(Function));
    });

    it('onTabsUpdated registers listener for tabs_updated', async () => {
      const cb = vi.fn();
      await tabManager.onTabsUpdated(cb);

      expect(mockListen).toHaveBeenCalledWith('tabs_updated', expect.any(Function));
    });
  });
});
