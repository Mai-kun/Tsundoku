<script lang="ts">
  import { i18n } from "$shared/i18n/index.svelte";
  import Modal from "$shared/ui/Modal.svelte";
  import { getStorageSettings, saveStorageSettings } from "$shared/api/api";
  import { onMount } from "svelte";

  let loading = $state(true);
  let mode = $state("default");
  let customPath = $state("");
  let settings = $state<any>(null);
  let isOpen = $state(false);

  onMount(async () => {
    try {
      settings = await getStorageSettings();
      isOpen = Boolean(settings?.isFirstRunSetupRequired);
    } catch (e) {
      console.error("Failed to load storage settings:", e);
      isOpen = false;
    } finally {
      loading = false;
    }
  });

  async function handleSave() {
    await saveStorageSettings({
      mode: mode as "default" | "portable" | "custom",
      customPath,
      migrateExistingData: true,
    });
    window.location.reload();
  }
</script>

{#if isOpen}
  <Modal {isOpen} onClose={() => (isOpen = false)}>
    <h2 class="text-white">{i18n.t.settings.storageSetupRequired}</h2>
    {#if loading}
      <p class="text-white">{i18n.t.common.loading}</p>
    {:else}
      <div class="options">
        <label class="text-white">
          <input type="radio" bind:group={mode} value="default" />
          {i18n.t.settings.storageDefault}
        </label>
        <label class="text-white">
          <input type="radio" bind:group={mode} value="portable" />
          {i18n.t.settings.storagePortable}
        </label>
        <label class="text-white">
          <input type="radio" bind:group={mode} value="custom" />
          {i18n.t.settings.storageCustom}
        </label>
        {#if mode === "custom"}
          <input type="text" bind:value={customPath} placeholder="/path/to/data" />
        {/if}
      </div>
      <button type="button" onclick={handleSave} class="text-white"
        >{i18n.t.settings.storageConfirm}</button
      >
    {/if}
  </Modal>
{/if}

<style>
  .options {
    display: flex;
    flex-direction: column;
    gap: 10px;
    margin-bottom: 20px;
  }
</style>
