/**
 * The living threads of the spatial workspace. Anchors pick the nearest card face automatically
 * and expose the face normal, so control points leave the card along its tangent. Every control
 * point is a spring that lags behind its target — with a gentle organic sine wave layered on top,
 * the cables breathe, sag and bend like flexible strands. Plain numbers in one rAF loop; no SVG
 * filters anywhere.
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
  /** Outward normal of the start face (unit vector along the exit tangent). */
  snx: number;
  sny: number;
  ex: number;
  ey: number;
  /** Outward normal of the end face (entry tangent). */
  enx: number;
  eny: number;
}

/** Face of a rect the thread leaves from; 0 = left, 1 = top, 2 = right, 3 = bottom. */
export type Face = 0 | 1 | 2 | 3;

const FACE_NORMALS: Record<Face, { x: number; y: number }> = {
  0: { x: -1, y: 0 },
  1: { x: 0, y: -1 },
  2: { x: 1, y: 0 },
  3: { x: 0, y: 1 },
};

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
 * poking out of a corner. Face normals ride along for the tangent-based control points.
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
  const sn = FACE_NORMALS[fromFace];
  const en = FACE_NORMALS[toFace];
  return { sx: start.x, sy: start.y, snx: sn.x, sny: sn.y, ex: end.x, ey: end.y, enx: en.x, eny: en.y };
}

/**
 * Animated cable. Endpoints and both control points are springs toward their targets; control
 * targets leave the face along its tangent, carry a soft sag and breathe with a per-thread sine
 * wave, so resting cables keep a gentle organic curve instead of hanging like dead sticks.
 */
export class ThreadSpring {
  private ax: number;
  private ay: number;
  private bx: number;
  private by: number;
  private c1x: number;
  private c1y: number;
  private c2x: number;
  private c2y: number;

  constructor(target: AnchorPair, private readonly wavePhase: number) {
    this.ax = target.sx;
    this.ay = target.sy;
    this.bx = target.ex;
    this.by = target.ey;
    const c = this.controlTargets(target, 0);
    this.c1x = c.c1x;
    this.c1y = c.c1y;
    this.c2x = c.c2x;
    this.c2y = c.c2y;
  }

  /**
   * Tangent-driven control targets: protrude along the face normal, add a light downward sag and
   * a delicate sine breathing term (phase shifts per thread so cables never sway in sync).
   */
  private controlTargets(t: AnchorPair, timeMs: number) {
    const dist = Math.hypot(t.ex - t.sx, t.ey - t.sy);
    const protrusion = Math.min(Math.max(dist * 0.32, 28), 110);
    const sag = Math.min(dist * 0.08, 26);
    const sway = Math.sin(timeMs * 0.0018 + this.wavePhase) * 8;
    const sway2 = Math.sin(timeMs * 0.0018 + this.wavePhase + 1.7) * 8;
    return {
      c1x: t.sx + t.snx * (protrusion + sway),
      c1y: t.sy + t.sny * (protrusion + sway) + sag,
      c2x: t.ex + t.enx * (protrusion - sway2),
      c2y: t.ey + t.eny * (protrusion - sway2) + sag,
    };
  }

  /**
   * Springs endpoints and control points toward their fresh targets and returns the cubic bezier
   * path (there are never any straight segments — every link is a `C` curve).
   */
  step(target: AnchorPair, timeMs: number, k: number): { d: string } {
    this.ax += (target.sx - this.ax) * k;
    this.ay += (target.sy - this.ay) * k;
    this.bx += (target.ex - this.bx) * k;
    this.by += (target.ey - this.by) * k;

    const c = this.controlTargets(target, timeMs);
    this.c1x += (c.c1x - this.c1x) * k;
    this.c1y += (c.c1y - this.c1y) * k;
    this.c2x += (c.c2x - this.c2x) * k;
    this.c2y += (c.c2y - this.c2y) * k;

    const d = `M ${this.ax.toFixed(1)} ${this.ay.toFixed(1)} C ${this.c1x.toFixed(1)} ${this.c1y.toFixed(1)}, ${this.c2x.toFixed(1)} ${this.c2y.toFixed(1)}, ${this.bx.toFixed(1)} ${this.by.toFixed(1)}`;
    return { d };
  }
}
