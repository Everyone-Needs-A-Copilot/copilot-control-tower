# UI Design

> **Provenance.** Grounded visual translation, not fresh invention. Every token and pattern below gives
> visual form to something already decided upstream: the status-icon **STATE MATRIX** and the
> **accessibility bar** (`50-ux-design.md`), the state coverage in `03-requirements/10-user-stories.md`,
> the **restraint / honesty** mandate of `SOUL.md` (§2 air-traffic-controller, §6 quality bar, §7
> voice), the essence of trust-by-subtraction (`00-overview/00-vision.md`), and the ratified **mark**
> in `docs/03-design/ui-ux/README.md`. Genuine unknowns are marked `<!-- TODO -->`.
>
> **This is macOS-native menu-bar software.** The visual language is bound by three hard constraints,
> not stylistic preference: (1) the status glyph ships as a macOS **template image** — a monochrome mask
> the system tints for the light/dark menu bar, so *shape must carry state before colour does*; (2)
> **light + dark** appearance are both first-class, not a theme toggle; (3) the a11y bar from the UX doc
> is non-negotiable — no status by colour alone, ≥3:1 glyph/badge contrast in *both* appearances, ≥4.5:1
> body text. Where the generic "design system" reflex (44px touch targets, heavy elevation, decorative
> motion) collides with native macOS convention, native convention and the Soul win — and the collision
> is called out inline.

---

## Visual Direction

### Named direction: **Air-Traffic Instrument** — calm native utility, colour as a scalpel

The product *is* an air-traffic controller (`SOUL.md` §2). The visual language is the instrument panel
in that tower: **monochrome by default, legible under a half-second glance, colour used only where it
carries a fact.** The whole aesthetic is *silence you can trust* — when everything is fine, the panel is
a plain solid mark and nothing draws the eye. The interface earns trust the way the product does:
by **subtraction**.

Five commitments define it:

| Commitment | Concrete visual move | Why (traces to) |
|---|---|---|
| **Monochrome-first, colour is a scalpel** | The menu-bar glyph is a single-colour template mask; colour appears only inside the popover/dashboard, and only ever *paired* with a shape and a sentence. There is no colour that means "generally good vibes." | P4 no-colour-only; a11y §1; `SOUL.md` §2 "says exactly what is true and no more" |
| **Native, not branded-native** | SF Pro type, macOS system materials (vibrancy popover), system corner radii, system focus rings. It looks like it *shipped with macOS*, not like a web app wearing a Mac costume. | `CLAUDE.md` Tech "keep the UI tiny — no heavy framework"; Windows = mechanical re-skin |
| **Silence is the success state, visually** | Healthy = the plain solid mark, **no green, no checkmark, no toast**. The brightest/most-saturated pixel on screen is *never* the Healthy state. | P1 (silence = success); `SOUL.md` §6 taste test; anti-pattern *The Alert Machine* |
| **Honest holding states are designed first** | The wrench / clock / cloud-slash / key badges get more design attention than Healthy. Each is a distinct, calm, named mark — never a blended "attention" blob. | P6 (design holding states first); US-B03/B04/B08/B09 |
| **Motion is confirmation, never attention-grabbing** | State changes cross-fade calmly (~180 ms); the only continuous motion is the Syncing ring, and it *reassures*, it doesn't alarm. No bounce, no flash, no pulse-to-notice (except one gentle Setup-needed invitation). | UX microinteractions; anti-pattern *The Alert Machine*; reduce-motion honoured |

### The mark

The glyph is the **aviator-sunglasses silhouette**, brand colour `#2D294E`, ratified in
`docs/03-design/ui-ux/README.md` as deliberately **template-friendly**: it renders correctly as a
monochrome menu-bar template image across light/dark and all status overlays. `#2D294E` is a deep
desaturated indigo — it reads as *instrument*, not *consumer* (it is neither a trust-blue cliché nor a
purple-gradient AI cliché), and as a template mask it is tinted by the system anyway, so the brand
colour survives only in full-colour surfaces (wizard header, dashboard chrome, primary action).

