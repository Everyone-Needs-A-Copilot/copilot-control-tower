#!/usr/bin/env bash
# Build a MINIMAL, deterministic onboard topology fixture: one bare "remote"
# + one matching visible checkout per (component x role), all in the `exact`
# history state (no departments). Used by PKG-01 (test_walkthrough_05_08_
# acceptance.sh) and verify-vendored-cc.sh for a lightweight "does this
# binary emit a real, schema-valid topology report" smoke check. The full
# eight-history-state, sixteen-row contract lives in
# test_packaged_cc_topology_contract.sh -- this is deliberately smaller.
#
# Usage: build-minimal-fixture.sh <scratch-root>
#
# Writes:
#   <scratch-root>/remotes/          bare repos
#   <scratch-root>/repo-root/        visible checkouts (--repository-root)
#   <scratch-root>/handoff.b64       base64 ecosystem.yml the gh-stub serves
# Prints <scratch-root>/repo-root to stdout (last line) plus these fixed,
# documented constants callers need to invoke the gh-stub/fake-ssh fixtures:
#   org=fixture-org owner=fixture-owner

set -euo pipefail

SCRATCH_ROOT="${1:?usage: build-minimal-fixture.sh <scratch-root>}"
FIXTURE_ORG="fixture-org"
FIXTURE_OWNER="fixture-owner"

REMOTES_DIR="${SCRATCH_ROOT}/remotes"
REPO_ROOT_DIR="${SCRATCH_ROOT}/repo-root"
mkdir -p "${REMOTES_DIR}" "${REPO_ROOT_DIR}"

export HOME="${SCRATCH_ROOT}/fixture-author-home"
mkdir -p "${HOME}"
git config --global user.email "fixture@example.invalid"
git config --global user.name "Fixture Author"
git config --global init.defaultBranch main

for component in knowledge cli claude codex; do
    for role in personal organization foundation; do
        case "${role}" in
            personal)
                repo_name="${component}-copilot-private"
                url="git@github-personal:${FIXTURE_OWNER}/${repo_name}.git"
                ref="main"
                ;;
            organization)
                repo_name="${component}-copilot-internal"
                url="git@github-work:${FIXTURE_ORG}/${repo_name}.git"
                ref="main"
                ;;
            foundation)
                repo_name="${component}-copilot"
                ref="1.0.0"
                if [[ "${component}" == "knowledge" || "${component}" == "cli" ]]; then
                    url="git@github-work:Everyone-Needs-A-Copilot/${repo_name}.git"
                else
                    url="https://github.com/Everyone-Needs-A-Copilot/${repo_name}.git"
                fi
                ;;
        esac

        local_path="${REPO_ROOT_DIR}/${repo_name}"

        git init --bare -q -b main "${REMOTES_DIR}/${repo_name}.git"
        bare="${REMOTES_DIR}/${repo_name}.git"
        work="$(mktemp -d "${SCRATCH_ROOT}/work.XXXXXX")"
        git init -q -b main "${work}"
        echo seed > "${work}/seed.txt"
        git -C "${work}" add seed.txt
        git -C "${work}" commit -q -m seed
        if [[ "${role}" == foundation ]]; then
            git -C "${work}" tag "${ref}"
            git -C "${work}" push -q "${bare}" main "${ref}"
        else
            git -C "${work}" push -q "${bare}" main
        fi
        git clone -q "${bare}" "${local_path}"
        git -C "${local_path}" remote set-url origin "${url}"
        rm -rf "${work}"
    done
done

cat > "${SCRATCH_ROOT}/handoff.yml" <<YAML
schema_version: "2.0"
org: ${FIXTURE_ORG}
harness:
  - claude
  - codex
components:
  - knowledge
  - cli
  - claude
  - codex
foundation:
  refs:
    knowledge: "1.0.0"
    cli: "1.0.0"
    claude: "1.0.0"
    codex: "1.0.0"
YAML
base64 < "${SCRATCH_ROOT}/handoff.yml" | tr -d '\n' > "${SCRATCH_ROOT}/handoff.b64"

echo "${REPO_ROOT_DIR}"
