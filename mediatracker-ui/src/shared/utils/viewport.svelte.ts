// Single reactive source of truth for the window width. HomeView derives the
// compact section limit from it (columns x full rows), so a live resize keeps
// the grid columns and the limit button in lockstep without duplicated
// listeners in every view.
let width = $state(typeof window === "undefined" ? 1280 : window.innerWidth);

if (typeof window !== "undefined") {
  window.addEventListener("resize", () => (width = window.innerWidth));
}

export function windowWidth(): number {
  return width;
}
