#!/usr/bin/env bash
# Shared release-source verification. This file provides validation functions;
# it is not an alternate packaging entry point and grants no release authority.

RELEASE_CANONICAL_REMOTE="https://github.com/Everyone-Needs-A-Copilot/copilot-control-tower.git"

release_source_die() {
    echo "error: $*" >&2
    return 1
}

release_reject_git_authority_environment() {
    local name
    while IFS= read -r name; do
        case "${name}" in
            GIT_CONFIG*|GIT_DIR|GIT_WORK_TREE|GIT_INDEX_FILE|\
            GIT_OBJECT_DIRECTORY|GIT_ALTERNATE_OBJECT_DIRECTORIES|\
            GIT_COMMON_DIR|GIT_CEILING_DIRECTORIES|\
            GIT_DISCOVERY_ACROSS_FILESYSTEM|GIT_EXEC_PATH|GIT_SSH|GIT_SSH_COMMAND|\
            GIT_ASKPASS|GIT_PROXY_COMMAND|GIT_PROTOCOL_FROM_USER|\
            GIT_ALLOW_PROTOCOL|GIT_SSL_NO_VERIFY|GIT_SSL_CAINFO|GIT_SSL_CAPATH|\
            GIT_TRACE*|GIT_CURL_VERBOSE|SSH_ASKPASS|SSH_ASKPASS_REQUIRE)
                release_source_die "Git authority environment is forbidden: ${name}" || return 1
                ;;
        esac
    done < <(compgen -e)
}

