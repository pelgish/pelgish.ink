#!/usr/bin/env bash
# Publish one Markdown file using the repository's Ruby/YAML dependencies.
set -euo pipefail

# Keep the caller's cwd so relative writing paths resolve as supplied.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
export BUNDLE_GEMFILE="${SCRIPT_DIR}/../Gemfile"

for prerequisite in ruby; do
    if ! command -v "${prerequisite}" >/dev/null 2>&1; then
        printf 'publish.sh: missing %s; follow README.md local setup first.\n' "${prerequisite}" >&2
        exit 1
    fi
done

# Argument and document validation happen before the helper writes anything.
exec "${SCRIPT_DIR}/bundle.sh" exec ruby "${SCRIPT_DIR}/publish.rb" "$@"
