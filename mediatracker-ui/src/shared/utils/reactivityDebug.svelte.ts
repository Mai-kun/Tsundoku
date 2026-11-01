export function traceEffect(label: string, fn: () => void | (() => void)): void {
  const enabled =
    import.meta.env.DEV &&
    typeof localStorage !== "undefined" &&
    (() => {
      try {
        return localStorage.getItem("tsundoku_trace_effects") === "1";
      } catch {
        return false;
      }
    })();

  if (enabled) {
    $effect(() => {
      // Dev-only effect tracing behind the tsundoku_trace_effects flag — the
      // production branch below never reaches this $inspect.
      // eslint-disable-next-line svelte/no-inspect
      $inspect.trace(label);
      return fn();
    });
  } else {
    $effect(() => {
      return fn();
    });
  }
}
