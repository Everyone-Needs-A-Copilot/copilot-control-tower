---
id: ccccb8b3-8d0e-48c1-9e9f-b8bcca17d878
type: decision
tags: []
created: 2026-07-21T15:13:41Z
updated: 2026-07-21T15:13:41Z
scope: project
---

cli-copilot-internal: migrated 11 non-secret config keys (git_user_name/email, uspto_cli_base_url, discord_channel_id/allowed_user_ids/webhook_username/avatar_url, nocodb_base_id, project_copilot_base_url/web_url, conversations_base_url) from gitignored .env into committed cli.overlay.yml adopt[].config/provides[].config using the ADR-001 fold. Verified via isolated no-.env scratch mirror test (copilot_overlay_internal/tests/test_overlay_config_migration.py, 3 tests) + confirmed live .env/mirror byte-untouched. Flag: guide called the nocodb service 'nocodb' but the actual overlay service name is 'crm' (module copilot_overlay_internal.services.nocodb.commands) -- config added under 'crm'. Not committed.
