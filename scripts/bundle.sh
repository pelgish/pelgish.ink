#!/usr/bin/env bash
# Run the locked Bundler, including a project-local installation made by setup.
set -euo pipefail

# Locate the manifest without changing the caller's working directory.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
export BUNDLE_GEMFILE="${SCRIPT_DIR}/../Gemfile"

# Provide setup guidance even when Ruby itself is unavailable.
if ! command -v ruby >/dev/null 2>&1; then
    printf 'bundle.sh: missing Ruby; run scripts/setup-dependencies.sh first.\n' >&2
    exit 1
fi

# Keep the caller's cwd and normal gem paths; do not rewrite their environment.
exec ruby -e '
    root = File.expand_path(ARGV.shift)
    version = File.read(File.join(root, "Gemfile.lock"))[/^BUNDLED WITH\n\s+(\S+)/, 1]
    abort "bundle.sh: Gemfile.lock has no BUNDLED WITH version" unless version
    Gem.use_paths(Gem.dir, [File.join(root, ".bundle/tools"), *Gem.path])
    begin
        gem "bundler", version
    rescue Gem::LoadError
        abort "bundle.sh: missing Bundler #{version}; run scripts/setup-dependencies.sh first."
    end
    load Gem.bin_path("bundler", "bundle", version)
' "${SCRIPT_DIR}/.." "$@"