> **Naming — SETTLED.** The product **name** is **"Copilot Control Tower"** (short **"Control Tower"**),
> per `00-overview/00-vision.md`, and it **is shown to the end user** — in the setup-wizard header, the
> dropdown/popover header, and About. The **mark** (aviator-sunglasses silhouette, `#2D294E`) is the
> **menu-bar tray glyph** Bob sees, ratified by the design-track README and **decoupled** from the dead
> codename: the *mark* survives the codename's retirement. The stale **"Aviator" engineering codename**
> is retired and **must never appear as a product name on any user surface** (`70-copy-voice.md` Banned
> Language). This doc adopts the aviator-sunglasses *mark* as the tray glyph and uses "Copilot Control
> Tower" / "Control Tower" as the name on every user surface.

---

## Anti-Direction

**What this must never look like — the one-liner:** *not a flashy consumer AI app, not a gamified
dashboard, not alarm-red-everywhere.* An interface that decorates, celebrates, or grabs attention is a
trust regression here, because the product's whole promise is a status you don't have to interpret and a
tool that says nothing when there's nothing to say.

| Anti-pattern to reject on sight | Why it betrays this product |
|---|---|
| **Purple/indigo→pink gradient, glow, "AI shimmer"** | The AI-slop signature. Contradicts *parse-never-compute* aesthetically — it performs intelligence the app deliberately doesn't have. It's a tower, not the pilot (`SOUL.md` anti-pattern *The Copilot of the Copilot*). |
| **A big green Healthy state / celebratory checkmark / "All good! 🎉" toast** | Directly violates P1 (silence is success) and the taste test. Healthy is the *absence* of signal, never a reward. |
| **Alarm-red everything, badge counts to "clear," dashboards that pulse** | *The Alert Machine.* Red is reserved for one genuine error state (CLI-unreadable). A sea of red trains Bob to ignore the one alert that matters. |
| **A gamified fleet dashboard — health scores, progress rings-as-trophies, sparkline flourishes** | Implies the app *computes* a score. It renders CLI-parsed facts only; a "health score" UI is a false-Healthy waiting to happen (*The Second Pilot*). |
| **A settings-heavy, tab-rich consumer app chrome for Bob** | *As little app as possible* (P5). Bob's surface is one glyph + one flat menu. Chrome is audit burden. |
| **Generic SaaS card-grid with identical radius + drop-shadow everywhere** | Flattens hierarchy — everything the same size/weight says everything is equally important. The state matrix is *precedence-ordered*; the visuals must encode that order. |
| **Heavy custom-drawn shadows, faux-glass panels, decorative depth** | On macOS this fights the system. The popover's material and shadow are AppKit's; faking them looks *less* native, not more premium. |
| **A dark "hacker terminal" aesthetic (neon-on-black, monospace body)** | The entire point is that Bob *never sees a terminal*. Terminal aesthetics re-import the wall the product exists to remove. |

---

## Design Tokens

All values are tokens. Nothing below is a raw literal in a component; components reference these names.
Every colour is given **light + dark** because both are first-class. Contrast is stated where it is a
requirement (glyph/badge/UI ≥3:1; body text ≥4.5:1; large text ≥3:1 — a11y §6).

### Colors

**Neutrals** — the panel. Aligned to macOS system semantics so the popover reads native and inherits
vibrancy correctly.

| Token | Light | Dark | Usage |
|---|---|---|---|
| `--surface-popover` | system `.popover` material (≈`#FFFFFF` @ vibrancy) | system `.popover` material (≈`#1E1E1E`) | Popover / menu background — **use the AppKit material, don't paint a flat fill** |
| `--surface-raised` | `#F5F5F7` | `#2A2A2C` | Wizard body, dashboard cards, code-box fill |
| `--surface-sunken` | `#ECECEE` | `#161617` | Dashboard table zebra / input wells |
| `--separator` | `#E3E3E6` | `#38383A` | Hairline dividers (0.5pt) between menu rows / table rows |
| `--text-primary` | `#1D1D1F` | `#F5F5F7` | Status sentence, menu labels — ≥4.5:1 on surface |
| `--text-secondary` | `#6E6E73` | `#98989D` | Per-host detail, captions, "waiting on IT" — ≥4.5:1 |
| `--text-tertiary` | `#AEAEB2` | `#636366` | Disabled rows, timestamps — decorative only, never sole carrier of meaning |
| `--brand-indigo` | `#2D294E` | `#B4AEE8` | The mark; primary-action fill (light) / accent (dark). Dark variant lightened for ≥4.5:1 text-on-fill |

