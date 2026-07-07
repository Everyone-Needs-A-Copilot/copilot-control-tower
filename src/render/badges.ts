/**
 * Badge SHAPES (wrench/key/clock/triangle/dot/ring/bang/spinner/hollow/…),
 * never colour-only — see docs/product-design/04-experience-design/60-ui-design.md
 * § Design Tokens → Status semantics / § Component Patterns → 1. The
 * Status-Glyph Family.
 *
 * Shape is the PRIMARY encoder: every mark here must disambiguate its state
 * with colour fully stripped (grayscale-legible, a11y §1 hard rule). Colour
 * (via the `--badge-*` CSS custom properties, set per `data-badge` in
 * popover.css) is a secondary, purely decorative layer on top.
 *
 * This module draws marks only — it never chooses which state applies
 * (that's the DTO's `badge_state` field, already decided upstream).
 */
import type { BadgeState } from "../types";

const SVG_NS = "http://www.w3.org/2000/svg";

function svg(paths: (svgEl: SVGSVGElement) => void): SVGSVGElement {
  const el = document.createElementNS(SVG_NS, "svg") as SVGSVGElement;
  el.setAttribute("viewBox", "0 0 16 16");
  el.setAttribute("width", "12");
  el.setAttribute("height", "12");
  el.setAttribute("aria-hidden", "true");
  el.setAttribute("focusable", "false");
  paths(el);
  return el;
}

function path(el: SVGSVGElement, d: string, opts: { fill?: string; stroke?: string; width?: string } = {}): void {
  const p = document.createElementNS(SVG_NS, "path");
  p.setAttribute("d", d);
  p.setAttribute("fill", opts.fill ?? "none");
  if (opts.stroke) {
    p.setAttribute("stroke", opts.stroke);
    p.setAttribute("stroke-width", opts.width ?? "1.4");
    p.setAttribute("stroke-linecap", "round");
    p.setAttribute("stroke-linejoin", "round");
  }
  el.appendChild(p);
}

function circle(el: SVGSVGElement, cx: number, cy: number, r: number, opts: { fill?: string; stroke?: string } = {}): void {
  const c = document.createElementNS(SVG_NS, "circle");
  c.setAttribute("cx", String(cx));
  c.setAttribute("cy", String(cy));
  c.setAttribute("r", String(r));
  c.setAttribute("fill", opts.fill ?? "currentColor");
  if (opts.stroke) {
    c.setAttribute("stroke", opts.stroke);
    c.setAttribute("stroke-width", "1.4");
    c.setAttribute("fill", "none");
  }
  el.appendChild(c);
}

/** Builds the shape for one badge state. Shape geometry only — colour comes from CSS. */
function drawShape(state: BadgeState): SVGSVGElement {
  switch (state) {
    case "pass":
      // Solid dot — the ONLY green mark in the product, and only ever a dot, never the tray glyph.
      return svg((el) => circle(el, 8, 8, 3.5));
    case "wrench":
      return svg((el) =>
        path(
          el,
          "M11.5 2.5a3 3 0 0 1-3.7 3.9L4 10.2a1.6 1.6 0 1 0 2.3 2.3l3.8-3.8a3 3 0 0 1 3.9-3.7l-2 2-1.4-1.4z",
          { stroke: "currentColor", width: "1.2" },
        ),
      );
    case "key":
      return svg((el) => {
        circle(el, 5, 6, 2.6, { stroke: "currentColor" });
        path(el, "M7 8l6 6M11 12l1.5-1.5M12.5 13.5L14 12", { stroke: "currentColor" });
      });
    case "triangle":
      return svg((el) => {
        path(el, "M8 2.5l6.2 11H1.8z", { stroke: "currentColor", width: "1.3" });
        path(el, "M8 6.5v3.2", { stroke: "currentColor", width: "1.3" });
        circle(el, 8, 11.8, 0.7);
      });
    case "clock":
      return svg((el) => {
        circle(el, 8, 8, 5.5, { stroke: "currentColor" });
        path(el, "M8 4.7v3.6l2.6 1.6", { stroke: "currentColor" });
      });
    case "cloud-slash":
      return svg((el) => {
        path(
          el,
          "M4.5 11h6a2.5 2.5 0 0 0 .4-4.96A3.5 3.5 0 0 0 4.2 7.1 2.5 2.5 0 0 0 4.5 11z",
          { stroke: "currentColor", width: "1.2" },
        );
        path(el, "M2.5 2.5l11 11", { stroke: "currentColor", width: "1.3" });
      });
    case "ring":
      return svg((el) => {
        circle(el, 8, 8, 5, { stroke: "currentColor" });
        path(el, "M8 3a5 5 0 0 1 4.5 2.8", { stroke: "currentColor", width: "1.6" });
      });
    case "update":
      // Info dot — visually distinct position/size from `pass` via CSS (outline ring), shape stays a dot.
      return svg((el) => circle(el, 8, 8, 3));
    case "bang":
      return svg((el) => {
        path(el, "M8 2.5v6.4", { stroke: "currentColor", width: "1.8" });
        circle(el, 8, 12.3, 0.9);
      });
    case "spinner":
      return svg((el) => {
        circle(el, 8, 8, 5, { stroke: "currentColor" });
        path(el, "M13 8a5 5 0 0 0-5-5", { stroke: "currentColor", width: "1.8" });
      });
    case "hollow":
      return svg((el) => circle(el, 8, 8, 5, { stroke: "currentColor" }));
    case "none":
    default:
      return svg(() => {
        /* deliberately empty — no data for this bucket, no mark drawn */
      });
  }
}

/** Human-readable name of the shape itself (never a colour word) — used as a fallback text carrier. */
export const BADGE_SHAPE_NAME: Record<BadgeState, string> = {
  pass: "solid dot",
  wrench: "wrench",
  key: "key",
  triangle: "triangle",
  clock: "clock",
  "cloud-slash": "cloud with a slash",
  ring: "ring",
  update: "dot",
  bang: "exclamation mark",
  spinner: "spinner",
  hollow: "hollow outline",
  none: "no badge",
};

/**
 * Renders a badge as a `<span>` wrapping the shape SVG. `data-badge` drives the
 * colour (CSS, secondary encoder only); the shape itself is colour-independent.
 * The caller is responsible for the accessible name (the row's own label
 * already states the fact in words — the badge is decorative, `aria-hidden`).
 */
export function renderBadge(state: BadgeState, opts: { animate?: boolean } = {}): HTMLSpanElement {
  const wrap = document.createElement("span");
  wrap.className = "badge";
  wrap.dataset.badge = state;
  if (opts.animate && (state === "ring" || state === "spinner")) {
    wrap.classList.add("badge-motion");
  }
  if (opts.animate && state === "hollow") {
    wrap.classList.add("badge-pulse");
  }
  wrap.appendChild(drawShape(state));
  return wrap;
}
