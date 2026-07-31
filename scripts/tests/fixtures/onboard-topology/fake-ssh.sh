#!/bin/bash
# Fake SSH transport for scripts/tests/test_packaged_cc_topology_contract.sh
# (task 209), set as GIT_SSH_COMMAND. Real cc/onboard.py always builds
# organization/department/personal layer remotes (and the private-foundation
# knowledge/cli layers) as `git@github-work:...`/`git@github-personal:...`
# SCP-style SSH URLs -- never overridable via CLI flag. Rather than run a
# real sshd or rewrite these URLs with `url.*.insteadOf` (which would also
# silently rewrite what `git remote get-url origin` reports, corrupting this
# gate's wrong-origin/exact classification checks -- `git remote get-url`
# expands insteadOf by design), this script IS the SSH transport: git invokes
# it as `<this> <host> "git-upload-pack '<owner>/<repo>.git'"`; it ignores
# the host and alias/owner prefix entirely and execs the real git service
# command directly against a same-named bare repo under
# FAKE_SSH_REMOTES_DIR, with no network, no sshd, and no config file.
set -uo pipefail

: "${FAKE_SSH_REMOTES_DIR:?FAKE_SSH_REMOTES_DIR must be set}"

# git first probes its ssh variant with `-G -o SendEnv=... <host>` to decide
# whether to add OpenSSH-only flags. Refusing this (exit 1) makes git fall
# back to the plain `<ssh> <host> <command>` invocation handled below.
if [[ "${1:-}" == "-G" ]]; then
    exit 1
fi

command_str="${*: -1}"
service="${command_str%% *}"
path="${command_str#*\'}"
path="${path%\'}"
repo_name="$(basename "${path}")"

case "${service}" in
    git-upload-pack|git-receive-pack|git-upload-archive) ;;
    *)
        echo "fake-ssh: unsupported service '${service}'" >&2
        exit 1
        ;;
esac

bare="${FAKE_SSH_REMOTES_DIR}/${repo_name}"
if [[ ! -d "${bare}" ]]; then
    echo "fake-ssh: no fixture remote at ${bare}" >&2
    exit 1
fi

exec "${service}" "${bare}"