**Status semantics** — colour is the *second* encoder (shape/badge is first). Each pairs with a badge
shape and a sentence, so a monochrome or colour-blind render stays fully legible (a11y §1). **Healthy is
the only green, and green never appears on the menu-bar glyph** — it lives only as a dropdown/dashboard
status dot.

| State (precedence order) | Badge **shape** (primary encoder) | Light | Dark | Role of the colour |
|---|---|---|---|---|
| **IT-config-incomplete** | wrench | `#5B6470` slate | `#8A93A0` | Deliberately **desaturated** — "not yours, IT owns this." Calm, not alarming (P3: no Bob action). |
| **Signed-out** | key | `#3B5BDB` indigo-blue | `#8AA0FF` | Actionable-by-Bob (his own data). Distinct hue from both Healthy-green and Error-red. |
| **Needs-attention** | amber triangle | `#B7791F` amber | `#E5A83B` | The one "look at this" warm tone — warm, not red; red is reserved for hard error. |
| **Offline** | cloud-slash | `#8A9099` gray | `#98989D` | Dimmed overlay; transient, restores the prior state underneath. |
| **Waiting-for-network** | clock | `#4A6FA5` patient blue | `#7BA6DE` | Patient, cool — "I'll finish when you're back," not an error. |
| **Syncing** | animated ring | `#2D294E` brand | `#B4AEE8` | Work-in-progress; brand-tinted, reassuring, not urgent. |
| **Update-available** | dot | `#4A6FA5` info blue | `#7BA6DE` | Informational only for Bob (never approve). Low-key. |
| **Healthy** | *solid, no badge* | `#1E8E3E` green *(dot only, in popover/dashboard — never the glyph)* | `#30D158` | The **only** green. On the menu bar Healthy is the plain template mark; green shows only as the in-popover status dot. |
| **Setup-needed** | hollow outline, slow pulse | `#5B6470` slate | `#8A93A0` | Invitation, not error — the one gentle pulse in the system. |
| **CLI-unreadable / Error** | bang **(!)** | `#C5221F` red | `#FF453A` | **The only red in the product.** Reserved for genuine fail-closed error, so red always means "real problem." |
| **Updating-app** | spinner | `#8A9099` gray | `#98989D` | Neutral self-maintenance; not a status about the machine. |

> **Contrast note (verified requirement, a11y §6).** Status greens for *dots/UI components* use the
> **deeper** `#1E8E3E` in light mode (≈3.7:1 on white) rather than Apple's brighter `#34C759` (≈1.9:1,
> fails the 3:1 UI-component floor). Dark-mode variants are brightened to clear 3:1 on the dark surface.
> Amber `#B7791F` on white ≈4.0:1; error `#C5221F` on white ≈5.4:1. <!-- TODO: run the full contrast
> matrix (every status colour × both surfaces × text-vs-UI thresholds) and paste the measured ratios
> before implementation sign-off; values above are design-target, spot-checked not exhaustively. -->

### Typography

**Two families, both native.** No third family, no web font, no download.

- **SF Pro** (Text + Display optical variants) — everything human-readable. The macOS system face; it is
  what a native menu *is*. Using anything else would announce "web app."
- **SF Mono** — *only* for machine tokens a human must read/copy character-by-character: the 8-char
  device-flow code, locked SHAs, `machine_id`, config keys in the IT-config-incomplete sentence.
  Monospace here is functional (glyph disambiguation `0/O`, `1/l`), not decorative.

| Token | Family / size / weight | Line-height | Usage |
|---|---|---|---|
| `--type-wizard-title` | SF Pro **Display** Semibold **20pt** | 24pt | Wizard step title ("Setting up Claude…") |
| `--type-section` | SF Pro Text Semibold **15pt** | 20pt | Admin section headers, teach-panel headings |
| `--type-status` | SF Pro Text **Semibold 13pt** | 17pt | Dropdown **top line** — the status sentence (weight = its primacy) |
| `--type-body` | SF Pro Text Regular **13pt** | 17pt | Menu rows, dashboard cells (macOS menu standard size) |
| `--type-caption` | SF Pro Text Regular **11pt** | 14pt | Per-host secondary detail, timestamps, "waiting on IT" |
| `--type-code-lg` | SF **Mono** Medium **17pt**, tracking +2 | 22pt | The device-flow 8-char code — large, spaced, copyable |
| `--type-code-sm` | SF Mono Regular **11pt** | 14pt | SHAs, config keys, `machine_id` in Admin |

