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
  }

  close() {
    this.target?.onClose?.();
    this.target = null;
  }
}

export const dropPromptState = new DropReasonState();