release_validate_platform_executable() {
    local helper="$1"
    local owner mode
    [[ -f "${helper}" && ! -L "${helper}" && -x "${helper}" ]] ||
        release_source_die "approved credential helper is missing, linked, or not executable" || return 1
    /usr/bin/codesign --verify --strict --requirements '=anchor apple' "${helper}" >/dev/null 2>&1 ||
        release_source_die "approved credential helper is not platform signed" || return 1
    owner="$(/usr/bin/stat -f '%u' "${helper}")"
    mode="$(/usr/bin/stat -f '%Lp' "${helper}")"
    [[ "${owner}" == "0" && $((8#${mode} & 8#022)) == 0 ]] ||
        release_source_die "approved credential helper ownership or mode is unsafe" || return 1
}

release_validate_apple_credential_helper() {
    local helper="$1"
    [[ "${helper}" == "/Applications/Xcode.app/Contents/Developer/usr/libexec/git-core/git-credential-osxkeychain" ]] ||
        release_source_die "credential helper is not the approved platform helper" || return 1
    release_validate_platform_executable "${helper}"
}

release_trusted_git() {
    local isolated helper rc had_errexit token basic
    local -a auth_env git_config
    isolated="$(mktemp -d "${TMPDIR:-/tmp}/ct-trusted-git.XXXXXX")" || return 1

    helper="/Applications/Xcode.app/Contents/Developer/usr/libexec/git-core/git-credential-osxkeychain"
    auth_env=()
    token="${GH_TOKEN:-${GITHUB_TOKEN:-}}"
    git_config=(
        -c credential.helper=
        -c protocol.file.allow=never
        -c protocol.ext.allow=never
        -c protocol.ssh.allow=never
        -c protocol.git.allow=never
        -c protocol.http.allow=never
        -c protocol.https.allow=always
        -c http.followRedirects=false
        -c include.path=/dev/null
    )
    if [[ -n "${token}" ]]; then
        basic="$(printf 'x-access-token:%s' "${token}" | /usr/bin/base64)"
        auth_env+=(
            GIT_CONFIG_COUNT=1
            GIT_CONFIG_KEY_0=http.https://github.com/.extraheader
            "GIT_CONFIG_VALUE_0=Authorization: Basic ${basic}"
        )
    else
        release_validate_apple_credential_helper "${helper}" || return 1
        git_config+=(
            -c credential.helper=
            -c "credential.https://github.com.helper=!${helper}"
        )
    fi

    had_errexit=0
    case "$-" in *e*) had_errexit=1 ;; esac
    set +e
    env -i \
        PATH=/usr/bin:/bin \
        HOME="${HOME}" \
        GIT_CONFIG_NOSYSTEM=1 \
        GIT_CONFIG_GLOBAL=/dev/null \
        GIT_CONFIG_SYSTEM=/dev/null \
        GIT_TERMINAL_PROMPT=0 \
        "${auth_env[@]}" \
        /usr/bin/git -C "${isolated}" "${git_config[@]}" "$@"
    rc=$?
    if [[ "${had_errexit}" == "1" ]]; then set -e; else set +e; fi
    rm -rf "${isolated}"
    return "${rc}"
}

release_resolve_remote_ref() {
    local remote="$1"
    local requested="$2"
    local head_ref tag_ref head_line tag_lines canonical_ref commit

    [[ "${remote}" == "${RELEASE_CANONICAL_REMOTE}" ]] ||
        release_source_die "release remote is not the approved HTTPS endpoint" || return 1
    [[ -n "${requested}" && "${requested}" != -* &&
       "${requested}" != *$'\n'* && "${requested}" != *$'\t'* ]] ||
        release_source_die "invalid release source ref: ${requested}" || return 1

    case "${requested}" in
        refs/heads/*)
            canonical_ref="${requested}"
            head_line="$(release_trusted_git ls-remote --exit-code "${remote}" "${canonical_ref}" 2>/dev/null)" ||
                release_source_die "approved remote does not advertise ${canonical_ref}" || return 1
            commit="${head_line%%[[:space:]]*}"
            ;;
        refs/tags/*)
            canonical_ref="${requested}"
            tag_lines="$(release_trusted_git ls-remote --exit-code "${remote}" "${canonical_ref}" "${canonical_ref}^{}" 2>/dev/null)" ||
                release_source_die "approved remote does not advertise ${canonical_ref}" || return 1
            commit="$(printf '%s\n' "${tag_lines}" | awk '$2 ~ /\^\{\}$/ { peeled=$1 } $2 !~ /\^\{\}$/ { direct=$1 } END { print peeled ? peeled : direct }')"
            ;;
        *)
            head_ref="refs/heads/${requested}"
            tag_ref="refs/tags/${requested}"
            head_line="$(release_trusted_git ls-remote "${remote}" "${head_ref}" 2>/dev/null)" ||
                release_source_die "could not inspect approved remote" || return 1
            tag_lines="$(release_trusted_git ls-remote "${remote}" "${tag_ref}" "${tag_ref}^{}" 2>/dev/null)" ||
                release_source_die "could not inspect approved remote" || return 1
            if [[ -n "${head_line}" && -n "${tag_lines}" ]]; then
                release_source_die "release source ref is ambiguous; use ${head_ref} or ${tag_ref}" || return 1
            elif [[ -n "${head_line}" ]]; then
                canonical_ref="${head_ref}"
                commit="${head_line%%[[:space:]]*}"
            elif [[ -n "${tag_lines}" ]]; then
                canonical_ref="${tag_ref}"
                commit="$(printf '%s\n' "${tag_lines}" | awk '$2 ~ /\^\{\}$/ { peeled=$1 } $2 !~ /\^\{\}$/ { direct=$1 } END { print peeled ? peeled : direct }')"
            else
                release_source_die "approved remote does not advertise ${requested}" || return 1
            fi
            ;;
    esac

    [[ "${commit}" =~ ^[0-9a-fA-F]{40,64}$ ]] ||
        release_source_die "approved remote returned an invalid commit for ${canonical_ref}" || return 1
    printf '%s\t%s\n' "${canonical_ref}" "${commit}"
}

release_verify_checkout() {
    local checkout="$1"
    local expected_remote="$2"
    local expected_ref="$3"
    local expected_commit="$4"
    local expected_tree="$5"
    local checkout_root actual_remote actual_commit actual_tree resolved resolved_ref resolved_commit

    checkout_root="$(cd "${checkout}" && pwd -P)" || return 1
    [[ "$(git -C "${checkout_root}" rev-parse --show-toplevel 2>/dev/null)" == "${checkout_root}" ]] ||
        release_source_die "release checkout is not the repository root" || return 1
    [[ -z "$(git -C "${checkout_root}" status --porcelain=v1 --untracked-files=all)" ]] ||
        release_source_die "verified release checkout is not clean" || return 1
    if git -C "${checkout_root}" symbolic-ref -q HEAD >/dev/null 2>&1; then
        release_source_die "verified release checkout must be detached" || return 1
    fi

    actual_remote="$(git -C "${checkout_root}" remote get-url origin 2>/dev/null)" ||
        release_source_die "verified release checkout has no origin" || return 1
    [[ "${actual_remote}" == "${expected_remote}" ]] ||
        release_source_die "verified release checkout origin is not the approved remote" || return 1

    actual_commit="$(git -C "${checkout_root}" rev-parse HEAD)"
    actual_tree="$(git -C "${checkout_root}" rev-parse 'HEAD^{tree}')"
    [[ "${actual_commit}" == "${expected_commit}" ]] ||
        release_source_die "verified release checkout HEAD changed" || return 1
    [[ "${actual_tree}" == "${expected_tree}" ]] ||
        release_source_die "verified release source tree changed" || return 1
    git -C "${checkout_root}" diff --quiet --ignore-submodules -- ||
        release_source_die "verified release checkout has unstaged changes" || return 1
    git -C "${checkout_root}" diff --cached --quiet --ignore-submodules -- ||
        release_source_die "verified release checkout has staged changes" || return 1

    resolved="$(release_resolve_remote_ref "${expected_remote}" "${expected_ref}")" || return 1
    IFS=$'\t' read -r resolved_ref resolved_commit <<< "${resolved}"
    [[ "${resolved_ref}" == "${expected_ref}" && "${resolved_commit}" == "${expected_commit}" ]] ||
        release_source_die "approved remote ref changed after checkout" || return 1
}
