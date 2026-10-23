#!/usr/bin/env bash
# Publish one Markdown file using the repository's Ruby/YAML dependencies.
set -euo pipefail

# Keep the caller's cwd so relative writing paths resolve as supplied.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR

exec "${SCRIPT_DIR}/bundle.sh" exec ruby "${SCRIPT_DIR}/publish.rb" "$@"
