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
      $inspect.trace(label);
      return fn();
    });
  } else {
    $effect(() => {
      return fn();
    });
  }
}