**Weight is hierarchy, not decoration.** The status sentence is the *only* Semibold in the popover body
— it is the one thing Bob must read, so it is the one thing that is heavier. Everything else (actions,
detail) is Regular. This is P4 made typographic: the sentence that names the failing product and layer outranks the
action offered.

### Spacing & Layout

**Base unit 4px.** Scale: `2 · 4 · 8 · 12 · 16 · 20 · 24`. (No 48/64/96 page-section steps — there is no
page. A tray popover that needed 96px rhythm would already be too big.)

| Token | Value | Usage |
|---|---|---|
| `--space-hair` | 2px | Badge inset, focus-ring offset |
| `--space-xs` | 4px | Icon-to-label gap in a menu row |
| `--space-sm` | 8px | Intra-row padding, dashboard cell padding |
| `--space-md` | 12px | Menu row horizontal padding; popover internal margin |
| `--space-lg` | 16px | Wizard body padding, section gaps |
| `--space-xl` | 20–24px | Wizard header/footer band; dashboard section separation |

| Layout token | Value | Rationale |
|---|---|---|
| `--popover-width` | **320pt**, fixed | Comfortable single-column; Miller's Law — ≤7 top-level rows (UX Responsive) |
| `--popover-height` | grows to content; internal scroll **only** on the Needs-attention finding list | The menu never becomes a scrolling wall; only a finding list may exceed |
| `--menu-row-height` | **28pt** | Native macOS menu density. *(See target-size note below.)* |
| `--wizard-window` | ~**520 × 420pt**, centered on the **active** display | A real window, not a popover; must not open off-screen on an external monitor |
| `--admin-window` | resizable, min **900 × 600pt** | The one dense surface — Earl is technical, density is earned (UX Admin patterns) |
| `--dashboard-row-height` | **32pt** | Slightly taller than a menu row for a scannable fleet table |

> **Target-size — deliberate, native, and AA-compliant.** The design-system default of 44px touch
> targets is a **touch** heuristic; Control Tower is a **pointer + keyboard** desktop app, and a 44px
> menu row would look broken on macOS. Rows are **28pt**, which clears WCAG **2.5.8 Target Size (Minimum,
> AA) = 24px**; the AAA 44px (2.5.5) does not apply to this device class. **Full keyboard operability and
> a visible focus ring are the real accessibility guarantee here** (a11y §4/§5), not oversized rows.

### Corner Radius

**Philosophy: match the system, commit to nothing sharper or rounder than macOS itself.** Sharp (0px,
brutalist) would feel alien in the menu bar; pill/16px+ (playful) would betray the instrument tone. The
radius should be *invisible* — the sign you got it right is that nobody notices it.

| Token | Value | Usage / character |
|---|---|---|
| `--radius-popover` | AppKit-owned (~10–12pt) | Don't redraw it — inherit the system popover shape |
| `--radius-control` | **6pt** | Buttons, the primary action, pick-list rows — native control radius |
| `--radius-card` | **8pt** | Dashboard cards, teach-panel blocks, code box |
| `--radius-badge` | **full** (circle) | Status badges sit in a circular field so the *shape* inside reads cleanly at 12–14px |

### Elevation

