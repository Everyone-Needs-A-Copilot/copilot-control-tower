# UI/UX design of record

> **Status line — rebuilt from evidence, 2026-08-02.** Describes Copilot Control Tower v0.4.0. The prior version of this file directed Product Creation Copilot to design an MDM-profile generator and to output a Figma file plus a Storybook component library; neither happened. MDM is dropped completely as a mechanism for this product (CSE decision D4), and the app was hand-built in native Swift on a separate design track, not delivered as Figma/Storybook artifacts.

## The design of record

The native app's actual UI/UX design lives in three documents, in this order:

1. [`../control-tower-native-experience-architecture.md`](../control-tower-native-experience-architecture.md) — the native macOS experience architecture (Stage 1 of 3). States plainly that the Tauri-web UI was rejected and the target is a true native macOS SwiftUI/AppKit app.
2. [`../control-tower-interaction-spec.md`](../control-tower-interaction-spec.md) — the interaction spec (Stage 2 of 3). Documents the tray states, wizard flow, and Settings surface as they actually render, and explicitly records that MDM/managed-fleet framing was deleted from the design.
3. [`../control-tower-visual-system.md`](../control-tower-visual-system.md) — the visual system (Stage 3 of 3). The monochrome, template-icon-friendly, "no MDM and no fleet-as-center" visual language actually implemented.

A fourth document, [`../control-tower-copy-deck.md`](../control-tower-copy-deck.md), is the canonical copy source, organized for direct use in `native/*.swift`.

These four documents describe what was actually built. Read them, not the historical brief below, before proposing a visual or interaction change.

## Historical brief (superseded, kept for lineage only)

The original brief in this file directed Product Creation Copilot to design four surfaces — the menu-bar dropdown, the first-run wizard (including a "silent managed path" gated on an MDM-pushed `DisableWizard=true`), an Admin-mode UI including "the MDM-profile generator," and notifications — and to deliver the result as a Figma file plus a Storybook component library, landing back in this repo. None of that happened as specified: there is no MDM-profile generator (MDM is dropped, not built), there is no silent managed path gated on a device-management push (self-install is the only path, per CSE decision D4), and no Figma or Storybook artifact was ever the delivery mechanism. The app was hand-authored in native Swift against the three-document design of record above.

If Product Creation Copilot or a similar design process is invoked again for this product, point it at the design of record above, not at this historical brief, and do not re-derive the MDM/Figma/Storybook framing — it was explicitly rejected.

## Brand

The mark is the aviator-sunglasses silhouette, deliberately template-icon friendly (renders correctly as a monochrome macOS menu-bar template image across light/dark and every badge state). See [`../brand-assets.md`](../brand-assets.md) for the source assets and rasterization approach.
