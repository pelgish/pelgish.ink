#!/usr/bin/env bash
# Preview this repository with Ruby, Bundler, and the installed local bundle.
set -euo pipefail

# Translate only our public preview option; leave unrelated Jekyll options alone.
arguments=()
for argument in "$@"; do
    # Recognize only wrapper options; Jekyll retains ownership of other arguments.
    if [[ "${argument}" == --show-unpublished ]]; then
        arguments+=(--unpublished)
    elif [[ "${argument}" == --unpublished || "${argument}" == --unpublished=* ]]; then
        printf 'serve.sh: use --show-unpublished instead of --unpublished.\n' >&2
        exit 1
    elif [[ "${argument}" == -h || "${argument}" == --help ]]; then
        printf '%s\n' \
            'Usage: scripts/serve.sh [PORT] [--show-unpublished] [JEKYLL OPTIONS...]' \
            'Default port: 4000. PORT must be first, from 1 to 65535.' \
            'Use --show-unpublished to preview writing drafts (not --unpublished).' \
            'LiveReload defaults to HTTP port + 10000 (minus 10000 above 55535).' \
            'Override it with --livereload-port PORT; both ports must be available.' \
            'Other options are forwarded to Jekyll; use --port/-P instead of PORT.' \
            'Examples: scripts/serve.sh 4001 --show-unpublished --baseurl /preview' \
            '          scripts/serve.sh --host 127.0.0.1 --show-unpublished'
        exit 0
    else
        arguments+=("${argument}")
    fi
done

# Keep original argument boundaries while applying the wrapper translation.
set -- "${arguments[@]}"

# Translate an optional leading decimal port; leave Jekyll options untouched.
if [[ $# -gt 0 && ( "$1" != -* || "$1" =~ ^-[0-9] ) ]]; then
    if [[ ! "$1" =~ ^0*([1-9][0-9]{0,4})$ ]] || (( 10#${BASH_REMATCH[1]} > 65535 )); then
        printf 'serve.sh: invalid port "%s"; expected an integer from 1 to 65535.\n' "$1" >&2
        exit 1
    fi
    port="${BASH_REMATCH[1]}"
    shift

    # A positional port must not compete with a forwarded Jekyll port option.
    for argument in "$@"; do
        case "${argument}" in
            --port|--port=*|-P*)
                printf 'serve.sh: choose either a positional port or --port/-P, not both.\n' >&2
                exit 1
                ;;
        esac
    done
    set -- --port "${port}" "$@"
fi

# Inspect only the HTTP/LiveReload selectors needed for our default, not other options.
http_port=4000
explicit_livereload_port=false
expect_http_port=false
for argument in "$@"; do
    # Preserve every original argument for Jekyll, including explicit overrides.
    if [[ "${expect_http_port}" == true ]]; then
        http_port="${argument}"
        expect_http_port=false
    elif [[ "${argument}" == --port || "${argument}" == -P ]]; then
        expect_http_port=true
    elif [[ "${argument}" == --port=* ]]; then
        http_port="${argument#--port=}"
    elif [[ "${argument}" == -P?* ]]; then
        http_port="${argument#-P}"
    elif [[ "${argument}" == --livereload-port || "${argument}" == --livereload-port=* ]]; then
        explicit_livereload_port=true
    fi
done

# A separate deterministic port keeps parallel previews off Jekyll's shared 35729.
livereload_arguments=()
if [[ "${explicit_livereload_port}" != true ]]; then
    # Validate only the value used in arithmetic; native options still go to Jekyll.
    if [[ "${expect_http_port}" == true || ! "${http_port}" =~ ^0*([1-9][0-9]{0,4})$ ]] || (( 10#${BASH_REMATCH[1]} > 65535 )); then
        printf 'serve.sh: HTTP port must be an integer from 1 to 65535; use --port PORT or -P PORT.\n' >&2
        exit 1
    fi

    # Keep the default LiveReload port unprivileged and within the TCP port range.
    http_port="$((10#${BASH_REMATCH[1]}))"
    livereload_port="$((http_port + 10000))"
    if (( livereload_port > 65535 )); then
        livereload_port="$((http_port - 10000))"
    fi

    # An explicit caller-supplied LiveReload port bypasses this default entirely.
    livereload_arguments=(--livereload-port "${livereload_port}")
fi

# Resolve the checkout from the script location, not the caller's directory.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT
cd -- "${REPO_ROOT}"
export BUNDLE_GEMFILE="${REPO_ROOT}/Gemfile"

# Give setup guidance before attempting to start Jekyll.
for prerequisite in ruby; do
    if ! command -v "${prerequisite}" >/dev/null 2>&1; then
        printf 'serve.sh: missing %s; follow README.md local setup first.\n' "${prerequisite}" >&2
        exit 1
    fi
done

if ! "${SCRIPT_DIR}/bundle.sh" check; then
    printf 'serve.sh: dependencies unavailable; run %s/scripts/setup-dependencies.sh.\n' "${REPO_ROOT}" >&2
    exit 1
fi

if ! "${SCRIPT_DIR}/bundle.sh" exec jekyll --version; then
    printf 'serve.sh: Jekyll cannot run; run scripts/setup-dependencies.sh (see README.md).\n' >&2
    exit 1
fi

# Replace the wrapper so Ctrl+C reaches Jekyll.
exec "${SCRIPT_DIR}/bundle.sh" exec jekyll serve --livereload "$@" "${livereload_arguments[@]}"
