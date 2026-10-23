#!/usr/bin/env bash
# Set up local Ruby/Jekyll dependencies; system package changes require opt-in.
set -euo pipefail

# Print usage before checking prerequisites, so help works without Ruby.
usage() {
    printf '%s\n' \
        'Usage: scripts/setup-dependencies.sh [--install-system-dependencies]' \
        'Install locked Bundler in .bundle/tools if missing, and gems in vendor/bundle.' \
        'Requires Bash, Ruby >=3.2 and <4, RubyGems, Ruby headers, make, gcc, g++,' \
        'pkg-config, and Ruby OpenSSL/zlib with CA certificates.' \
        'System package installation is opt-in and supported only on Debian/Ubuntu' \
        'with apt-get (sudo required unless already root). No server is started.' \
        'Other platforms must supply prerequisites manually; see README.md.' \
        '  -h, --help                         Show this help' \
        '  --install-system-dependencies     Install missing system prerequisites'
}

# Accept only the explicit system-install opt-in and help options.
install_system=false
for argument in "$@"; do
    # Reject unknown arguments before any setup or installation can happen.
    if [[ "${argument}" == -h || "${argument}" == --help ]]; then
        usage
        exit 0
    elif [[ "${argument}" == --install-system-dependencies ]]; then
        install_system=true
    else
        printf 'setup-dependencies.sh: unknown argument "%s"; use --help.\n' "${argument}" >&2
        exit 1
    fi
done

# Resolve all project-local paths relative to this script rather than the caller.
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
readonly SCRIPT_DIR
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
readonly REPO_ROOT
cd -- "${REPO_ROOT}"
readonly BUNDLE="${SCRIPT_DIR}/bundle.sh"

# Limit automatic system installation to the explicitly supported distro family.
supported_system=false
if [[ "$(uname -s)" == Linux && -r /etc/os-release ]]; then
    # os-release is a trusted system file, not repository-supplied configuration.
    . /etc/os-release

    # Similar distributions are not implicitly treated as supported platforms.
    if [[ "${ID:-}" == ubuntu || "${ID:-}" == debian ]]; then
        supported_system=true
    fi
fi

# Use the distribution packages for Ruby, native extension builds, and HTTPS.
readonly PACKAGES=(ruby ruby-dev build-essential pkg-config libssl-dev zlib1g-dev ca-certificates)

# Report concrete missing tools and Ruby development/runtime components.
find_missing() {
    missing=()
    for prerequisite in ruby gem make gcc g++ pkg-config; do
        # Missing commands are reported together rather than one per retry.
        if ! command -v "${prerequisite}" >/dev/null 2>&1; then
            missing+=("${prerequisite}")
        fi
    done

    # Runtime Ruby alone is insufficient when native extensions need compilation.
    if command -v ruby >/dev/null 2>&1; then
        # Check the headers for the active Ruby, not just a distro package name.
        if ! ruby -rrbconfig -e 'exit File.file?(File.join(RbConfig::CONFIG.fetch("rubyhdrdir"), "ruby.h"))'; then
            missing+=("Ruby development headers (ruby.h)")
        fi

        # RubyGems downloads require these runtime modules and certificate trust.
        if ! ruby -ropenssl -rzlib -e 'exit File.file?(OpenSSL::X509::DEFAULT_CERT_FILE)'; then
            missing+=("Ruby OpenSSL/zlib and CA certificates")
        fi
    fi
}

