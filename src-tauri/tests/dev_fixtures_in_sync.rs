//! Fails CI if `src/dev-fixtures/*.json` (T7's static data before the live
//! IPC seam exists) has drifted from what `examples/gen_dev_fixtures.rs`
//! would produce right now. If this fails: re-run
//! `cargo run --example gen_dev_fixtures` and commit the result.

use copilot_control_tower_lib::model::state::parse_doctor_body;
use copilot_control_tower_lib::render::derive::derive_render_state;
use std::fs;
use std::path::Path;

#[test]
fn dev_fixtures_match_the_real_derive_pipeline() {
    let manifest_dir = Path::new(env!("CARGO_MANIFEST_DIR"));
    let dev_fixtures_dir = manifest_dir
        .parent()
        .expect("src-tauri has a parent directory")
        .join("src/dev-fixtures");

    let mut checked = 0usize;
    for sub in ["fixtures/corpus", "fixtures/invalid"] {
        let dir = manifest_dir.join(sub);
        for entry in fs::read_dir(&dir).unwrap_or_else(|e| panic!("read {}: {e}", dir.display())) {
            let path = entry.expect("dir entry").path();
            if path.extension().and_then(|e| e.to_str()) != Some("json") {
                continue;
            }
            let name = path
                .file_stem()
                .and_then(|s| s.to_str())
                .expect("utf8 file stem")
                .to_string();
            let raw = fs::read(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
            let outcome = parse_doctor_body(&raw);
            let render_state = derive_render_state(&outcome);
            let expected = format!(
                "{}\n",
                serde_json::to_string_pretty(&render_state).expect("serialize RenderState")
            );

            let dev_fixture_path = dev_fixtures_dir.join(format!("{name}.json"));
            let actual = fs::read_to_string(&dev_fixture_path).unwrap_or_else(|e| {
                panic!(
                    "missing dev fixture {} ({e}) — run `cargo run --example gen_dev_fixtures`",
                    dev_fixture_path.display()
                )
            });
            assert_eq!(
                actual, expected,
                "src/dev-fixtures/{name}.json is stale — run `cargo run --example gen_dev_fixtures`"
            );
            checked += 1;
        }
    }
    assert!(checked > 0, "expected to check at least one fixture");
}