**The app owns almost no shadows.** The popover's elevation is AppKit's (its material + system shadow
declare "this floats above the menu bar" — don't fake it). Only the two real windows and dashboard cards
carry app-defined elevation, and only to seat content on a ground plane.

| Level | Shadow | Spatial justification |
|---|---|---|
| **0 — flat** | none | Menu rows, dashboard table rows, inline badges — they live *on* the surface, not above it |
| **1 — card** | `0 1px 3px rgba(0,0,0,0.12)` (light) / `0 1px 3px rgba(0,0,0,0.4)` (dark) | Dashboard cards, teach-panel blocks lift subtly off `--surface-raised` |
| **system — popover** | AppKit default | The popover / wizard float; owned by the OS, never re-drawn |
| **3 — modal** | AppKit sheet | The wizard-as-sheet and Admin confirmations use the system modal shadow |

There is **no Level-2 (dropdown/popover custom shadow)** because our "dropdown" *is* a system popover —
inventing one would fight the platform.

### Motion

**Restraint is the whole point.** Honesty means no decorative animation and, above all, no
attention-grabbing (anti-pattern *The Alert Machine*). State changes are *calm* — a controller doesn't
flash the panel, it just tells you the new truth.

| Token | Duration | Easing | Usage |
|---|---|---|---|
| `--motion-instant` | 0ms | — | Focus move, checkbox/radio toggle |
| `--motion-fast` | 120ms | ease-out | Hover feedback, button press |
| `--motion-calm` | **180ms** | **ease-in-out** | **The status cross-fade** — glyph shape/badge dissolves to the new state (no arrival "pop"; in-out because it's a *change*, not an entrance) — matches UX microinteraction spec |
| `--motion-slow` | 240ms | ease-out | Wizard step advance, popover-fallback open |
| `--motion-ring` | 1.2s linear, looping | linear | Syncing ring rotation — *steady and unhurried*, a reassurance not an alarm |
| `--motion-pulse` | 2s ease-in-out, looping | ease-in-out | Setup-needed hollow-outline gentle pulse — the **one** invitation-to-act motion in the product |

**Reduce-motion (honoured, a11y §7):** the Syncing ring becomes a **static** "syncing" glyph + the
"Syncing…" sentence; the Setup-needed pulse becomes a static hollow outline. No state is *ever*
distinguishable by motion alone — motion is always redundant with shape + text.

---

## Component Patterns

### ★ 1. The Status-Glyph Family — the product's visual centerpiece

*This is the one artifact the whole visual system exists to serve.* Each state is **one honest mark**,
built from three layers so colour is never alone (P4, a11y §1):

- **Base** = the aviator-sunglasses silhouette, shipped as a **macOS template image** (mask). The system
  tints it for the light/dark menu bar automatically. Healthy is *just this base*, solid.
- **Badge** = a distinct **shape** occupying a circular field at the lower-trailing corner. **The shape
  is the primary encoder** — it must disambiguate the state with colour fully stripped (grayscale, the
  a11y §1 hard rule).
- **Tint** = a *secondary* encoder only. In the menu bar the base is template-tinted by the system; the
  badge may carry its status colour as a supporting cue, but if the badge were rendered monochrome, its
  shape alone still names the state.

| State | Base treatment | Badge shape | Tint (secondary) | Reads in grayscale? |
|---|---|---|---|---|
| **Healthy** | solid silhouette | *none* | — (plain template) | ✓ (solid, unbadged = the only "clear" mark) |
| **Setup-needed** | **hollow outline**, slow pulse | none | slate | ✓ (hollow vs. solid) |
| **IT-config-incomplete** | solid, outlined | **wrench** | slate `#5B6470` | ✓ (wrench ≠ any other shape) |
| **Signed-out** | solid | **key** | indigo-blue `#3B5BDB` | ✓ |
| **Needs-attention** | solid | **triangle (⚠ form)** | amber `#B7791F` | ✓ |
| **Offline** | **dimmed** silhouette (overlay) | **cloud-slash** | gray | ✓ (dimmed base + slash) |
| **Waiting-for-network** | **dimmed** silhouette | **clock** | patient blue `#4A6FA5` | ✓ |
| **Syncing** | solid | **animated ring** (static in reduce-motion) | brand `#2D294E` | ✓ (ring around the mark) |
| **Update-available** | solid | **dot** | info blue `#4A6FA5` | ✓ (small filled dot) |
| **CLI-unreadable / Error** | solid | **bang (!)** | **red `#C5221F`** | ✓ (the only ! and the only red) |
| **Updating-app** | solid | **spinner** | gray | ✓ |

**The governing visual rule (from the UX matrix):** *the brightest, most-saturated pixel in the menu bar
is never Healthy.* Healthy is the quietest mark. A failure or holding state is what carries a badge and a
tint — so the eye is drawn **only** when there is something true to say. **Worst-wins is UNCHANGED and
nested:** the single glyph shows the worst state across **all products × all layers**; the *sentence*
names the worst **product and layer**; the **product list** carries a per-product badge (worst of that
product's four layers); expanding a product attributes down to the individual tier.

**VoiceOver (a11y §2):** the tray item's accessibility label is the **current status sentence** ("CLI
Copilot — department layer needs sign-in. Everything else is up to date."), never "app icon"; each
product row and each expanded layer also carry their own labels; each badge is described, never left as
decoration.

### 2. The Dropdown Popover — PRODUCT-FIRST

Fixed 320pt, system material, arrow anchored to the glyph. Structure top→bottom (Fitts's Law — the
primary action is the largest target, high in the body). The body is organized **by product**, not by
host — the instrument reads out one product per row, worst-wins glyph above:

```
┌─ (system popover, --radius-popover, AppKit shadow) ─────────────────┐
│  CLI Copilot — department layer needs sign-in.   ← --type-status (Semibold 13pt) │
│  Everything else is up to date.                  ← 2nd clause, --type-caption     │
│                                                                     │
│  [  Sign in…  ]                                  ← Primary action (contextual)    │
│  ─────────────────────────────────              ← --separator hairline (0.5pt)    │
│  PRODUCTS                                        ← --type-caption, --text-secondary (section label) │
│  ● Knowledge Copilot   up to date            ▸  ← green dot + text; collapsed      │
│  ● CLI Copilot         department: sign-in   ▾  ← key badge + text; EXPANDED below  │
│      ○ Foundation      up to date               ← layer rows, --type-caption, indented │
│      ○ Org             up to date                                                    │
│      ⚿ Department      needs sign-in  [Sign in…]  ← the off layer; inline layer action │
│          · Q3-campaign (project)  up to date    ← temp dept PROJECT, nested under Dept │
│      ○ Personal        up to date                                                    │
│  ◐ Claude Copilot      org: updating…        ▸  ← ring badge + text; collapsed      │
│  ● Codex Copilot       repairing personal…   ▸  ← ring badge + text; collapsed      │
│  ─────────────────────────────────                                                  │
│  What changed…                                   ← secondary rows, --type-body       │
│  Add a skill…                                                                        │
│  ─────────────────────────────────                                                  │
│  Preferences…                                                                        │
│  Quit                                                                                │
└──────────────────────────────────────────────────────────────────────────────────┘
```

- **Top line** is always present, always the status sentence, always the heaviest text — it now names
  the worst **product and layer**. When everything is Healthy it reads "Everything's in sync across all
  your copilots." — flat, no green, no icon celebrating it.
- **Product list** is a chunked section under a quiet `PRODUCTS` label. **Data-driven — one row per
  declared product, N not 4.** Each row carries: a **status dot/badge** (the same shape family as the
  glyph, worst of that product's four layers), the product **name**, a **short state phrase** (which
  layer + what), and a **disclosure chevron ▸/▾**. Row height `--menu-row-height` (28pt); layer rows are
  indented one step and use `--type-caption`.
- **Expansion is inline** (progressive disclosure, `--motion-calm` 180ms), not a submenu — the four
  tiers **foundation / org / department / personal** unfold beneath the product, each with its own badge
  + state text. **Temporary department projects** render as further-indented entries under the
  **Department** tier (marked "(project)"). Opening a second product may collapse the first, so the open
  set stays small (Miller's Law).
- **Worst-wins for the single glyph is unchanged** — only the *attribution* is now nested product→layer.
- **Primary action is contextual and singular** at the top (Healthy → "Sync now"; Signed-out →
  "Sign in…"; Needs-attention → "Repair…"; Setup-needed → "Finish setup…"), targeting the worst item.
  Filled with `--brand-indigo`; it is the one filled control. A layer that needs its own action may also
  surface a compact **inline layer action** (e.g. "Sign in…" on the Department row) — a plain, not
  filled, control so the top primary stays the single hero target.
- **No approve/unblock control ever renders for Bob** (US-B15, Soul: OUT) — a held update on any product
  layer shows the *sentence* "waiting on IT" and offers only "What changed?", never a button that acts.

#### 2a. Product row & four-layer expansion — visual spec

| Element | Treatment | Notes |
|---|---|---|
| **Product row (collapsed)** | dot/badge (`--radius-badge`) + `--type-body` name + `--type-caption` state phrase (right-aligned or trailing) + chevron | Badge = worst of the product's 4 layers (worst-wins, one level down). Green dot only if **all four** parsed current+fresh+authed (never fabricated) |
| **Chevron** | ▸ collapsed / ▾ expanded, `--text-tertiary`, `--motion-fast` rotate | Redundant with the `aria-expanded` state; never the sole expand signal |
| **Layer row (expanded)** | indented `--space-lg`; small badge (same shape family) + `--type-caption` layer name + state | foundation / org / department / personal, fixed order. Badge+text per layer — **never colour alone**, a11y §1 applies per layer |
| **Dept-project entry** | further indented; `·` leader + `--type-caption` + "(project)" tag | A temporary department project, scoped under the Department tier |
| **Inline layer action** | plain (unfilled) `--radius-control` control at row-trailing | Only when that layer is the actionable one; the top primary action remains the single filled hero |
| **Layer badge palette** | reuses the status-glyph family tints (§ Design Tokens → Status semantics) | up-to-date = green dot · updating/repairing = brand ring · needs sign-in = key/indigo-blue · behind = info-blue dot · needs-attention = amber triangle |

**Air-Traffic Instrument continuity:** the product list reads like a departures board — one line per
product, a calm status per line, detail on request. No product row is ever emphasized by size or colour
when it is Healthy; the eye is drawn only to the product+layer that has something true to say.

### 3. Menu Row

28pt, `--space-md` horizontal padding, `--type-body`. States: **default** (transparent) · **hover**
(system selection tint, `--motion-fast`) · **focus** (visible ring, a11y §5) · **pressed** ·
**disabled** (`--text-tertiary`, non-focusable) · **destructive** (only ever "Quit"; no red flourish).
Every row exposes an accessibility label naming its action *and* its plain-language effect ("Repair —
fixes the finding IT can see"), a11y §2.

### 4. Wizard Panel

A real window (`--wizard-window`), `--surface-raised` body, brand-indigo header band. Two modes:

- **Silent managed path (0 questions):** a single centered progress view — the current phase named in
  `--type-wizard-title` ("Setting up Claude…") over a determinate progress bar. **No buttons, no
  questions.** This is the hero, and its design job is to be *calm and boring* — a spectator view, not an
  interactive form.
- **Unmanaged guided path (≤3 questions):** linear, mostly auto-advancing. The **device-flow code** is
  the one hero moment: the 8-char code in `--type-code-lg` (SF Mono, spaced) inside a `--radius-card`
  code box on `--surface-sunken`, with a copy button; focus lands on the code and it is
  keyboard-copyable (a11y §4). Department is a **numbered pick-list**, never a free-text field.
- **Honest holding screens** (IT-config-incomplete / Waiting-for-network) reuse the **same badge shape**
  as the glyph, at large size, above a calm sentence naming the state and who owns fixing it — visual
  continuity between glyph and screen so Bob learns the mark once.

### 5. Notification (rare by design)

The one Bob-facing alert tier — fires *only* when Bob is the sole competent actor for a non-deferrable
decision about his own data (P3). Visually a plain system notification: no custom chrome, no badge
count. Tone per `SOUL.md` §7 — **quiet past-tense** for auto-acted security ("Kept you safe — a security
fix replaced a component you'd overridden"), **direct and singular** for a Bob-owned action ("Commit
your unsaved personal work, then I'll sync"). When notifications are denied, the **popover opens** as
fallback (US-B16) — same content, no new visual language.

### 6. Admin / Fleet Dashboard — the one dense surface, same restrained language

Earl is technical; Hick's/Miller's limits relax here (UX Admin patterns). Density is *earned*, but the
tone is identical — **still no gamification, still shape+colour+text, still no computed "score."**

- **Fleet table** — rows = machines, `--dashboard-row-height` 32pt, zebra on `--surface-sunken`.
  Sortable by health family. The status cell renders the **same badge family** as the tray glyph plus a
  **status dot** + a **plain-language cell** naming the worst **product and layer** ("Codex Copilot —
  personal layer signed-out") — never colour alone, never a bare dot (a11y §1 applies to Earl too). A
  machine detail row expands to the same product × four-layer breakdown Bob's dropdown uses (Earl sees
  which product-layer on which machine). Healthy rows are the quietest: a plain green dot + "In sync
  across all products," no emphasis.
- **Red/green preflight** — a vertical checklist; each item is **✓ pass / ✕ fail** *shape* + green/red
  *tint* + a sentence. **Any red blocks deploy** and deep-links to the offending item. The shape (✓/✕)
  carries the verdict so it survives grayscale/colour-blindness.
- **Version-skew bar** — a single honest fraction ("83% on current SHA"), not a decorative gauge.
- **Govern queue** — actionable held-majors + time-boxed Bob items + content-free policy log, as a plain
  list. No item shown here is ever also shown to Bob.

**Dashboard visual restraint check:** no sparkline flourishes, no trophy rings, no "fleet health 94/100"
score. A number that looks *computed-by-us* would imply the app judges health — it renders CLI-parsed
facts only (`SOUL.md` *The Second Pilot*). The dashboard's job is legibility of truth, not a cockpit
fantasy.

---

## Visual References

Named products that embody **Air-Traffic Instrument** — what works, what we'd change. (These are
directional anchors, not templates; nothing here is cloned.)

| Reference | What works (adopt) | What to change (reject) |
|---|---|---|
| **macOS system menu extras** (Wi-Fi, Battery, Sound) | The gold standard for *native, monochrome, template-glyph-first, silent-when-fine*. This is exactly the register Control Tower lives in. | They carry no per-state badge vocabulary — we add the wrench/key/clock/dot family that names *which* thing. |
| **Tailscale menu-bar app** | Calm status-first menu, plain-language rows, no marketing chrome in the tray. | Occasionally leans on colour for state — we harden to shape-first, colour-second. |
| **Little Snitch / network monitors** | Instrument-panel legibility; dense fact display that never feels alarmist. | More visual texture than we want; we stay flatter and quieter. |
| **Linear (app chrome, restraint only)** | Disciplined type hierarchy, hairline separators, calm neutral palette, zero decoration — a model for the **Admin** surface's density. | Its brand-forward accents and product-marketing polish; our Admin surface is a utility, not a product showcase. |
| **Time Machine / Backblaze status** | Honest "backing up… / up to date" states, past-tense reassurance, no celebration of success. | Dated visual craft; we use current SF Pro / system materials. |

**Anti-references (studied to avoid):** any AI-product landing aesthetic (purple→pink gradient hero,
glow, shimmer); gamified observability dashboards (Datadog-style score rings, heat-map flourish as
decoration); iStat Menus at its densest (decorated, graph-heavy — the opposite of *silence is the
signal*).

---

## Traceability summary

| UI element | Primary trace |
|---|---|
| Air-Traffic Instrument direction (monochrome-first, colour-as-scalpel, silence=success) | `SOUL.md` §2/§6/§7; P1/P5; `00-vision.md` (trust by subtraction) |
| Anti-direction (no consumer-AI gradient, no gamified dashboard, no alarm-red) | `SOUL.md` anti-patterns (*Alert Machine*, *Second Pilot*, *Copilot of the Copilot*) |
| Status-glyph family (shape+badge+tint, template image, grayscale-legible) | UX STATE MATRIX; a11y §1/§6; US-B07/B08/B09; P4 |
| Status palette (Healthy = only green; red = only error) | UX matrix "colour never sole encoder"; a11y §1 |
| Dropdown popover — product-first list + inline four-layer expansion (contextual singular action, no approve control) | Owner's model (products × layers); Flow 6; US-B12/B15; Fitts's Law |
| Wizard (silent spectator + device-flow code + pick-list) | Flows 1–4; US-B01/B02; a11y §4 |
| Notification pattern (rare, past-tense/singular tone) | UX notification pattern; US-B13/B16/B17; `SOUL.md` §7 |
| Admin dashboard (dense but shape+colour+text, no score) | Flows 9–10; US-A05/A07; UX Admin patterns; *The Second Pilot* |
| Motion tokens (calm cross-fade, reduce-motion redundant) | UX microinteractions; a11y §7 |
| Naming: name "Copilot Control Tower" shown to user; aviator-sunglasses mark = tray glyph; "Aviator" codename retired | `00-overview/00-vision.md` (name); `03-design/ui-ux/README.md` (mark); `70-copy-voice.md` (banned codename) |

**Related:** [UX Design](50-ux-design.md) · [User Stories](../03-requirements/10-user-stories.md) ·
[SOUL](../../../SOUL.md) · [Vision](../00-overview/00-vision.md) ·
[Design-track brief](../../03-design/ui-ux/README.md)
