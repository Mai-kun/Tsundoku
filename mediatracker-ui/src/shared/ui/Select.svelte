<script lang="ts" generics="T">
  import { Check, ChevronDown } from "$shared/ui/Icons";
  import PopoverMenu from "./PopoverMenu.svelte";

  interface Props<T> {
    id: string;
    options: { value: T; label: string }[];
    value: T;
    onChange: (value: T) => void;
    placeholder?: string;
    disabled?: boolean;
    /** aria-label for the trigger button; defaults to the selected label. */
    label?: string;
    /** Extra classes for the trigger button (width, height, typography). */
    class?: string;
    matchTriggerWidth?: boolean;
  }

  let {
    id,
    options,
    value,
    onChange,
    placeholder = "",
    disabled = false,
    label,
    class: className = "h-10 w-full text-sm",
    matchTriggerWidth = true,
  }: Props<T> = $props();

  const selectedLabel = $derived(
    options.find((option) => option.value === value)?.label ?? placeholder,
  );

  function handleSelect(next: T) {
    onChange(next);
    // PopoverMenu keeps click-opened menus open (multi-choice footers rely on
    // that); a single-value select closes right after picking.
    document.getElementById(`popover-${id}`)?.hidePopover();
  }
</script>

<PopoverMenu
  {id}
  {options}
  selected={value}
  onSelect={handleSelect}
  label={label ?? selectedLabel}
  placement="bottom-start"
  {matchTriggerWidth}
>
  {#snippet trigger({ popoverTargetId, anchorName, isOpen })}
    <button
      type="button"
      {id}
      popovertarget={popoverTargetId}
      popovertargetaction="toggle"
      style={isOpen ? `anchor-name: ${anchorName}` : undefined}
      {disabled}
      aria-haspopup="listbox"
      aria-label={label ?? selectedLabel}
      class="text-ink flex cursor-pointer items-center justify-between gap-2 rounded-lg border border-white/10 bg-[#1c202b] px-3 transition outline-none hover:border-white/20 focus:border-indigo-500/60 disabled:cursor-not-allowed disabled:opacity-50 {className}"
    >
      <span class="truncate">{selectedLabel}</span>
      <ChevronDown size={14} class="text-muted shrink-0" aria-hidden="true" />
    </button>
  {/snippet}
</PopoverMenu>
