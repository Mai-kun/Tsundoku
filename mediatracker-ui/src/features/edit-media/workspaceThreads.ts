/**
 * The living threads of the spatial workspace. Anchors pick the nearest card face automatically,
 * and a critically-damped-ish spring follows the targets so cables lag, bow and stretch while a
 * window is being dragged — all with plain numbers stepping in one rAF loop, no SVG filters.
 */

export interface Rect {
  x: number;
  y: number;
  w: number;
  h: number;
}

export interface AnchorPair {
  sx: number;
  sy: number;
  ex: number;
  ey: number;
}

/** Face of a rect the thread leaves from; 0 = left, 1 = top, 2 = right, 3 = bottom. */
export type Face = 0 | 1 | 2 | 3;

function centerOf(rect: Rect): { x: number; y: number } {
  return { x: rect.x + rect.w / 2, y: rect.y + rect.h / 2 };
}

function facePoint(rect: Rect, face: Face): { x: number; y: number } {
  switch (face) {
    case 0:
      return { x: rect.x, y: rect.y + rect.h / 2 };
    case 1:
      return { x: rect.x + rect.w / 2, y: rect.y };
    case 2:
      return { x: rect.x + rect.w, y: rect.y + rect.h / 2 };
    case 3:
      return { x: rect.x + rect.w / 2, y: rect.y + rect.h };
  }
}

/**
 * Picks the exit face on `from` and the entry face on `to` from the vector between the two
 * centers: the dominant axis wins, so the cable always leaves through a card edge instead of
 * poking out of a corner.
 */
export function nearestFaceAnchors(from: Rect, to: Rect): AnchorPair {
  const a = centerOf(from);
  const b = centerOf(to);
  const dx = b.x - a.x;
  const dy = b.y - a.y;
  let fromFace: Face;
  let toFace: Face;
  if (Math.abs(dx) >= Math.abs(dy)) {
    fromFace = dx >= 0 ? 2 : 0;
    toFace = dx >= 0 ? 0 : 2;
  } else {
    fromFace = dy >= 0 ? 3 : 1;
    toFace = dy >= 0 ? 1 : 3;
  }
  const start = facePoint(from, fromFace);
  const end = facePoint(to, toFace);
  return { sx: start.x, sy: start.y, ex: end.x, ey: end.y };
}

/** Animated cable: endpoints and the previous midpoint spring toward their targets. */
export class ThreadSpring {
  ax: number;
  ay: number;
  bx: number;
  by: number;
  pmx: number;
  pmy: number;

  constructor(target: AnchorPair) {
    this.ax = target.sx;
    this.ay = target.sy;
    this.bx = target.ex;
    this.by = target.ey;
    this.pmx = (target.sx + target.ex) / 2;
    this.pmy = (target.sy + target.ey) / 2;
  }

  /**
   * Springs the endpoints toward the fresh anchor pair and derives the bezier control points from
   * the damped midpoint lag — that lag is what makes the cable visibly bend while dragging.
   */
  step(target: AnchorPair, k: number): { d: string; settled: boolean } {
    this.ax += (target.sx - this.ax) * k;
    this.ay += (target.sy - this.ay) * k;
    this.bx += (target.ex - this.bx) * k;
    this.by += (target.ey - this.by) * k;

    const mx = (this.ax + this.bx) / 2;
    const my = (this.ay + this.by) / 2;
    // Midpoint lag, damped: the previous mid trails the current one and pulls the curve sideways.
    const wobX = (this.pmx - mx) * 0.55;
    const wobY = (this.pmy - my) * 0.55;
    this.pmx = mx;
    this.pmy = my;

    const c1x = this.ax + (mx - this.ax) * 0.5 + wobX;
    const c1y = this.ay + (my - this.ay) * 0.5 + wobY;
    const c2x = this.bx - (mx - this.bx) * 0.5 + wobX;
    const c2y = this.by - (my - this.by) * 0.5 + wobY;

    const settled =
      Math.abs(target.sx - this.ax) < 0.1 &&
      Math.abs(target.sy - this.ay) < 0.1 &&
      Math.abs(target.ex - this.bx) < 0.1 &&
      Math.abs(target.ey - this.by) < 0.1 &&
      Math.abs(wobX) < 0.1 &&
      Math.abs(wobY) < 0.1;

    const d = `M ${this.ax.toFixed(1)} ${this.ay.toFixed(1)} C ${c1x.toFixed(1)} ${c1y.toFixed(1)}, ${c2x.toFixed(1)} ${c2y.toFixed(1)}, ${this.bx.toFixed(1)} ${this.by.toFixed(1)}`;
    return { d, settled };
  }
}
