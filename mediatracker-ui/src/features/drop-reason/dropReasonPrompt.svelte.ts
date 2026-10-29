export interface DropPromptTarget {
  id: string;
  title: string;
  type?: string;
  isAnime?: boolean;
  dropReason?: string | null;
  dropNotes?: string | null;
  onSaved?: (dropReason: string | null, dropNotes: string | null) => void;
  onClose?: () => void;
}

class DropReasonState {
  target = $state<DropPromptTarget | null>(null);

  open(target: DropPromptTarget) {
    this.target = target;
    // Push a modal entry so the browser Back button closes this prompt instead of navigating the
    // view beneath it.
    window.history.pushState({ modalOpen: true }, "");
  }

  close() {
    this.target?.onClose?.();
    this.target = null;
    if (window.history.state?.modalOpen) {
      window.history.back();
    }
  }
}

export const dropPromptState = new DropReasonState();
