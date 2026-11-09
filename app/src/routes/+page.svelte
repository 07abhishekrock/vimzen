<script lang="ts">
  import { onMount } from "svelte";
  import { tabManager, isTauri, type TabInfo } from "$lib/tab-manager";

  let tabs = $state<TabInfo[]>([]);
  let activeTabId = $state<number | null>(null);

  onMount(async () => {
    if (isTauri) {
      tabs = await tabManager.getTabs();
      activeTabId = await tabManager.getActiveTabId();

      await tabManager.onTabsUpdated((updated) => {
        tabs = updated;
      });
      await tabManager.onTabActivated((id) => {
        activeTabId = id;
      });
    }
  });
</script>

<div class="shell">
  <!-- Minimal headless mount for Svelte client; all tabs are native OS child views driven via $lib/tab-manager -->
  <main class="viewport">
    {#if tabs.length === 0}
      <div class="empty-state">
        <p>No active native tabs. Create one via <code>tabManager.createTab(url)</code>.</p>
      </div>
    {/if}
  </main>
</div>

<style>
  :global(body) {
    margin: 0;
    padding: 0;
    background: #0d1117;
    color: #c9d1d9;
    font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace;
    font-size: 12px;
  }
  .shell {
    height: 100vh;
    display: flex;
    flex-direction: column;
  }
  .viewport {
    flex: 1;
    position: relative;
  }
  .empty-state {
    display: flex;
    align-items: center;
    justify-content: center;
    height: 100%;
    color: #8b949e;
  }
</style>
