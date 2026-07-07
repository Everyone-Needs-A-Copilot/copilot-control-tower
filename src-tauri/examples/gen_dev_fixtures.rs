//! Dev-tool (T3): regenerates `src/dev-fixtures/*.json` by running every T2
//! `fixtures/corpus/` and `fixtures/invalid/` file through the real
//! parse (`model::state::parse_doctor_body`) + derive
//! (`render::derive::derive_render_state`) pipeline. The dev fixtures are
//! never hand-authored, so they can't drift from what the real Rust code
//! actually produces — T7 builds the popover against these before the live
//! `get_state()`/`state-changed` IPC seam exists (T8).
//!
//! Run after any change to the corpus or the derive logic:
//!
//! ```sh
//! cargo run --example gen_dev_fixtures
//! ```
//!
//! `tests/dev_fixtures_in_sync.rs` fails CI if someone forgets to re-run
//! this and commit the result.

use copilot_control_tower_lib::model::state::parse_doctor_body;
use copilot_control_tower_lib::render::derive::derive_render_state;
use std::fs;
use std::path::Path;

fn main() {
    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let out_dir = manifest_dir
        .parent()
        .expect("src-tauri has a parent directory")
        .join("src/dev-fixtures");
    fs::create_dir_all(&out_dir).unwrap_or_else(|e| panic!("create {}: {e}", out_dir.display()));

    let mut written = 0usize;
    for sub in ["fixtures/corpus", "fixtures/invalid"] {
        let dir = manifest_dir.join(sub);
        let mut entries: Vec<_> = fs::read_dir(&dir)
            .unwrap_or_else(|e| panic!("read {}: {e}", dir.display()))
            .map(|e| e.expect("dir entry").path())
            .filter(|p| p.extension().and_then(|e| e.to_str()) == Some("json"))
            .collect();
        entries.sort();

        for path in entries {
            let name = path
                .file_stem()
                .and_then(|s| s.to_str())
                .expect("utf8 file stem")
                .to_string();
            let raw = fs::read(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
            let outcome = parse_doctor_body(&raw);
            let render_state = derive_render_state(&outcome);
            let json = serde_json::to_string_pretty(&render_state).expect("serialize RenderState");
            let out_path = out_dir.join(format!("{name}.json"));
            fs::write(&out_path, format!("{json}\n"))
                .unwrap_or_else(|e| panic!("write {}: {e}", out_path.display()));
            written += 1;
        }
    }
    println!("wrote {written} dev fixtures to {}", out_dir.display());
}