# Never modify system packages unless prerequisites are missing and opt-in is set.
find_missing
if (( ${#missing[@]} > 0 )); then
    printf 'setup-dependencies.sh: missing prerequisite: %s\n' "${missing[@]}" >&2

    # Without permission, print the supported manual recovery command instead.
    if [[ "${install_system}" != true ]]; then
        # Other platforms must obtain the reported prerequisites themselves.
        if [[ "${supported_system}" == true ]]; then
            printf 'Re-run with --install-system-dependencies to opt in, or run:\n  sudo apt-get update\n  sudo apt-get install -y %s\n' "${PACKAGES[*]}" >&2
        else
            printf 'Install the listed prerequisites using your platform tools, then retry. Automatic installation supports only Debian/Ubuntu with apt-get.\n' >&2
        fi

        # Exit before any privileged operation.
        exit 1
    fi

    # Even explicit opt-in cannot enable an unsupported package manager.
    if [[ "${supported_system}" != true ]] || ! command -v apt-get >/dev/null 2>&1; then
        printf 'setup-dependencies.sh: system installation supports only Debian/Ubuntu with apt-get; install the listed prerequisites manually.\n' >&2
        exit 1
    fi

    # Request privileges only for apt, never for RubyGems or project files.
    privilege=()
    if (( EUID != 0 )); then
        # Fail with an administrator command rather than attempting another escalator.
        if ! command -v sudo >/dev/null 2>&1; then
            printf 'setup-dependencies.sh: sudo is missing; ask an administrator to run apt-get update and apt-get install -y %s.\n' "${PACKAGES[*]}" >&2
            exit 1
        fi

        # Root can invoke apt directly; normal users use sudo.
        privilege=(sudo)
    fi

    # Surface package index failures before attempting installation.
    if ! "${privilege[@]}" apt-get update; then
        printf 'setup-dependencies.sh: apt-get update failed; fix the package manager error above and retry.\n' >&2
        exit 1
    fi

    # Install only the documented local development prerequisites.
    if ! "${privilege[@]}" apt-get install -y "${PACKAGES[@]}"; then
        printf 'setup-dependencies.sh: apt-get install failed; fix the package manager error above and retry.\n' >&2
        exit 1
    fi

    # Verify the actual active tools after apt, including non-system Ruby installs.
    find_missing
    if (( ${#missing[@]} > 0 )); then
        printf 'setup-dependencies.sh: still missing after system installation: %s\n' "${missing[@]}" >&2
        exit 1
    fi
fi

# Older distro Ruby versions require a deliberate user-managed upgrade.
if ! ruby -e 'exit Gem::Requirement.new(">= 3.2", "< 4.0").satisfied_by?(Gem::Version.new(RUBY_VERSION))'; then
    printf 'setup-dependencies.sh: Ruby >=3.2 and <4 is required; install Ruby 3.3 (see .ruby-version) and matching development headers, then retry. Older distro Ruby is not upgraded automatically.\n' >&2
    exit 1
fi

# Read Bundler's exact lockfile version rather than choosing the latest release.
bundler_version="$(ruby -e '
    version = File.read("Gemfile.lock")[/^BUNDLED WITH\n\s+(\S+)/, 1]
    abort "setup-dependencies.sh: Gemfile.lock has no BUNDLED WITH version" unless version
    puts version
')"
readonly bundler_version

# Reuse compatible installed Bundler before downloading a project-local copy.
if ! "${BUNDLE}" --version; then
    printf 'Installing Bundler %s locally...\n' "${bundler_version}"

    # RubyGems failures must stop setup without claiming success.
    if ! gem install bundler --version "${bundler_version}" --no-document --install-dir "${REPO_ROOT}/.bundle/tools"; then
        printf 'setup-dependencies.sh: local Bundler installation failed; check the RubyGems error above and retry.\n' >&2
        exit 1
    fi

    # Confirm the launcher can find the new installation.
    "${BUNDLE}" --version
fi

# Frozen mode fails on manifest/platform mismatches instead of rewriting the lock.
export BUNDLE_FROZEN=true
"${BUNDLE}" config set --local path vendor/bundle

# A complete bundle needs no install; missing gems must install successfully.
if ! "${BUNDLE}" check; then
    # Keep Bundler's own error details and add an explicit setup failure message.
    if ! "${BUNDLE}" install; then
        printf 'setup-dependencies.sh: locked bundle installation failed; resolve the error above and retry. Gemfile.lock was not updated.\n' >&2
        exit 1
    fi
fi

# Recheck before printing the exact development and test commands.
"${BUNDLE}" check
printf 'Setup complete. Run:\n  cd %q\n  ./scripts/serve.sh\n  ./scripts/serve.sh --show-unpublished\n  ./scripts/bundle.sh exec ruby scripts/check.rb\n  JEKYLL_ENV=production ./scripts/bundle.sh exec jekyll build --trace\n' "${REPO_ROOT}"
