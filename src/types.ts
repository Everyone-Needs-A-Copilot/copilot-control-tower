/**
 * The web UI's view of Rust's typed domain state (`src-tauri/src/model/state.rs`).
 *
 * This mirrors the DTO Rust serializes for `get_state()` / the `state-changed`
 * event — never the raw `cc doctor --json` wire shape. The UI must not be able
 * to reinterpret unparsed CLI output; parsing and fail-closed defaulting happen
 * exclusively in Rust (`model/`), per the parse-never-compute boundary.
 *
 * T7 scope: this is the `RenderState` contract shared with T3 (see the T7 task
 * brief). T3 owns the authoritative Rust struct; this file is the TS mirror.
 * Until T3's real DTO lands, T7 builds to this shape directly from the T2
 * corpus (`src-tauri/fixtures/corpus/*.json`) via `src/dev-fixtures/*.json` —
 * T8 reconciles any drift once the real `get_state()` return type exists.
 */

/** The 10 CLI-emitted status values, mapped 1:1 from `doctor.status` (ADR-M1-001). */
export type CliStatus =
  | "setup-needed"
  | "it-config-incomplete"
  | "healthy"
  | "syncing"
  | "update-available"
  | "needs-attention"
  | "signed-out"
  | "offline"
  | "waiting-for-network"
  | "updating-app";

/** The 11th, APP-OWNED state — never CLI-emitted; chosen only from I/O/schema failure. */
export type CliUnreadableReason =
  | "io_error"
  | "parse_error"
  | "schema_out_of_range"
  | "missing_security_field"
  | "exit_2"
  | "invalid_content";

export type Severity = "pass" | "warn" | "fail";
export type LayerSeverity = Severity | "none";

export type Layer = "foundation" | "org" | "dept" | "personal";

/**
 * The badge SHAPE vocabulary (60-ui-design.md § Status-Glyph Family / § Layer
 * badge palette). Shape is the primary encoder — every value here must be
 * legible with colour fully stripped. `badges.ts` is the only module that
 * interprets this union into a rendered mark.
 *
 * T8: this is the SAME 12-token set as Rust's canonical
 * `render::BADGE_VOCABULARY` (`src-tauri/src/render/mod.rs`) — every token
 * `CliStatus::glyph_badge()`/`render::derive::severity_badge` can produce.
 * `src-tauri/tests/fitness_badge_vocabulary.rs` cross-checks this union and
 * `badges.ts`'s `drawShape` switch against that Rust list on every CI run,
 * so the two sides cannot silently drift apart again.
 */
export type BadgeState =
  | "pass" // up-to-date — green dot (layer/product only, never the tray glyph)
  | "ring" // syncing / updating / repairing in the background
  | "key" // needs sign-in
  | "update" // update-available — info-blue dot
  | "triangle" // needs-attention — amber triangle
  | "wrench" // IT-config-incomplete
  | "clock" // waiting-for-network
  | "cloud-slash" // offline
  | "bang" // CLI-unreadable / Error — the only red, the only "!"
  | "spinner" // updating-app (Control Tower self-update)
  | "hollow" // setup-needed — hollow outline, slow pulse
  | "none"; // no data for this bucket

export interface LayerView {
  layer: Layer;
  severity: LayerSeverity;
  badge_state: BadgeState;
  detail: string | null;
  /** A temporary department project scoped under this layer (dept only). */
  projects?: DeptProjectView[];
}

export interface DeptProjectView {
  name: string;
  severity: LayerSeverity;
  badge_state: BadgeState;
  detail: string | null;
}

export interface ProductView {
  product: string;
  worst_severity: Severity;
  layers: LayerView[];
}

export interface AuthIssue {
  identity: string;
  scope: string;
  state: "expired" | "revoked";
  expires_at: string | null;
}

export interface HeaderView {
  /** Same badge vocabulary as the tray glyph — worst state across all products x layers. */
  glyph_state: BadgeState;
  /** The one honest status sentence, per 70-copy-voice.md. Never fabricated. */
  sentence: string;
}

export type ClientState = "ok" | "cli_unreadable";

/**
 * The shared render contract (T3/T7). The web UI renders this and only this —
 * no computed score, no worst-wins ladder computed in TS, no verdict beyond
 * what's already in the fields below.
 */
export interface RenderState {
  client_state: ClientState;
  cli_unreadable_reason: CliUnreadableReason | null;
  host: string | null;
  status: CliStatus | null;
  offline: boolean;
  header: HeaderView;
  products: ProductView[];
  auth_issues: AuthIssue[];
}

/** T1 IPC seam alias — the DTO crossing `get_state()` / `state-changed` is a `RenderState`. */
export type TrayStateDto = RenderState;

/** Event name Rust emits on `state-changed` (see src-tauri/src/commands.rs). */
export const STATE_CHANGED_EVENT = "state-changed" as const;

/**
 * Settings (M2, S1) — the layer-manifest IPC DTOs. Mirrors
 * `src-tauri/src/settings/dto.rs` field-for-field (plain snake_case on both
 * sides, same convention as `RenderState` above — no camelCase translation
 * layer).
 *
 * S1 froze this shape; `get_settings()` / `save_settings()` (S6) now cross
 * this seam for real, and S8 folded S7's standalone `src/settings-types.ts`
 * copy in here as the single authoritative source once the two could safely
 * be merged (that file's own header explains why it existed separately in
 * the meantime — a deliberate anti-merge-conflict measure, not drift).
 * `repo_url`/`auth_ref` are non-null `string` — Rust always projects a
 * missing value to `""` (`commands::project_row`'s `unwrap_or_default()`),
 * never `null`, so the UI's own "not set up" / "needs sign-in" checks read
 * an empty string, not an absent field.
 */

/**
 * The three tiers Settings can author (D-1-M2). Foundation is the base tier
 * and is never user-authored via Settings, so it has no member here.
 */
export type Tier = "org" | "dept" | "personal";

export interface FieldError {
  /** `null` for a manifest-wide problem not attributable to one layer. */
  layer_id: string | null;
  field: string;
  /**
   * Plain language always — never raw yaml/git/serde text (SOUL "a Git
   * error to a non-technical person").
   */
  message: string;
}

export interface LayerRow {
  id: string;
  product: string;
  tier: Tier;
  repo_url: string;
  /** A REFERENCE only (e.g. "ssh-personal", "anon") — never a credential value (D-4). */
  auth_ref: string;
  rank: number;
  /** `false` on a managed machine for a locked org/dept row (S5's managed gate). */
  editable: boolean;
}

/** The full Settings surface `get_settings()` returns (S6). */
export interface SettingsState {
  /** `true` when a forced/managed-domain ecosystem is present (S5). */
  managed: boolean;
  layers: LayerRow[];
  /** Every current validation problem, plain language. Empty means valid. */
  errors: FieldError[];
}

/**
 * What the UI submits on save (S7 -> S6 -> S4). `rank`/`id`/`auth_ref` are
 * NOT here — they're derived Rust-side (decision-gated on D-1-M2), never
 * sent from the UI, and the assembly step never probes the repo (invariant
 * #1: no network I/O in authoring).
 */
export interface LayerInput {
  product: string;
  tier: Tier;
  repo_url: string;
}
